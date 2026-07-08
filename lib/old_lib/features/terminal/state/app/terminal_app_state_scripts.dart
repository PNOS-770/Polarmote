import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dartssh2/dartssh2.dart';

import '../../../../shared/constants/app_string.dart';
import '../../../../shared/notifications/asmote_system_notifications.dart';
import '../../../../shared/utils/cron_expression.dart';
import '../../models/host_entry.dart';
import '../../models/terminal_session.dart';
import '../../models/script_entry.dart';
import '../../models/script_run_session.dart';
import '../../models/ssh_connection_pool.dart';
import '../../models/script_schedule_entry.dart';
import '../../models/terminal_tab.dart';
import '../../models/workflow_node.dart';
import '../terminal_app_state.dart';

part 'terminal_app_state_scripts_execution.dart';

final Expando<List<ScriptRunEvent>> _scriptRunEventsByState =
    Expando<List<ScriptRunEvent>>('script-run-events');
final Expando<Timer> _scriptScheduleTimerByState = Expando<Timer>(
  'script-schedule-timer',
);
final Expando<Set<String>> _scriptScheduleRunningByState = Expando<Set<String>>(
  'script-schedule-running',
);
final Expando<Map<String, _ScriptRunProgressState>> _scriptRunProgressByState =
    Expando<Map<String, _ScriptRunProgressState>>('script-run-progress');
final Expando<Map<String, int>> _scriptRunningCountByState =
    Expando<Map<String, int>>('script-running-count');
final Expando<Map<String, ScriptRunStatus>> _scriptLastStatusByState =
    Expando<Map<String, ScriptRunStatus>>('script-last-status');

const int _scriptRunEventLimit = 1200;
const int _scriptOutputSnippetLimit = 320;
const int _scriptScheduleCatchUpMaxPerTick = 12;

final RegExp _scriptTemplatePattern = RegExp(r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}');
final RegExp _scriptIncludePattern = RegExp(
  r'^@script\s*:\s*(.+)$',
  caseSensitive: false,
);

String _randomHex(int len) {
  final rng = Random();
  final bytes = List<int>.generate((len + 1) ~/ 2, (_) => rng.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().substring(0, len);
}

String _markerPrefix(String token) => '__ASMOTE_${token}__';

enum ScriptRunEventType {
  runStarted,
  targetStarted,
  stepStarted,
  stdout,
  stderr,
  stepSucceeded,
  stepFailed,
  targetSucceeded,
  targetFailed,
  runFinished,
}

enum ScriptRunStatus { idle, running, success, failed }

class ScriptRunEvent {
  const ScriptRunEvent({
    required this.runId,
    required this.type,
    required this.timestamp,
    required this.target,
    this.targetId,
    this.stepIndex,
    this.message,
    this.command,
  });

  final String runId;
  final ScriptRunEventType type;
  final DateTime timestamp;
  final String target;
  final String? targetId;
  final int? stepIndex;
  final String? message;
  final String? command;
}

extension TerminalAppStateScripts on TerminalAppState {
  void updateScriptLastRunConfig({
    required String scriptId,
    required List<String> hostIds,
    required List<LocalShellType> localShellTypes,
    required bool notifyEnabled,
    required bool silentExecution,
    required ScriptFailurePolicy failurePolicy,
    int retryPerHost = 1,
    Map<String, String> templateArgs = const <String, String>{},
    Map<String, String> environmentOverrides = const <String, String>{},
    int maxConcurrency = 1,
  }) {
    final index = scripts.indexWhere((script) => script.id == scriptId);
    if (index < 0) {
      return;
    }
    scripts[index] = scripts[index].copyWith(
      updatedAt: DateTime.now(),
      lastRunConfig: ScriptLastRunConfig(
        hostIds: hostIds.toList(growable: false),
        localShellTypes: localShellTypes.toList(growable: false),
        notifyEnabled: notifyEnabled,
        silentExecution: silentExecution,
        failurePolicy: failurePolicy,
        retryPerHost: retryPerHost.clamp(1, 6),
        templateArgs: Map<String, String>.from(templateArgs),
        environmentOverrides: Map<String, String>.from(environmentOverrides),
        maxConcurrency: maxConcurrency.clamp(1, 8),
      ),
    );
    scheduleStateSave();
    notifyState();
  }

  void resetScriptLastRunConfig(String scriptId) {
    final index = scripts.indexWhere((script) => script.id == scriptId);
    if (index < 0) {
      return;
    }
    final current = scripts[index];
    scripts[index] = current.copyWith(
      updatedAt: DateTime.now(),
      lastRunConfig: const ScriptLastRunConfig(
        hostIds: <String>[],
        localShellTypes: <LocalShellType>[],
        notifyEnabled: true,
        silentExecution: false,
        failurePolicy: ScriptFailurePolicy.continueOnFailure,
        retryPerHost: 1,
        templateArgs: <String, String>{},
        environmentOverrides: <String, String>{},
        maxConcurrency: 1,
      ),
    );
    scheduleStateSave();
    notifyState();
  }

  List<TerminalSession> availableScriptSessions() {
    return sessions.toList(growable: false);
  }

  List<HostEntry> availableScriptHosts() {
    return hosts
        .where((host) => host.isLocal || host.isSsh)
        .toList(growable: false);
  }

  ScriptEntry? findScriptById(String id) {
    for (final script in scripts) {
      if (script.id == id) return script;
    }
    return null;
  }

  List<ScriptRunEvent> scriptRunEvents({int max = 300}) {
    final all = _scriptRunEventsByState[this] ?? const <ScriptRunEvent>[];
    if (max <= 0 || all.length <= max) {
      return all.toList(growable: false);
    }
    return all.sublist(all.length - max).toList(growable: false);
  }

  int activeScriptRunCount() {
    return _scriptRunProgressByState[this]?.length ?? 0;
  }

  ScriptRunStatus scriptRunStatus(String scriptId) {
    final id = scriptId.trim();
    if (id.isEmpty) return ScriptRunStatus.idle;
    final running = _scriptRunningCountByState[this]?[id] ?? 0;
    if (running > 0) return ScriptRunStatus.running;
    return _scriptLastStatusByState[this]?[id] ?? ScriptRunStatus.idle;
  }

  void _clearScriptLastStatus(String scriptId) {
    final id = scriptId.trim();
    if (id.isEmpty) return;
    final lastMap = _scriptLastStatusByState[this];
    if (lastMap == null) return;
    if (lastMap.remove(id) != null) {
      notifyState();
    }
  }

  void _markScriptRunStarted(String scriptId) {
    final id = scriptId.trim();
    if (id.isEmpty) return;
    final runningMap = _scriptRunningCountByState[this] ??= <String, int>{};
    runningMap[id] = (runningMap[id] ?? 0) + 1;
    notifyState();
  }

  void _markScriptRunFinished(String scriptId, {required bool success}) {
    final id = scriptId.trim();
    if (id.isEmpty) return;
    final runningMap = _scriptRunningCountByState[this] ??= <String, int>{};
    final current = (runningMap[id] ?? 0) - 1;
    if (current <= 0) {
      runningMap.remove(id);
    } else {
      runningMap[id] = current;
    }
    final lastMap = _scriptLastStatusByState[this] ??=
        <String, ScriptRunStatus>{};
    lastMap[id] = success ? ScriptRunStatus.success : ScriptRunStatus.failed;
    notifyState();
  }

  void clearScriptRunEvents() {
    _scriptRunEventsByState[this]?.clear();
    notifyState();
  }

  void notifyScriptRunCancelled(String runId, String scriptId) {
    _markScriptRunFinished(scriptId, success: false);
    _finishScriptRunProgress(
      runId: runId,
      attempted: 0,
      executed: 0,
      failed: 0,
    );
  }

  void ensureScriptScheduleRuntime() {
    final existing = _scriptScheduleTimerByState[this];
    if (existing?.isActive ?? false) {
      return;
    }
    _scriptScheduleTimerByState[this] = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(_runScriptScheduleTick()),
    );
    // 延迟到下一帧执行，避免在 build 期间调用 notifyState
    Future.microtask(() => _runScriptScheduleTick());
  }

  void disposeScriptScheduleRuntime() {
    _scriptScheduleTimerByState[this]?.cancel();
    _scriptScheduleRunningByState[this]?.clear();
  }

  List<ScriptScheduleEntry> scriptSchedulesForScript(String scriptId) {
    return scriptSchedules
        .where((item) => item.scriptId == scriptId)
        .toList(growable: false);
  }

  DateTime? scriptScheduleNextTriggerTime(
    ScriptScheduleEntry schedule, {
    DateTime? from,
  }) {
    final expression = schedule.cronExpression.trim();
    if (!CronExpression.isValid(expression)) {
      return null;
    }
    final offsetMinutes = schedule.timezoneOffsetMinutes.clamp(
      -12 * 60,
      14 * 60,
    );
    final offset = Duration(minutes: offsetMinutes);
    final startUtc = (from ?? DateTime.now()).toUtc();
    final startLocal = startUtc.add(offset);
    var cursor = CronExpression.minuteBucket(startLocal);
    if (!cursor.isAfter(startLocal)) {
      cursor = cursor.add(const Duration(minutes: 1));
    }
    const maxSearchMinutes = 366 * 24 * 60;
    for (var i = 0; i < maxSearchMinutes; i++) {
      if (CronExpression.matches(expression, cursor)) {
        return cursor.subtract(offset).toLocal();
      }
      cursor = cursor.add(const Duration(minutes: 1));
    }
    return null;
  }

  void upsertScriptScheduleEntry(ScriptScheduleEntry entry) {
    final scriptId = entry.scriptId.trim();
    if (scriptId.isEmpty) {
      return;
    }
    final index = scriptSchedules.indexWhere((item) => item.id == entry.id);
    final now = DateTime.now();
    final normalized = entry.copyWith(
      retryPerHost: entry.retryPerHost.clamp(1, 6),
      timezoneOffsetMinutes: entry.timezoneOffsetMinutes.clamp(
        -12 * 60,
        14 * 60,
      ),
      updatedAt: now,
      lastEvaluatedAt: entry.lastEvaluatedAt ?? CronExpression.minuteBucket(now.toUtc()),
    );
    if (index >= 0) {
      scriptSchedules[index] = normalized;
    } else {
      scriptSchedules.add(normalized);
    }
    ensureScriptScheduleRuntime();
    scheduleStateSave();
    notifyState();
  }

  void removeScriptScheduleEntry(String scheduleId) {
    if (scheduleId.trim().isEmpty) {
      return;
    }
    scriptSchedules.removeWhere((item) => item.id == scheduleId);
    scheduleStateSave();
    notifyState();
  }

  void clearAllScriptSchedules() {
    if (scriptSchedules.isEmpty) return;
    scriptSchedules.clear();
    disposeScriptScheduleRuntime();
    scheduleStateSave();
    notifyState();
  }

  List<ScriptHostRunRecord> recentScriptRunsForHost(
    String hostId, {
    int max = 20,
  }) {
    final normalizedHostId = hostId.trim();
    if (normalizedHostId.isEmpty || max <= 0) {
      return const <ScriptHostRunRecord>[];
    }
    final filtered = scriptRunHistory
        .where((item) => item.hostId == normalizedHostId)
        .toList(growable: false);
    if (filtered.length <= max) {
      return filtered;
    }
    return filtered.sublist(filtered.length - max);
  }

  void clearScriptRunHistory({String? hostId}) {
    if (hostId == null || hostId.trim().isEmpty) {
      if (scriptRunHistory.isEmpty) {
        return;
      }
      scriptRunHistory.clear();
      scheduleStateSave();
      notifyState();
      return;
    }
    final normalizedHostId = hostId.trim();
    final before = scriptRunHistory.length;
    scriptRunHistory.removeWhere((item) => item.hostId == normalizedHostId);
    if (scriptRunHistory.length != before) {
      scheduleStateSave();
      notifyState();
    }
  }

  Future<int> runScriptOnSessions({
    required String scriptId,
    required List<String> sessionIds,
  }) async {
    final selected = sessions
        .where((session) => sessionIds.contains(session.id))
        .toList(growable: false);
    if (selected.isEmpty) {
      final script = findScriptById(scriptId);
      if (script != null) {
        _recordScriptRunFailure(
          script: script,
          detail: AppStrings.values.noAvailableSessionSelectedForScriptVar
              .resolve(locale.languageCode, params: {'name': script.name}),
        );
      } else {
        addStructuredLog(
          category: TerminalLogCategory.script,
          level: TerminalLogLevel.error,
          message: 'script not found: $scriptId',
          notifyListeners: false,
        );
      }
      return 0;
    }

    final hostIds = <String>{};
    final localShells = <LocalShellType>{};
    for (final session in selected) {
      if (session.profile.isLocal) {
        localShells.add(session.profile.localShellType);
      } else if (session.profile.isSsh) {
        hostIds.add(session.profile.id);
      }
    }

    final result = await runScriptOnTargets(
      scriptId: scriptId,
      hostIds: hostIds.toList(growable: false),
      localShellTypes: localShells.toList(growable: false),
      silentExecution: true,
    );
    return result.executed;
  }

  Future<int> runScriptOnHosts({
    required String scriptId,
    required List<String> hostIds,
  }) async {
    final result = await runScriptOnTargets(
      scriptId: scriptId,
      hostIds: hostIds,
    );
    return result.executed;
  }

  Future<ScriptWorkflowRunResult> runScriptWorkflow({
    required String workflowId,
  }) async {
    final workflow = findScriptWorkflowById(workflowId);
    if (workflow == null) {
      final detail = 'workflow not found: $workflowId';
      setError(detail);
      return ScriptWorkflowRunResult(
        workflowId: workflowId,
        workflowName: workflowId,
        attemptedSteps: 0,
        succeededSteps: 0,
        failedSteps: 1,
        detail: detail,
      );
    }
    if (workflow.nodes.isEmpty) {
      return ScriptWorkflowRunResult(
        workflowId: workflow.id,
        workflowName: workflow.name,
        attemptedSteps: 0,
        succeededSteps: 0,
        failedSteps: 0,
        detail: 'empty workflow',
      );
    }
    addStructuredLog(
      category: TerminalLogCategory.script,
      message:
          '[Workflow] start name=${workflow.name} steps=${workflow.nodes.length}',
      notifyListeners: false,
    );

    var attemptedSteps = 0;
    var succeededSteps = 0;
    var failedSteps = 0;
    final failedStepDetails = <String>[];
    final nodeResults = <WorkflowNodeResult>[];

    for (var i = 0; i < workflow.nodes.length; i++) {
      final node = workflow.nodes[i];
      final scriptId = node.scriptId.trim();
      final script = findScriptById(scriptId);
      if (script == null) {
        attemptedSteps += 1;
        failedSteps += 1;
        nodeResults.add(WorkflowNodeResult(
          nodeId: node.id,
          scriptId: node.scriptId,
          passed: false,
          detail: 'script not found ($scriptId)',
        ));
        failedStepDetails.add('step ${i + 1}: script not found ($scriptId)');
        if (node.stopOnFailure) {
          break;
        }
        continue;
      }
      final runConfig = script.lastRunConfig;
      final hostIds = runConfig?.hostIds ?? const <String>[];
      final localShellTypes =
          runConfig?.localShellTypes ?? const <LocalShellType>[];
      if (hostIds.isEmpty && localShellTypes.isEmpty) {
        attemptedSteps += 1;
        failedSteps += 1;
        nodeResults.add(WorkflowNodeResult(
          nodeId: node.id,
          scriptId: node.scriptId,
          passed: false,
          detail: '${script.name} has no run targets configured',
        ));
        failedStepDetails.add(
          'step ${i + 1}: ${script.name} has no run targets configured',
        );
        if (node.stopOnFailure) {
          break;
        }
        continue;
      }
      attemptedSteps += 1;
      addStructuredLog(
        category: TerminalLogCategory.script,
        message:
            '[Workflow] step ${i + 1}/${workflow.nodes.length} run script=${script.name}',
        notifyListeners: false,
      );
      final result = await runScriptOnTargets(
        scriptId: script.id,
        hostIds: hostIds,
        localShellTypes: localShellTypes,
        silentExecution: runConfig?.silentExecution ?? true,
        notifyEnabled: false,
        failurePolicy:
            runConfig?.failurePolicy ?? ScriptFailurePolicy.continueOnFailure,
        retryPerHost: runConfig?.retryPerHost ?? 1,
        templateArgs: runConfig?.templateArgs ?? const <String, String>{},
        environmentOverrides:
            runConfig?.environmentOverrides ?? const <String, String>{},
        maxConcurrency: runConfig?.maxConcurrency ?? script.maxConcurrency,
      );
      final passed = _evaluateWorkflowNode(node, result);
      final nodeDetail = passed
          ? 'ok'
          : '${script.name} failed (exit: ${result.failed}/${result.attempted})';
      nodeResults.add(WorkflowNodeResult(
        nodeId: node.id,
        scriptId: node.scriptId,
        passed: passed,
        detail: nodeDetail,
      ));
      if (passed) {
        succeededSteps += 1;
      } else {
        failedSteps += 1;
        failedStepDetails.add('step ${i + 1}: $nodeDetail');
        if (node.stopOnFailure) {
          break;
        }
      }
    }

    final detail = failedStepDetails.isEmpty
        ? 'ok'
        : failedStepDetails.take(4).join(' | ');

    addStructuredLog(
      category: TerminalLogCategory.script,
      message:
          '[Workflow] finish name=${workflow.name} attempted=$attemptedSteps success=$succeededSteps failed=$failedSteps detail=$detail',
      notifyListeners: false,
    );
    scheduleStateSave();
    notifyState();
    final result = ScriptWorkflowRunResult(
      workflowId: workflow.id,
      workflowName: workflow.name,
      attemptedSteps: attemptedSteps,
      succeededSteps: succeededSteps,
      failedSteps: failedSteps,
      detail: detail,
      nodeResults: nodeResults,
    );
    workflowRunHistory.add(result);
    if (workflowRunHistory.length > 120) {
      workflowRunHistory.removeAt(0);
    }
    return result;
  }

  Future<bool> runScriptAsMacroOnSession({
    required String scriptId,
    required TerminalSession session,
    Map<String, String> templateArgs = const <String, String>{},
    Map<String, String> environmentOverrides = const <String, String>{},
    Duration stepDelay = const Duration(milliseconds: 50),
    void Function(int stepIndex, int totalSteps, String command)? onStepStarted,
  }) async {
    if (!sessions.contains(session) ||
        session.tab.status != TerminalStatus.connected) {
      setError(
        AppStrings.values.sessionNotConnected.resolve(locale.languageCode),
      );
      return false;
    }
    final script = findScriptById(scriptId);
    if (script == null) {
      setError(
        AppStrings.values.scriptNotFoundVar.resolve(
          locale.languageCode,
          params: {'id': scriptId},
        ),
      );
      return false;
    }
    final mergedTemplateArgs = <String, String>{
      ...script.variables,
      ...templateArgs,
    };
    final mergedEnvironment = <String, String>{
      ...script.environment,
      ...environmentOverrides,
    };
    final markerToken = _randomHex(8);
    final compiled = _compileScriptPlan(
      script: script,
      templateArgs: mergedTemplateArgs,
      environment: mergedEnvironment,
      markerToken: markerToken,
    );
    if (compiled.error != null) {
      setError(
        AppStrings.values.scriptExecutionFailedVarVar.resolve(
          locale.languageCode,
          params: {'name': script.name, 'detail': compiled.error!},
        ),
      );
      return false;
    }
    final macroSteps = <String>[...compiled.prechecks, ...compiled.commands];
    if (macroSteps.isEmpty) {
      return true;
    }
    for (var i = 0; i < macroSteps.length; i++) {
      final step = macroSteps[i];
      final command = step.trim();
      if (command.isEmpty) {
        continue;
      }
      onStepStarted?.call(i + 1, macroSteps.length, command);
      final hasSubmitKey = command.endsWith('\n') || command.endsWith('\r');
      final payload = hasSubmitKey ? command : '$command\r';
      session.sendInput(payload, trackForHistory: false);
      if (stepDelay.inMilliseconds > 0) {
        await Future<void>.delayed(stepDelay);
      }
    }
    return true;
  }

  Future<ScriptRunResult> runScriptOnTargets({
    required String scriptId,
    required List<String> hostIds,
    List<LocalShellType> localShellTypes = const [],
    bool silentExecution = false,
    bool? notifyEnabled,
    ScriptFailurePolicy failurePolicy = ScriptFailurePolicy.continueOnFailure,
    int retryPerHost = 1,
    Map<String, String> templateArgs = const <String, String>{},
    Map<String, String> environmentOverrides = const <String, String>{},
    int? maxConcurrency,
  }) async {
    final script = findScriptById(scriptId);
    if (script == null) {
      final message = AppStrings.values.scriptNotFoundVar.resolve(
        locale.languageCode,
        params: {'id': scriptId},
      );
      addStructuredLog(
        category: TerminalLogCategory.script,
        level: TerminalLogLevel.error,
        message: message,
        notifyListeners: false,
      );
      return ScriptRunResult(
        runId: 'missing-$scriptId',
        scriptName: scriptId,
        attempted: 0,
        executed: 0,
        failed: 0,
      );
    }
    final shouldNotifyResult = !silentExecution
        ? false
        : (notifyEnabled ?? (script.lastRunConfig?.notifyEnabled ?? true));
    _clearScriptLastStatus(script.id);

    final targets = _resolveScriptTargets(hostIds, localShellTypes);
    if (targets.isEmpty) {
      final message = AppStrings.values.noAvailableSessionSelectedForScriptVar
          .resolve(locale.languageCode, params: {'name': script.name});
      _recordScriptRunFailure(script: script, detail: message);
      return ScriptRunResult(
        runId: 'empty-${DateTime.now().microsecondsSinceEpoch}',
        scriptName: script.name,
        attempted: 0,
        executed: 0,
        failed: 0,
      );
    }

    final mergedTemplateArgs = <String, String>{
      ...script.variables,
      ...templateArgs,
    };
    final mergedEnvironment = <String, String>{
      ...script.environment,
      ...environmentOverrides,
    };
    final markerToken = _randomHex(8);
    final compiled = _compileScriptPlan(
      script: script,
      templateArgs: mergedTemplateArgs,
      environment: mergedEnvironment,
      markerToken: markerToken,
    );
    if (compiled.error != null) {
      _recordScriptRunFailure(
        script: script,
        detail: AppStrings.values.scriptExecutionFailedVarVar.resolve(
          locale.languageCode,
          params: {'name': script.name, 'detail': compiled.error!},
        ),
      );
      return ScriptRunResult(
        runId: 'compile-${DateTime.now().microsecondsSinceEpoch}',
        scriptName: script.name,
        attempted: 0,
        executed: 0,
        failed: 0,
      );
    }
    final commandsPerTarget =
        (compiled.prechecks.length + compiled.commands.length).clamp(1, 100000);

    var started = false;
    var succeeded = false;
    try {
      _markScriptRunStarted(script.id);
      started = true;

      if (!silentExecution) {
        final monitorRunId = nextScriptRunId;
        final session = ScriptRunSession(
          runId: monitorRunId,
          scriptId: script.id,
          scriptName: script.name,
          targetCount: targets.length,
          silent: false,
        );
        activeScriptRuns[monitorRunId] = session;
        notifyState();
        final result = await _runScriptOnTargetsInVisibleSessions(
          runId: monitorRunId,
          script: script,
          targets: targets,
          notifyEnabled: shouldNotifyResult,
          failurePolicy: failurePolicy,
          retryPerHost: retryPerHost,
          templateArgs: templateArgs,
          environmentOverrides: environmentOverrides,
          commandsPerTarget: commandsPerTarget,
        );
        session.isFinished = true;
        succeeded = result.executed > 0 && result.failed <= 0;
        _logScriptRunSummary(scriptName: script.name, success: succeeded);
        notifyState();
        return result;
      }

      final runId = nextScriptRunId;
      final resolvedConcurrency = (maxConcurrency ?? script.maxConcurrency)
          .clamp(1, 8);

      final session = ScriptRunSession(
        runId: runId,
        scriptId: script.id,
        scriptName: script.name,
        targetCount: targets.length,
      );
      activeScriptRuns[runId] = session;

      _beginScriptRunProgress(
        runId: runId,
        scriptName: script.name,
        totalTargets: targets.length,
        commandsPerTarget: commandsPerTarget,
      );
      _emitScriptEvent(
        runId: runId,
        type: ScriptRunEventType.runStarted,
        target: '*',
        message: 'script=${script.name} targets=${targets.length}',
        notify: true,
      );

      final results = List<_ScriptTargetExecutionResult?>.filled(
        targets.length,
        null,
      );
      var cursor = 0;
      var stopDispatch = false;
      Object? workerError;

      Future<void> worker() async {
        while (true) {
          if (stopDispatch || session.isCancelled) {
            return;
          }
          final index = cursor;
          if (index >= targets.length) {
            return;
          }
          cursor += 1;
          final host = targets[index];
          final result = await _runScriptOnTarget(
            runId: runId,
            host: host,
            plan: compiled,
            maxAttempts: failurePolicy == ScriptFailurePolicy.retryHost
                ? retryPerHost.clamp(1, 6)
                : 1,
          );
          results[index] = result;
          if (failurePolicy == ScriptFailurePolicy.stopOnFailure &&
              !result.success) {
            stopDispatch = true;
          }
        }
      }

      final workerCount = resolvedConcurrency.clamp(1, targets.length);
      try {
        await Future.wait(
          List<Future<void>>.generate(workerCount, (_) => worker()),
        );
      } catch (error) {
        workerError = error;
        addStructuredLog(
          category: TerminalLogCategory.script,
          message: 'silent script worker failed: $error',
          notifyListeners: true,
        );
      }

      final completed = results
          .whereType<_ScriptTargetExecutionResult>()
          .toList(growable: false);
      final successItems = completed
          .where((item) => item.success)
          .toList(growable: false);
      final failureItems = completed
          .where((item) => !item.success)
          .toList(growable: false);

      final failures = failureItems
          .map((item) => '${item.targetName}: ${item.detail}')
          .toList(growable: true);
      if (workerError != null) {
        failures.insert(0, 'runtime: $workerError');
      }

      final attempted = completed.length;
      final executed = successItems.length;
      final failed = failureItems.length;

      _finishScriptRunProgress(
        runId: runId,
        attempted: attempted,
        executed: executed,
        failed: failed,
      );

      _emitScriptEvent(
        runId: runId,
        type: ScriptRunEventType.runFinished,
        target: '*',
        message: 'attempted=$attempted success=$executed failed=$failed',
        notify: true,
      );

      _appendScriptRunHistory(
        runId: runId,
        script: script,
        completed: completed,
      );
      unawaited(
        _notifyScriptRunSystemResult(
          script: script,
          executed: executed,
          failed: failed,
          notifyEnabled: shouldNotifyResult,
        ),
      );
      scheduleStateSave();
      notifyState();
      final result = ScriptRunResult(
        runId: runId,
        scriptName: script.name,
        attempted: attempted,
        executed: executed,
        failed: failed,
        failedTargets: failures,
      );
      succeeded = executed > 0 && failed <= 0;
      _logScriptRunSummary(scriptName: script.name, success: succeeded);
      return result;
    } finally {
      if (started) {
        _markScriptRunFinished(script.id, success: succeeded);
      }
    }
  }

  Future<ScriptRunResult> _runScriptOnTargetsInVisibleSessions({
    required String runId,
    required ScriptEntry script,
    required List<HostEntry> targets,
    required bool notifyEnabled,
    required ScriptFailurePolicy failurePolicy,
    required int retryPerHost,
    required Map<String, String> templateArgs,
    required Map<String, String> environmentOverrides,
    required int commandsPerTarget,
  }) async {
    _beginScriptRunProgress(
      runId: runId,
      scriptName: script.name,
      totalTargets: targets.length,
      commandsPerTarget: commandsPerTarget,
    );
    _emitScriptEvent(
      runId: runId,
      type: ScriptRunEventType.runStarted,
      target: '*',
      message: 'script=${script.name} targets=${targets.length} visible=true',
      notify: true,
    );

    final completed = <_ScriptTargetExecutionResult>[];
    for (final host in targets) {
      final result = await _runScriptOnTargetInVisibleSession(
        runId: runId,
        script: script,
        host: host,
        maxAttempts: failurePolicy == ScriptFailurePolicy.retryHost
            ? retryPerHost.clamp(1, 6)
            : 1,
        templateArgs: templateArgs,
        environmentOverrides: environmentOverrides,
      );
      completed.add(result);
      if (failurePolicy == ScriptFailurePolicy.stopOnFailure &&
          !result.success) {
        break;
      }
    }

    final successItems = completed
        .where((item) => item.success)
        .toList(growable: false);
    final failureItems = completed
        .where((item) => !item.success)
        .toList(growable: false);
    final failures = failureItems
        .map((item) => '${item.targetName}: ${item.detail}')
        .toList(growable: false);
    final attempted = completed.length;
    final executed = successItems.length;
    final failed = failureItems.length;

    _finishScriptRunProgress(
      runId: runId,
      attempted: attempted,
      executed: executed,
      failed: failed,
    );

    _emitScriptEvent(
      runId: runId,
      type: ScriptRunEventType.runFinished,
      target: '*',
      message: 'attempted=$attempted success=$executed failed=$failed',
      notify: true,
    );

    _appendScriptRunHistory(runId: runId, script: script, completed: completed);
    unawaited(
      _notifyScriptRunSystemResult(
        script: script,
        executed: executed,
        failed: failed,
        notifyEnabled: notifyEnabled,
      ),
    );
    scheduleStateSave();
    notifyState();
    return ScriptRunResult(
      runId: runId,
      scriptName: script.name,
      attempted: attempted,
      executed: executed,
      failed: failed,
      failedTargets: failures,
    );
  }

  Future<_ScriptTargetExecutionResult> _runScriptOnTargetInVisibleSession({
    required String runId,
    required ScriptEntry script,
    required HostEntry host,
    required int maxAttempts,
    required Map<String, String> templateArgs,
    required Map<String, String> environmentOverrides,
  }) async {
    _emitScriptEvent(
      runId: runId,
      type: ScriptRunEventType.targetStarted,
      target: host.name,
      targetId: host.id,
      message: 'start (visible)',
      notify: true,
    );
    final attempts = maxAttempts.clamp(1, 6);
    _ScriptTargetExecutionResult? lastFailure;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      final session = await _ensureScriptExecutionSessionVisible(host);
      if (session == null) {
        lastFailure = _ScriptTargetExecutionResult(
          targetId: host.id,
          targetName: host.name,
          success: false,
          detail: 'session unavailable',
        );
      } else {
        final previousError = (lastError ?? '').trim();
        final success = await runScriptAsMacroOnSession(
          scriptId: script.id,
          session: session,
          templateArgs: templateArgs,
          environmentOverrides: environmentOverrides,
          onStepStarted: (stepIndex, totalSteps, command) {
            _updateScriptRunProgressStep(
              runId: runId,
              targetId: host.id,
              targetName: host.name,
              stepIndex: stepIndex,
              totalSteps: totalSteps,
            );
          },
        );
        if (success) {
          _emitScriptEvent(
            runId: runId,
            type: ScriptRunEventType.targetSucceeded,
            target: host.name,
            targetId: host.id,
            message: 'visible session injected',
            notify: true,
          );
          _markScriptRunProgressTargetCompleted(
            runId: runId,
            targetId: host.id,
            targetName: host.name,
          );
          return _ScriptTargetExecutionResult(
            targetId: host.id,
            targetName: host.name,
            success: true,
            detail: 'visible session injected',
          );
        }
        final currentError = (lastError ?? '').trim();
        lastFailure = _ScriptTargetExecutionResult(
          targetId: host.id,
          targetName: host.name,
          success: false,
          detail: currentError.isNotEmpty && currentError != previousError
              ? currentError
              : 'session execution failed',
        );
      }
      if (attempt < attempts) {
        _emitScriptEvent(
          runId: runId,
          type: ScriptRunEventType.targetFailed,
          target: host.name,
          targetId: host.id,
          message:
              'attempt $attempt/$attempts failed, retrying: ${lastFailure.detail}',
          notify: true,
        );
      }
    }
    final failure =
        lastFailure ??
        _ScriptTargetExecutionResult(
          targetId: host.id,
          targetName: host.name,
          success: false,
          detail: 'unknown',
        );
    _emitScriptEvent(
      runId: runId,
      type: ScriptRunEventType.targetFailed,
      target: host.name,
      targetId: host.id,
      message: failure.detail,
      notify: true,
    );
    _markScriptRunProgressTargetCompleted(
      runId: runId,
      targetId: host.id,
      targetName: host.name,
    );
    return failure;
  }

  Future<TerminalSession?> _ensureScriptExecutionSessionVisible(
    HostEntry host,
  ) async {
    TerminalSession? session;
    int sessionIndex = -1;
    for (var i = sessions.length - 1; i >= 0; i--) {
      final candidate = sessions[i];
      if (candidate.profile.id != host.id) {
        continue;
      }
      session = candidate;
      sessionIndex = i;
      if (candidate.tab.status == TerminalStatus.connected) {
        break;
      }
    }

    if (session == null) {
      await connectToHost(host, remember: false, background: false);
      for (var i = sessions.length - 1; i >= 0; i--) {
        final candidate = sessions[i];
        if (candidate.profile.id != host.id) {
          continue;
        }
        session = candidate;
        sessionIndex = i;
        break;
      }
    } else {
      if (sessionIndex >= 0) {
        setActiveSession(sessionIndex);
      }
      if (session.tab.status != TerminalStatus.connected) {
        await reconnectSession(session, background: false);
      }
    }

    if (session == null ||
        !sessions.contains(session) ||
        session.tab.status != TerminalStatus.connected) {
      return null;
    }
    if (sessionIndex < 0 || sessionIndex >= sessions.length) {
      sessionIndex = sessions.indexOf(session);
    }
    if (sessionIndex >= 0) {
      setActiveSession(sessionIndex);
    }
    if (navSection != NavSection.sessions) {
      navSection = NavSection.sessions;
      notifyState();
    }
    return session;
  }

  Future<void> _runScriptScheduleTick() async {
    if (scriptSchedules.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final nowUtc = now.toUtc();
    final nowBucketUtc = CronExpression.minuteBucket(nowUtc);
    final running = _scriptScheduleRunningByState[this] ??= <String>{};
    var changed = false;
    for (var i = 0; i < scriptSchedules.length; i++) {
      final schedule = scriptSchedules[i];
      if (!schedule.enabled) {
        continue;
      }
      if (running.contains(schedule.id)) {
        continue;
      }
      final script = findScriptById(schedule.scriptId);
      if (script == null) {
        continue;
      }
      final dueMomentsUtc = _collectDueScheduleMomentsUtc(
        schedule: schedule,
        nowUtc: nowUtc,
      );
      final lastEvaluatedBucketUtc = schedule.lastEvaluatedAt == null
          ? null
          : CronExpression.minuteBucket(schedule.lastEvaluatedAt!.toUtc());
      final evaluationAdvanced = lastEvaluatedBucketUtc == null
          ? true
          : lastEvaluatedBucketUtc != nowBucketUtc;
      if (!evaluationAdvanced && dueMomentsUtc.isEmpty) {
        continue;
      }
      final updated = schedule.copyWith(
        lastTriggeredAt: dueMomentsUtc.isEmpty
            ? schedule.lastTriggeredAt
            : dueMomentsUtc.last.toUtc(),
        lastEvaluatedAt: nowBucketUtc,
        updatedAt: now,
      );
      scriptSchedules[i] = updated;
      changed = true;
      if (dueMomentsUtc.isEmpty) {
        continue;
      }
      running.add(updated.id);
      unawaited(() async {
        try {
          for (final dueAtUtc in dueMomentsUtc) {
            await _runSingleScheduledScript(
              schedule: updated,
              scriptName: script.name,
              scheduledAtUtc: dueAtUtc,
            );
          }
        } finally {
          running.remove(updated.id);
        }
      }());
    }
    if (changed) {
      scheduleStateSave();
      notifyState();
    }
  }

  List<DateTime> _collectDueScheduleMomentsUtc({
    required ScriptScheduleEntry schedule,
    required DateTime nowUtc,
  }) {
    final expression = schedule.cronExpression.trim();
    if (!CronExpression.isValid(expression)) {
      return const <DateTime>[];
    }
    final timezoneOffsetMinutes = schedule.timezoneOffsetMinutes.clamp(
      -12 * 60,
      14 * 60,
    );
    final offset = Duration(minutes: timezoneOffsetMinutes);
    final nowLocal = nowUtc.add(offset);
    final nowLocalBucket = CronExpression.minuteBucket(nowLocal);
    final lastEvaluatedUtc = (schedule.lastEvaluatedAt ?? nowUtc).toUtc();
    final startUtc = lastEvaluatedUtc.isAfter(nowUtc)
        ? nowUtc
        : lastEvaluatedUtc;
    var dueMomentsUtc = CronExpression.momentsInRange(
      expression: expression,
      startExclusiveUtc: startUtc,
      endInclusiveUtc: nowUtc,
      timezoneOffsetMinutes: timezoneOffsetMinutes,
      maxCount: _scriptScheduleCatchUpMaxPerTick * 4,
    );
    final lastTriggered = schedule.lastTriggeredAt;
    if (lastTriggered != null) {
      final lastTriggeredBucketUtc = CronExpression.minuteBucket(lastTriggered.toUtc());
      dueMomentsUtc = dueMomentsUtc
          .where(
            (item) =>
                CronExpression.minuteBucket(item.toUtc()).isAfter(lastTriggeredBucketUtc),
          )
          .toList(growable: false);
    }
    if (dueMomentsUtc.isEmpty) {
      return const <DateTime>[];
    }
    switch (schedule.missedRunPolicy) {
      case ScriptScheduleMissedRunPolicy.skip:
        if (!CronExpression.matches(expression, nowLocal)) {
          return const <DateTime>[];
        }
        final currentDueUtc = nowLocalBucket.subtract(offset);
        final foundCurrent = dueMomentsUtc.any(
          (item) =>
              CronExpression.minuteBucket(item.toUtc()) ==
              CronExpression.minuteBucket(currentDueUtc.toUtc()),
        );
        if (!foundCurrent) {
          return const <DateTime>[];
        }
        return <DateTime>[currentDueUtc.toUtc()];
      case ScriptScheduleMissedRunPolicy.catchUpOnce:
        return <DateTime>[dueMomentsUtc.last.toUtc()];
      case ScriptScheduleMissedRunPolicy.catchUpAll:
        if (dueMomentsUtc.length <= _scriptScheduleCatchUpMaxPerTick) {
          return dueMomentsUtc
              .map((item) => item.toUtc())
              .toList(growable: false);
        }
        return dueMomentsUtc
            .sublist(dueMomentsUtc.length - _scriptScheduleCatchUpMaxPerTick)
            .map((item) => item.toUtc())
            .toList(growable: false);
    }
  }

  Future<void> _runSingleScheduledScript({
    required ScriptScheduleEntry schedule,
    required String scriptName,
    required DateTime scheduledAtUtc,
  }) async {
    final scheduleLabel =
        '[ScriptSchedule] '
        '${schedule.cronExpression} '
        'tz=${_formatUtcOffset(schedule.timezoneOffsetMinutes)} '
        'at=${scheduledAtUtc.toLocal()}';
    try {
      final result = await runScriptOnTargets(
        scriptId: schedule.scriptId,
        hostIds: schedule.hostIds,
        localShellTypes: schedule.localShellTypes,
        silentExecution: schedule.silentExecution,
        failurePolicy: schedule.failurePolicy,
        retryPerHost: schedule.retryPerHost,
      );
      addStructuredLog(
        category: TerminalLogCategory.script,
        message:
            '$scheduleLabel '
            '$scriptName success=${result.executed} failed=${result.failed}',
        notifyListeners: false,
      );
    } catch (error) {
      addStructuredLog(
        category: TerminalLogCategory.script,
        level: TerminalLogLevel.error,
        message: '$scheduleLabel $scriptName failed: $error',
        notifyListeners: false,
      );
    }
  }

  String _formatUtcOffset(int offsetMinutes) {
    final sign = offsetMinutes >= 0 ? '+' : '-';
    final total = offsetMinutes.abs();
    final hours = (total ~/ 60).toString().padLeft(2, '0');
    final minutes = (total % 60).toString().padLeft(2, '0');
    return 'UTC$sign$hours:$minutes';
  }

  void _appendScriptRunHistory({
    required String runId,
    required ScriptEntry script,
    required List<_ScriptTargetExecutionResult> completed,
  }) {
    if (completed.isEmpty) {
      return;
    }
    final now = DateTime.now();
    for (final item in completed) {
      scriptRunHistory.add(
        ScriptHostRunRecord(
          id: 'script-run-${now.microsecondsSinceEpoch}-${scriptRunHistory.length}',
          runId: runId,
          scriptId: script.id,
          scriptName: script.name,
          hostId: item.targetId,
          hostName: item.targetName,
          success: item.success,
          detail: item.detail,
          finishedAt: now,
        ),
      );
    }
    if (scriptRunHistory.length > TerminalAppState.scriptRunHistoryCap) {
      scriptRunHistory.removeRange(
        0,
        scriptRunHistory.length - TerminalAppState.scriptRunHistoryCap,
      );
    }
  }

  void _recordScriptRunFailure({
    required ScriptEntry script,
    required String detail,
  }) {
    final now = DateTime.now();
    final hostName = AppStrings.values.scriptLabel.resolve(locale.languageCode);
    final lastMap = _scriptLastStatusByState[this] ??=
        <String, ScriptRunStatus>{};
    lastMap[script.id] = ScriptRunStatus.failed;
    scriptRunHistory.add(
      ScriptHostRunRecord(
        id: 'script-run-${now.microsecondsSinceEpoch}-${scriptRunHistory.length}',
        runId: 'error-${now.microsecondsSinceEpoch}',
        scriptId: script.id,
        scriptName: script.name,
        hostId: '',
        hostName: hostName,
        success: false,
        detail: detail,
        finishedAt: now,
      ),
    );
    if (scriptRunHistory.length > TerminalAppState.scriptRunHistoryCap) {
      scriptRunHistory.removeRange(
        0,
        scriptRunHistory.length - TerminalAppState.scriptRunHistoryCap,
      );
    }
    scheduleStateSave();
    notifyState();
  }

  void _logScriptRunSummary({
    required String scriptName,
    required bool success,
  }) {
    final message = locale.languageCode == 'zh'
        ? '$scriptName 执行${success ? '成功' : '失败'}'
        : '$scriptName ${success ? 'succeeded' : 'failed'}';
    addStructuredLog(
      category: TerminalLogCategory.script,
      message: message,
      notifyListeners: false,
    );
  }

  List<HostEntry> _resolveScriptTargets(
    List<String> hostIds,
    List<LocalShellType> localShellTypes,
  ) {
    final hostTargets = hosts
        .where(
          (host) => hostIds.contains(host.id) && (host.isLocal || host.isSsh),
        )
        .toList(growable: false);
    final seenLocal = <LocalShellType>{};
    final localTargets = <HostEntry>[];
    for (final shellType in localShellTypes) {
      if (!seenLocal.add(shellType)) {
        continue;
      }
      localTargets.add(_buildEphemeralLocalHost(shellType));
    }
    return <HostEntry>[...hostTargets, ...localTargets];
  }

  _CompiledScript _compileScriptPlan({
    required ScriptEntry script,
    required Map<String, String> templateArgs,
    required Map<String, String> environment,
    String markerToken = '',
    String? workingDirectory,
  }) {
    final expandedPrechecks = _expandScriptLines(
      owner: script,
      lines: script.precheckCommands,
      stack: <String>[script.id],
    );
    if (expandedPrechecks.error != null) {
      return _CompiledScript(
        prechecks: const <String>[],
        commands: const <String>[],
        environment: const <String, String>{},
        error: expandedPrechecks.error,
        markerToken: markerToken,
        stepConfigs: script.stepConfigs,
      );
    }
    final expandedCommands = _expandScriptLines(
      owner: script,
      lines: script.commands,
      stack: <String>[script.id],
    );
    if (expandedCommands.error != null) {
      return _CompiledScript(
        prechecks: const <String>[],
        commands: const <String>[],
        environment: const <String, String>{},
        error: expandedCommands.error,
        markerToken: markerToken,
        stepConfigs: script.stepConfigs,
      );
    }

    final missing = <String>{};
    final allSource = <String>[
      ...expandedPrechecks.lines,
      ...expandedCommands.lines,
      ...environment.values,
    ];
    for (final item in allSource) {
      for (final match in _scriptTemplatePattern.allMatches(item)) {
        final key = match.group(1)?.trim() ?? '';
        if (key.isEmpty) {
          continue;
        }
        if (!templateArgs.containsKey(key)) {
          missing.add(key);
        }
      }
    }

    if (missing.isNotEmpty) {
      final keys = missing.toList(growable: false)..sort();
      final preview = keys.take(8).join(', ');
      return _CompiledScript(
        prechecks: const <String>[],
        commands: const <String>[],
        environment: const <String, String>{},
        error: 'missing template args: $preview',
        markerToken: markerToken,
        stepConfigs: script.stepConfigs,
      );
    }

    String resolveTemplate(String input) {
      return input.replaceAllMapped(_scriptTemplatePattern, (match) {
        final key = match.group(1) ?? '';
        return templateArgs[key] ?? match.group(0)!;
      });
    }

    final prechecks = expandedPrechecks.lines
        .map((line) => resolveTemplate(line.trim()))
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final commands = expandedCommands.lines
        .map((line) => resolveTemplate(line.trim()))
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final env = <String, String>{};
    for (final entry in environment.entries) {
      final key = entry.key.trim();
      if (key.isEmpty) {
        continue;
      }
      env[key] = resolveTemplate(entry.value);
    }
    return _CompiledScript(
      prechecks: prechecks,
      commands: commands,
      environment: env,
      error: null,
      markerToken: markerToken,
      workingDirectory: workingDirectory,
      stepConfigs: script.stepConfigs,
    );
  }

  _ScriptExpandResult _expandScriptLines({
    required ScriptEntry owner,
    required List<String> lines,
    required List<String> stack,
  }) {
    if (stack.length > 24) {
      return const _ScriptExpandResult(
        lines: <String>[],
        error: 'script include depth exceeded (max=24)',
      );
    }
    final expanded = <String>[];
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) {
        continue;
      }
      final includeMatch = _scriptIncludePattern.firstMatch(line);
      if (includeMatch == null) {
        expanded.add(line);
        continue;
      }
      final ref = (includeMatch.group(1) ?? '').trim();
      if (ref.isEmpty) {
        return const _ScriptExpandResult(
          lines: <String>[],
          error: 'invalid @script reference',
        );
      }
      final resolved = _findScriptByReference(ref);
      if (resolved.error != null || resolved.script == null) {
        return _ScriptExpandResult(
          lines: const <String>[],
          error: resolved.error ?? 'script ref not found: $ref',
        );
      }
      final target = resolved.script!;
      if (target.id == owner.id) {
        return _ScriptExpandResult(
          lines: const <String>[],
          error: 'script cannot include itself: ${target.name}',
        );
      }
      if (stack.contains(target.id)) {
        final cycle = <String>[...stack, target.id].join(' -> ');
        return _ScriptExpandResult(
          lines: const <String>[],
          error: 'cyclic script include: $cycle',
        );
      }
      final nextStack = <String>[...stack, target.id];
      final prechecks = _expandScriptLines(
        owner: target,
        lines: target.precheckCommands,
        stack: nextStack,
      );
      if (prechecks.error != null) {
        return prechecks;
      }
      final commands = _expandScriptLines(
        owner: target,
        lines: target.commands,
        stack: nextStack,
      );
      if (commands.error != null) {
        return commands;
      }
      expanded
        ..addAll(prechecks.lines)
        ..addAll(commands.lines);
    }
    return _ScriptExpandResult(lines: expanded, error: null);
  }

  _ScriptLookupResult _findScriptByReference(String raw) {
    final token = raw.trim();
    if (token.isEmpty) {
      return const _ScriptLookupResult(
        script: null,
        error: 'empty script reference',
      );
    }
    for (final script in scripts) {
      if (script.id == token) {
        return _ScriptLookupResult(script: script, error: null);
      }
    }
    final exactName = scripts
        .where((item) => item.name.trim() == token)
        .toList(growable: false);
    if (exactName.length == 1) {
      return _ScriptLookupResult(script: exactName.first, error: null);
    }
    final lowered = token.toLowerCase();
    final caseInsensitive = scripts
        .where((item) => item.name.trim().toLowerCase() == lowered)
        .toList(growable: false);
    if (caseInsensitive.length == 1) {
      return _ScriptLookupResult(script: caseInsensitive.first, error: null);
    }
    if (exactName.length > 1 || caseInsensitive.length > 1) {
      return _ScriptLookupResult(
        script: null,
        error: 'ambiguous script reference: $token',
      );
    }
    return _ScriptLookupResult(
      script: null,
      error: 'script ref not found: $token',
    );
  }

  bool _evaluateWorkflowNode(WorkflowNode node, ScriptRunResult result) {
    switch (node.validation) {
      case WorkflowValidationType.always:
        return true;
      case WorkflowValidationType.exitCode:
        return result.failed == 0;
      case WorkflowValidationType.outputContains:
      case WorkflowValidationType.outputRegex:
        if (result.failed != 0) return false;
        return true;
    }
  }
}

class ScriptRunResult {
  const ScriptRunResult({
    required this.runId,
    required this.scriptName,
    required this.attempted,
    required this.executed,
    required this.failed,
    this.failedTargets = const <String>[],
  });

  final String runId;
  final String scriptName;
  final int attempted;
  final int executed;
  final int failed;
  final List<String> failedTargets;
}

class WorkflowNodeResult {
  const WorkflowNodeResult({
    required this.nodeId,
    required this.scriptId,
    required this.passed,
    required this.detail,
  });

  final String nodeId;
  final String scriptId;
  final bool passed;
  final String detail;
}

class ScriptWorkflowRunResult {
  const ScriptWorkflowRunResult({
    required this.workflowId,
    required this.workflowName,
    required this.attemptedSteps,
    required this.succeededSteps,
    required this.failedSteps,
    required this.detail,
    this.nodeResults = const <WorkflowNodeResult>[],
  });

  final String workflowId;
  final String workflowName;
  final int attemptedSteps;
  final int succeededSteps;
  final int failedSteps;
  final String detail;
  final List<WorkflowNodeResult> nodeResults;
}

class _CompiledScript {
  const _CompiledScript({
    required this.prechecks,
    required this.commands,
    required this.environment,
    required this.error,
    this.markerToken = '',
    this.workingDirectory,
    this.stepConfigs = const <ScriptStepConfig?>[],
  });

  final List<String> prechecks;
  final List<String> commands;
  final Map<String, String> environment;
  final String? error;
  final String markerToken;
  final String? workingDirectory;
  final List<ScriptStepConfig?> stepConfigs;
}

class _ScriptExpandResult {
  const _ScriptExpandResult({required this.lines, required this.error});

  final List<String> lines;
  final String? error;
}

class _ScriptLookupResult {
  const _ScriptLookupResult({required this.script, required this.error});

  final ScriptEntry? script;
  final String? error;
}

enum _ScriptStepKind { precheck, command }

class _ScriptStepPlan {
  const _ScriptStepPlan(this.kind, this.command, {
    this.allowFailure = false,
    this.condition = ScriptStepCondition.always,
    this.captureOutput = false,
    this.failurePolicy = ScriptStepFailurePolicy.continueOnFailure,
    this.retryCount = 1,
  });

  final _ScriptStepKind kind;
  final String command;
  final bool allowFailure;
  final ScriptStepCondition condition;
  final bool captureOutput;
  final ScriptStepFailurePolicy failurePolicy;
  final int retryCount;
}

class _ScriptTargetExecutionResult {
  const _ScriptTargetExecutionResult({
    required this.targetId,
    required this.targetName,
    required this.success,
    required this.detail,
  });

  final String targetId;
  final String targetName;
  final bool success;
  final String detail;
}

class _ScriptSessionExecutionResult {
  const _ScriptSessionExecutionResult({
    required this.success,
    required this.exitCode,
    required this.detail,
  });

  final bool success;
  final int exitCode;
  final String detail;
}

class _ScriptSessionTracker {
  _ScriptSessionTracker(this.stepByIndex);

  final Map<int, _ScriptStepPlan> stepByIndex;
  int? activeStepIndex;
  int? failedStepIndex;
  int? failedExitCode;
  String? failedDetail;
  final Map<int, StringBuffer> _stepStderr = <int, StringBuffer>{};

  void appendStepStderr(int stepIndex, String line) {
    final buffer = _stepStderr.putIfAbsent(stepIndex, StringBuffer.new);
    if (buffer.length >= _scriptOutputSnippetLimit) {
      return;
    }
    if (buffer.isNotEmpty) {
      buffer.write(' | ');
    }
    buffer.write(line);
  }

  String stepStderrSnippet(int stepIndex) {
    return _stepStderr[stepIndex]?.toString() ?? '';
  }
}

class _ScriptRunProgressState {
  _ScriptRunProgressState({
    required this.runId,
    required this.scriptName,
    required this.totalTargets,
    required this.commandsPerTarget,
  });

  final String runId;
  final String scriptName;
  final int totalTargets;
  final int commandsPerTarget;
  final Map<String, int> stepByTarget = <String, int>{};
  final Map<String, String> targetNameById = <String, String>{};
  final Set<String> completedTargetIds = <String>{};

  double progressValue() {
    final steps = commandsPerTarget.clamp(1, 100000);
    final targets = totalTargets.clamp(1, 100000);
    final totalUnits = steps * targets;
    var doneUnits = completedTargetIds.length * steps;
    for (final entry in stepByTarget.entries) {
      if (completedTargetIds.contains(entry.key)) {
        continue;
      }
      doneUnits += entry.value.clamp(0, steps);
    }
    if (doneUnits <= 0) {
      return 0;
    }
    if (doneUnits >= totalUnits) {
      return 0.999;
    }
    return doneUnits / totalUnits;
  }
}

enum _ScriptStepMarkerType { start, end }

class _ScriptStepMarker {
  const _ScriptStepMarker._({
    required this.type,
    required this.index,
    this.exitCode,
  });

  final _ScriptStepMarkerType type;
  final int index;
  final int? exitCode;

  factory _ScriptStepMarker.start(int index) {
    return _ScriptStepMarker._(type: _ScriptStepMarkerType.start, index: index);
  }

  factory _ScriptStepMarker.end(int index, int exitCode) {
    return _ScriptStepMarker._(
      type: _ScriptStepMarkerType.end,
      index: index,
      exitCode: exitCode,
    );
  }
}
