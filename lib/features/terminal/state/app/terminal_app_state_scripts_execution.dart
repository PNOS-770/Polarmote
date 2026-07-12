part of 'terminal_app_state_scripts.dart';

bool _isWindowsProcessElevated() {
  if (!Platform.isWindows) return false;
  try {
    final result = Process.runSync('powershell.exe', const [
      '-NoProfile',
      '-Command',
      '[bool]([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)',
    ]);
    if (result.exitCode != 0) return false;
    final output = result.stdout?.toString().trim().toLowerCase() ?? '';
    return output == 'true';
  } catch (_) {
    return false;
  }
}

extension TerminalAppStateScriptsExecution on TerminalAppState {
  Future<_ScriptTargetExecutionResult> _runScriptOnTarget({
    required String runId,
    required HostEntry host,
    required _CompiledScript plan,
    required int maxAttempts,
  }) async {
    _emitScriptEvent(
      runId: runId,
      type: ScriptRunEventType.targetStarted,
      target: host.name,
      targetId: host.id,
      message: 'start',
      notify: true,
    );

    if (plan.commands.isEmpty) {
      _emitScriptEvent(
        runId: runId,
        type: ScriptRunEventType.targetSucceeded,
        target: host.name,
        targetId: host.id,
        message: 'empty script',
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
        detail: 'empty script',
      );
    }

    final attempts = maxAttempts.clamp(1, 6);
    _ScriptTargetExecutionResult? lastFailure;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        final result = host.isLocal
            ? await _runScriptOnLocalTarget(
                runId: runId,
                host: host,
                plan: plan,
              )
            : await _runScriptOnRemoteTarget(
                runId: runId,
                host: host,
                plan: plan,
              );
        if (result.success) {
          _markScriptRunProgressTargetCompleted(
            runId: runId,
            targetId: host.id,
            targetName: host.name,
          );
          _emitScriptEvent(
            runId: runId,
            type: ScriptRunEventType.targetSucceeded,
            target: host.name,
            targetId: host.id,
            message: result.detail,
            notify: true,
          );
          return result;
        }
        lastFailure = result;
      } catch (error) {
        lastFailure = _ScriptTargetExecutionResult(
          targetId: host.id,
          targetName: host.name,
          success: false,
          detail: '$error',
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

  Future<_ScriptTargetExecutionResult> _runScriptOnLocalTarget({
    required String runId,
    required HostEntry host,
    required _CompiledScript plan,
  }) async {
    if (Platform.isWindows &&
        host.localShellType == LocalShellType.powershellAdmin &&
        !_isWindowsProcessElevated()) {
      return _ScriptTargetExecutionResult(
        targetId: host.id,
        targetName: host.name,
        success: false,
        detail: 'Polarmote is not running as Administrator. '
            'Restart Polarmote as Administrator to run scripts with PowerShell (Admin).',
      );
    }

    final steps = _buildScriptStepPlans(plan,
      stepConfigs: plan.stepConfigs,
    );
    final scriptBody = _buildLocalShellScript(
      shellType: host.localShellType,
      steps: steps,
      markerToken: plan.markerToken,
    );
    if (scriptBody == null) {
      return _ScriptTargetExecutionResult(
        targetId: host.id,
        targetName: host.name,
        success: false,
        detail: 'unsupported local shell',
      );
    }
    final spec = _resolveBackgroundLocalShellSpec(
      host.localShellType,
      scriptBody,
    );
    if (spec == null) {
      return _ScriptTargetExecutionResult(
        targetId: host.id,
        targetName: host.name,
        success: false,
        detail: 'unsupported local shell',
      );
    }

    final (program, args) = spec;
    final result = await _runLocalScriptSession(
      runId: runId,
      targetId: host.id,
      target: host.name,
      program: program,
      args: args,
      environment: plan.environment,
      steps: steps,
      markerToken: plan.markerToken,
    );
    return _ScriptTargetExecutionResult(
      targetId: host.id,
      targetName: host.name,
      success: result.success,
      detail: result.detail,
    );
  }

  Future<_ScriptTargetExecutionResult> _runScriptOnRemoteTarget({
    required String runId,
    required HostEntry host,
    required _CompiledScript plan,
  }) async {
    final runSession = activeScriptRuns[runId];
    if (runSession != null && runSession.isCancelled) {
      return _ScriptTargetExecutionResult(
        targetId: host.id,
        targetName: host.name,
        success: false,
        detail: 'cancelled',
      );
    }

    SSHClient? client;
    try {
      client = await scriptSshPool.acquire(host, (h) async {
        final aux = <SSHClient>[];
        final c = await connectSshClientForHost(h, auxiliaryClients: aux);
        return SshClientBundle(c, aux);
      });
      final steps = _buildScriptStepPlans(plan,
        stepConfigs: plan.stepConfigs,
      );
      final scriptBody = _buildPosixShellScript(steps, plan.markerToken);
      final result = await _runRemoteScriptSession(
        runId: runId,
        targetId: host.id,
        target: host.name,
        client: client,
        environment: plan.environment,
        scriptBody: scriptBody,
        steps: steps,
        markerToken: plan.markerToken,
      );
      return _ScriptTargetExecutionResult(
        targetId: host.id,
        targetName: host.name,
        success: result.success,
        detail: result.detail,
      );
    } catch (error) {
      return _ScriptTargetExecutionResult(
        targetId: host.id,
        targetName: host.name,
        success: false,
        detail: '$error',
      );
    } finally {
      scriptSshPool.release(host);
    }
  }

  Future<_ScriptSessionExecutionResult> _runLocalScriptSession({
    required String runId,
    required String targetId,
    required String target,
    required String program,
    required List<String> args,
    required Map<String, String> environment,
    required List<_ScriptStepPlan> steps,
    String markerToken = '',
  }) async {
    Process process;
    try {
      final runSession = activeScriptRuns[runId];
      final workingDir = runSession?.workingDirectory ?? Directory.current.path;
      process = await Process.start(
        program,
        args,
        includeParentEnvironment: true,
        environment: environment.isEmpty ? null : environment,
        workingDirectory: workingDir,
      );
    } catch (error) {
      return _ScriptSessionExecutionResult(
        success: false,
        exitCode: -1,
        detail: '$error',
      );
    }

    final runSession = activeScriptRuns[runId];
    runSession?.registerProcess(process, null);

    final indexMap = <int, _ScriptStepPlan>{};
    for (var i = 0; i < steps.length; i++) {
      indexMap[i + 1] = steps[i];
    }
    final tracker = _ScriptSessionTracker(indexMap);
    final stderrBuffer = StringBuffer();
    final stdoutDone = _pumpOutputLines(
      stream: process.stdout,
      useSystemEncoding: Platform.isWindows,
      onLine: (line) {
        _onScriptSessionLine(
          runId: runId,
          targetId: targetId,
          target: target,
          line: line,
          isStdErr: false,
          tracker: tracker,
          stderrBuffer: stderrBuffer,
          markerToken: markerToken,
        );
      },
    );
    final stderrDone = _pumpOutputLines(
      stream: process.stderr,
      useSystemEncoding: Platform.isWindows,
      onLine: (line) {
        _onScriptSessionLine(
          runId: runId,
          targetId: targetId,
          target: target,
          line: line,
          isStdErr: true,
          tracker: tracker,
          stderrBuffer: stderrBuffer,
          markerToken: markerToken,
        );
      },
    );

    final stepTimeout = runSession?.stepTimeoutSeconds != null
        ? Duration(seconds: runSession!.stepTimeoutSeconds!)
        : null;
    int exitCode;
    try {
      exitCode = stepTimeout != null
          ? await process.exitCode.timeout(stepTimeout)
          : await process.exitCode;
    } on TimeoutException {
      try { process.kill(ProcessSignal.sigterm); } catch (_) {}
      return _ScriptSessionExecutionResult(
        success: false,
        exitCode: -1,
        detail: 'step timeout (${runSession?.stepTimeoutSeconds}s)',
      );
    }
    await Future.wait(<Future<void>>[stdoutDone, stderrDone]);
    runSession?.unregisterProcess(process);
    return _buildScriptSessionResult(
      tracker: tracker,
      exitCode: exitCode,
      stderr: stderrBuffer.toString(),
    );
  }

  Future<_ScriptSessionExecutionResult> _runRemoteScriptSession({
    required String runId,
    required String targetId,
    required String target,
    required SSHClient client,
    required Map<String, String> environment,
    required String scriptBody,
    required List<_ScriptStepPlan> steps,
    String markerToken = '',
  }) async {
    SSHSession? session;
    try {
      final execEnv = environment.isEmpty ? null : environment;
      session = await client.execute(
        _wrapRemoteShellCommand(scriptBody),
        environment: execEnv,
      );
      final runSession = activeScriptRuns[runId];
      runSession?.registerProcess(null, session);

      final indexMap = <int, _ScriptStepPlan>{};
      for (var i = 0; i < steps.length; i++) {
        indexMap[i + 1] = steps[i];
      }
      final tracker = _ScriptSessionTracker(indexMap);
      final stderrBuffer = StringBuffer();
      final stdoutDone = _pumpOutputLines(
        stream: session.stdout,
        onLine: (line) {
          _onScriptSessionLine(
            runId: runId,
            targetId: targetId,
            target: target,
            line: line,
            isStdErr: false,
            tracker: tracker,
            stderrBuffer: stderrBuffer,
            markerToken: markerToken,
          );
        },
      );
      final stderrDone = _pumpOutputLines(
        stream: session.stderr,
        onLine: (line) {
          _onScriptSessionLine(
            runId: runId,
            targetId: targetId,
            target: target,
            line: line,
            isStdErr: true,
            tracker: tracker,
            stderrBuffer: stderrBuffer,
            markerToken: markerToken,
          );
        },
      );

      final stepTimeout = runSession?.stepTimeoutSeconds != null
          ? Duration(seconds: runSession!.stepTimeoutSeconds!)
          : null;
      try {
        if (stepTimeout != null) {
          await session.done.timeout(stepTimeout);
        } else {
          await session.done;
        }
      } on TimeoutException {
        try { session.close(); } catch (_) {}
        return _ScriptSessionExecutionResult(
          success: false,
          exitCode: -1,
          detail: 'step timeout (${runSession?.stepTimeoutSeconds}s)',
        );
      }
      await Future.wait(<Future<void>>[stdoutDone, stderrDone]);
      final exitCode = session.exitCode ?? (session.exitSignal == null ? 0 : 1);
      final signal = session.exitSignal;
      final signalInfo = signal?.errorMessage.trim() ?? '';
      final stderrText = stderrBuffer.toString().trim().isNotEmpty
          ? stderrBuffer.toString()
          : signalInfo;
      runSession?.unregisterSshSession(session);
      return _buildScriptSessionResult(
        tracker: tracker,
        exitCode: exitCode,
        stderr: stderrText,
      );
    } catch (error) {
      return _ScriptSessionExecutionResult(
        success: false,
        exitCode: -1,
        detail: '$error',
      );
    } finally {
      try {
        session?.close();
      } catch (_) {}
    }
  }

  void _onScriptSessionLine({
    required String runId,
    required String targetId,
    required String target,
    required String line,
    required bool isStdErr,
    required _ScriptSessionTracker tracker,
    required StringBuffer stderrBuffer,
    String markerToken = '',
  }) {
    final marker = markerToken.isNotEmpty
        ? _parseScriptStepMarker(line, markerToken)
        : null;
    if (marker != null) {
      final step = tracker.stepByIndex[marker.index];
      if (step != null) {
        if (marker.type == _ScriptStepMarkerType.start) {
          tracker.activeStepIndex = marker.index;
          _updateScriptRunProgressStep(
            runId: runId,
            targetId: targetId,
            targetName: target,
            stepIndex: marker.index,
            totalSteps: tracker.stepByIndex.length,
          );
          _emitScriptEvent(
            runId: runId,
            type: ScriptRunEventType.stepStarted,
            target: target,
            targetId: targetId,
            stepIndex: marker.index,
            command: step.command,
            message: step.kind == _ScriptStepKind.precheck
                ? 'precheck start'
                : 'step start',
          );
        } else {
          if (marker.exitCode == 0) {
            _emitScriptEvent(
              runId: runId,
              type: ScriptRunEventType.stepSucceeded,
              target: target,
              targetId: targetId,
              stepIndex: marker.index,
              command: step.command,
              message: 'exit=0',
            );
          } else if (step.allowFailure) {
            _emitScriptEvent(
              runId: runId,
              type: ScriptRunEventType.stepSucceeded,
              target: target,
              targetId: targetId,
              stepIndex: marker.index,
              command: step.command,
              message: 'exit=${marker.exitCode} (ignored)',
            );
          } else if (tracker.failedStepIndex == null) {
            tracker.failedStepIndex = marker.index;
            tracker.failedExitCode = marker.exitCode;
            final stepStderr = tracker.stepStderrSnippet(marker.index);
            final detail = _summarizeLocalStepFailure(
              command: step.command,
              stderr: stepStderr,
              exitCode: marker.exitCode ?? 1,
            );
            tracker.failedDetail =
                'step#${marker.index} exit=${marker.exitCode} ${detail.trim()}'
                    .trim();
            _emitScriptEvent(
              runId: runId,
              type: ScriptRunEventType.stepFailed,
              target: target,
              targetId: targetId,
              stepIndex: marker.index,
              command: step.command,
              message: tracker.failedDetail,
              notify: true,
            );
          }
          if (tracker.activeStepIndex == marker.index) {
            tracker.activeStepIndex = null;
          }
        }
      }
      return;
    }

    if (isStdErr && stderrBuffer.length < _scriptOutputSnippetLimit) {
      if (stderrBuffer.isNotEmpty) {
        stderrBuffer.write(' | ');
      }
      stderrBuffer.write(line);
    }

    final stepIndex = tracker.activeStepIndex;
    if (isStdErr && stepIndex != null) {
      tracker.appendStepStderr(stepIndex, line);
    }
    final command = stepIndex == null
        ? null
        : tracker.stepByIndex[stepIndex]?.command;
    _emitScriptEvent(
      runId: runId,
      type: isStdErr ? ScriptRunEventType.stderr : ScriptRunEventType.stdout,
      target: target,
      targetId: targetId,
      stepIndex: stepIndex,
      command: command,
      message: line,
      notify: true,
    );
  }

  _ScriptSessionExecutionResult _buildScriptSessionResult({
    required _ScriptSessionTracker tracker,
    required int exitCode,
    required String stderr,
  }) {
    final failedStepIndex = tracker.failedStepIndex;
    if (failedStepIndex != null) {
      final failedExitCode = tracker.failedExitCode ?? exitCode;
      final reason = (tracker.failedDetail ?? '').trim().isNotEmpty
          ? tracker.failedDetail!.trim()
          : 'step#$failedStepIndex exit=$failedExitCode';
      return _ScriptSessionExecutionResult(
        success: false,
        exitCode: failedExitCode,
        detail: reason,
      );
    }

    if (exitCode == 0) {
      return const _ScriptSessionExecutionResult(
        success: true,
        exitCode: 0,
        detail: 'ok',
      );
    }

    final detail = stderr.trim().isEmpty
        ? 'exit code $exitCode'
        : stderr.trim();
    return _ScriptSessionExecutionResult(
      success: false,
      exitCode: exitCode,
      detail: detail,
    );
  }

  List<_ScriptStepPlan> _buildScriptStepPlans(
    _CompiledScript plan, {
    List<ScriptStepConfig?>? stepConfigs,
  }) {
    final precheckSteps = plan.prechecks.map(
      (line) => _parseScriptStepPlan(_ScriptStepKind.precheck, line, 0),
    );
    final commandSteps = plan.commands.asMap().entries.map(
      (entry) => _parseScriptStepPlan(
        _ScriptStepKind.command, entry.value, entry.key,
        config: stepConfigs != null && entry.key < stepConfigs.length
            ? stepConfigs[entry.key]
            : null,
      ),
    );
    return <_ScriptStepPlan>[...precheckSteps, ...commandSteps];
  }

  _ScriptStepPlan _parseScriptStepPlan(
    _ScriptStepKind kind, String raw, int index, {
    ScriptStepConfig? config,
  }) {
    final trimmed = raw.trim();
    final allowFailure = config?.failurePolicy == ScriptStepFailurePolicy.stopOnFailure
        ? false
        : trimmed.startsWith('!')
            ? (trimmed.substring(1).trimLeft().isNotEmpty)
            : false;
    final command = trimmed.startsWith('!') && trimmed.substring(1).trimLeft().isNotEmpty
        ? trimmed.substring(1).trimLeft()
        : trimmed;
    if (config != null) {
      return _ScriptStepPlan(kind, command,
        allowFailure: allowFailure || config.failurePolicy == ScriptStepFailurePolicy.continueOnFailure,
        condition: config.condition,
        captureOutput: config.captureOutput,
        failurePolicy: config.failurePolicy,
        retryCount: config.retryCount,
      );
    }
    return _ScriptStepPlan(kind, command, allowFailure: allowFailure);
  }

  String? _buildLocalShellScript({
    required LocalShellType shellType,
    required List<_ScriptStepPlan> steps,
    required String markerToken,
  }) {
    if (Platform.isWindows) {
      switch (shellType) {
        case LocalShellType.systemDefault:
        case LocalShellType.commandPrompt:
          return _buildWindowsCmdScript(steps, markerToken);
        case LocalShellType.powershell:
        case LocalShellType.powershellAdmin:
          return _buildWindowsPowerShellScript(steps, markerToken);
        case LocalShellType.wsl:
        case LocalShellType.bash:
          return _buildPosixShellScript(steps, markerToken);
      }
    }
    if (Platform.isLinux || Platform.isMacOS || Platform.isAndroid) {
      switch (shellType) {
        case LocalShellType.systemDefault:
        case LocalShellType.bash:
        case LocalShellType.wsl:
          return _buildPosixShellScript(steps, markerToken);
        case LocalShellType.powershell:
        case LocalShellType.powershellAdmin:
        case LocalShellType.commandPrompt:
          return null;
      }
    }
    return null;
  }

  String _buildPosixShellScript(List<_ScriptStepPlan> steps, String markerToken) {
    final prefix = _markerPrefix(markerToken);
    final buffer = StringBuffer();
    buffer.writeln('set +e');
    buffer.writeln('_Polarmote_FAILED=0');
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final index = i + 1;
      switch (step.condition) {
        case ScriptStepCondition.always:
          _writePosixStep(buffer, prefix, index, step);
        case ScriptStepCondition.onSuccess:
          buffer.writeln('if [ "\$_Polarmote_FAILED" -eq 0 ]; then');
          _writePosixStep(buffer, prefix, index, step, indent: true);
          buffer.writeln('fi');
        case ScriptStepCondition.onFailure:
          buffer.writeln('if [ "\$_Polarmote_FAILED" -ne 0 ]; then');
          _writePosixStep(buffer, prefix, index, step, indent: true);
          buffer.writeln('fi');
      }
    }
    buffer.writeln('exit 0');
    return buffer.toString();
  }

  void _writePosixStep(StringBuffer buffer, String prefix, int index, _ScriptStepPlan step, {bool indent = false}) {
    final indentStr = indent ? '  ' : '';
    buffer.writeln(
      "${indentStr}printf '$prefix:START:$index:${step.kind.name}\\n'",
    );
    buffer.writeln('${indentStr}eval ${_quotePosix(step.command)}');
    buffer.writeln('${indentStr}rc=\$?');
    buffer.writeln(
      "${indentStr}printf '$prefix:END:$index:%s\\n' \"\$rc\"",
    );
    buffer.writeln('${indentStr}if [ "\$rc" -ne 0 ]; then _Polarmote_FAILED=1; fi');
    if (!step.allowFailure) {
      buffer.writeln('${indentStr}if [ "\$_Polarmote_FAILED" -eq 0 ] && [ "\$rc" -ne 0 ]; then exit "\$rc"; fi');
    }
  }

  String _buildWindowsCmdScript(List<_ScriptStepPlan> steps, String markerToken) {
    final prefix = _markerPrefix(markerToken);
    final buffer = StringBuffer();
    buffer.writeln('@echo off');
    buffer.writeln('setlocal EnableExtensions DisableDelayedExpansion');
    buffer.writeln('set "Polarmote_FAILED=0"');
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final index = i + 1;
      switch (step.condition) {
        case ScriptStepCondition.always:
          _writeCmdStep(buffer, prefix, index, step);
        case ScriptStepCondition.onSuccess:
          buffer.writeln('if not "%Polarmote_FAILED%"=="1" (');
          _writeCmdStep(buffer, prefix, index, step, indent: true);
          buffer.writeln(')');
        case ScriptStepCondition.onFailure:
          buffer.writeln('if "%Polarmote_FAILED%"=="1" (');
          _writeCmdStep(buffer, prefix, index, step, indent: true);
          buffer.writeln(')');
      }
    }
    buffer.writeln('exit /b 0');
    return buffer.toString();
  }

  void _writeCmdStep(StringBuffer buffer, String prefix, int index, _ScriptStepPlan step, {bool indent = false}) {
    final i = indent ? '  ' : '';
    buffer.writeln(
      '$i@echo $prefix:START:$index:${step.kind.name}',
    );
    final normalized = step.command
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    for (final line in normalized.split('\n')) {
      buffer.writeln('$i$line');
    }
    buffer.writeln('$i set "Polarmote_RC=!ERRORLEVEL!"');
    buffer.writeln('$i @echo $prefix:END:$index:!Polarmote_RC!');
    buffer.writeln('$i if not "!Polarmote_RC!"=="0" set "Polarmote_FAILED=1"');
    if (!step.allowFailure) {
      buffer.writeln('${i}if "!Polarmote_FAILED!"=="0" if not "!Polarmote_RC!"=="0" exit /b !Polarmote_RC!');
    }
  }

  String _buildWindowsPowerShellScript(List<_ScriptStepPlan> steps, String markerToken) {
    final prefix = _markerPrefix(markerToken);
    final buffer = StringBuffer();
    buffer.writeln(r"$ErrorActionPreference = 'Continue'");
    buffer.writeln(r'$PolarmoteFailed = $false');
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final index = i + 1;
      switch (step.condition) {
        case ScriptStepCondition.always:
          _writePowerShellStep(buffer, prefix, index, step);
        case ScriptStepCondition.onSuccess:
          buffer.writeln('if (-not \$PolarmoteFailed) {');
          _writePowerShellStep(buffer, prefix, index, step, indent: true);
          buffer.writeln('}');
        case ScriptStepCondition.onFailure:
          buffer.writeln('if (\$PolarmoteFailed) {');
          _writePowerShellStep(buffer, prefix, index, step, indent: true);
          buffer.writeln('}');
      }
    }
    buffer.writeln('exit 0');
    return buffer.toString();
  }

  void _writePowerShellStep(StringBuffer buffer, String prefix, int index, _ScriptStepPlan step, {bool indent = false}) {
    final i = indent ? '  ' : '';
    final encodedCommand = base64Encode(utf8.encode(step.command));
    buffer.writeln(
      '${i}Write-Output "$prefix:START:$index:${step.kind.name}"',
    );
    buffer.writeln(
      "$i \$PolarmoteCommand = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('$encodedCommand'))",
    );
    buffer.writeln('${i}Invoke-Expression \$PolarmoteCommand');
    buffer.writeln(
      '$i \$PolarmoteRc = if (\$null -eq \$LASTEXITCODE) { if (\$?) { 0 } else { 1 } } else { [int]\$LASTEXITCODE }',
    );
    buffer.writeln(
      '${i}Write-Output "$prefix:END:$index:\$PolarmoteRc"',
    );
    buffer.writeln('${i}if (\$PolarmoteRc -ne 0) { \$PolarmoteFailed = \$true }');
    if (!step.allowFailure) {
      buffer.writeln('${i}if ((-not \$PolarmoteFailed) -and (\$PolarmoteRc -ne 0)) { exit \$PolarmoteRc }');
    }
  }

  _ScriptStepMarker? _parseScriptStepMarker(String line, String markerToken) {
    final prefix = _markerPrefix(markerToken);
    if (!line.startsWith('$prefix:')) {
      return null;
    }
    final parts = line.split(':');
    if (parts.length < 4) {
      return null;
    }
    if (parts[1] == 'START') {
      final index = int.tryParse(parts[2]);
      if (index == null || index <= 0) {
        return null;
      }
      return _ScriptStepMarker.start(index);
    }
    if (parts[1] == 'END') {
      final index = int.tryParse(parts[2]);
      final code = int.tryParse(parts[3]);
      if (index == null || index <= 0 || code == null) {
        return null;
      }
      return _ScriptStepMarker.end(index, code);
    }
    return null;
  }

  String _quotePosix(String input) {
    return "'${input.replaceAll("'", "'\"'\"'")}'";
  }

  Future<void> _pumpOutputLines({
    required Stream<List<int>> stream,
    required void Function(String line) onLine,
    bool useSystemEncoding = false,
  }) async {
    final decoder = useSystemEncoding
        ? systemEncoding.decoder
        : const Utf8Decoder(allowMalformed: true);
    final normalizedByteStream = stream.map<List<int>>((chunk) => chunk);
    await for (final line
        in normalizedByteStream
            .transform(decoder)
            .transform(const LineSplitter())) {
      final normalized = line.trimRight();
      if (normalized.isEmpty) {
        continue;
      }
      onLine(normalized);
    }
  }

  Map<String, _ScriptRunProgressState> _scriptRunProgressStore() {
    return _scriptRunProgressByState[this] ??=
        <String, _ScriptRunProgressState>{};
  }

  void _beginScriptRunProgress({
    required String runId,
    required String scriptName,
    required int totalTargets,
    required int commandsPerTarget,
  }) {
    final normalizedTargets = totalTargets.clamp(1, 100000);
    final normalizedCommands = commandsPerTarget.clamp(1, 100000);
    _scriptRunProgressStore()[runId] = _ScriptRunProgressState(
      runId: runId,
      scriptName: scriptName,
      totalTargets: normalizedTargets,
      commandsPerTarget: normalizedCommands,
    );
    notifyState();
  }

  void _updateScriptRunProgressStep({
    required String runId,
    required String targetId,
    required String targetName,
    required int stepIndex,
    required int totalSteps,
  }) {
    final state = _scriptRunProgressStore()[runId];
    if (state == null) {
      return;
    }
    final normalizedTotal = totalSteps.clamp(1, state.commandsPerTarget);
    final normalizedStep = stepIndex.clamp(1, normalizedTotal);
    state.stepByTarget[targetId] = normalizedStep;
    state.targetNameById[targetId] = targetName;
  }

  void _markScriptRunProgressTargetCompleted({
    required String runId,
    required String targetId,
    required String targetName,
  }) {
    final state = _scriptRunProgressStore()[runId];
    if (state == null) {
      return;
    }
    if (state.completedTargetIds.add(targetId)) {
      state.stepByTarget.remove(targetId);
    }
  }

  void _finishScriptRunProgress({
    required String runId,
    required int attempted,
    required int executed,
    required int failed,
  }) {
    final state = _scriptRunProgressStore().remove(runId);
    if (state != null) {
      notifyState();
    }
  }

  Future<void> _notifyScriptRunSystemResult({
    required ScriptEntry script,
    required int executed,
    required int failed,
    required bool notifyEnabled,
  }) async {
    if (!notifyEnabled) {
      return;
    }
    if (executed <= 0 && failed <= 0) {
      return;
    }
    final hasFailure = failed > 0;
    final title = hasFailure
        ? AppStrings.values.scriptSystemNotificationFailedTitleVar.resolve(
            locale.languageCode,
            params: {'name': script.name},
          )
        : AppStrings.values.scriptSystemNotificationCompletedTitleVar.resolve(
            locale.languageCode,
            params: {'name': script.name},
          );
    final summary = AppStrings.values.runSummaryVarVar.resolve(
      locale.languageCode,
      params: {'success': '$executed', 'failed': '$failed'},
    );
    await PolarmoteSystemNotifications.showScriptResult(
      title: title,
      body: summary,
      failed: hasFailure,
    );
  }

  String _summarizeLocalStepFailure({
    required String command,
    required String stderr,
    required int exitCode,
  }) {
    final normalized = stderr.toLowerCase();
    final commandParts = command.trim().split(RegExp(r'\s+'));
    final firstToken = commandParts.isEmpty ? '' : commandParts.first;
    final isCommandNotFound =
        normalized.contains('commandnotfoundexception') ||
        normalized.contains('is not recognized as the name of a cmdlet') ||
        normalized.contains(
          'is not recognized as an internal or external command',
        ) ||
        normalized.contains('无法将') && normalized.contains('识别') ||
        normalized.contains('不是内部或外部命令');
    if (isCommandNotFound && firstToken.isNotEmpty) {
      if (locale.languageCode == 'zh') {
        return '命令不存在: $firstToken（请使用绝对路径，或把命令目录加入 PATH）';
      }
      return 'command not found: $firstToken (use absolute path or add command directory to PATH)';
    }
    final compact = stderr.trim();
    if (compact.isEmpty) {
      return 'exit code $exitCode';
    }
    if (compact.length > _scriptOutputSnippetLimit) {
      return compact.substring(0, _scriptOutputSnippetLimit);
    }
    return compact;
  }

  void _emitScriptEvent({
    required String runId,
    required ScriptRunEventType type,
    required String target,
    String? targetId,
    int? stepIndex,
    String? message,
    String? command,
    bool notify = false,
  }) {
    final event = ScriptRunEvent(
      runId: runId,
      type: type,
      timestamp: DateTime.now(),
      target: target,
      targetId: targetId,
      stepIndex: stepIndex,
      message: message,
      command: command,
    );

    final storage = _scriptRunEventsByState[this] ??= <ScriptRunEvent>[];
    storage.add(event);
    if (storage.length > _scriptRunEventLimit) {
      storage.removeRange(0, storage.length - _scriptRunEventLimit);
    }

    _updateScriptRunSession(event);

    if (!_shouldLogScriptEvent(type)) {
      return;
    }

    final eventLabel = _scriptEventTypeLabel(type);
    final indexPart = stepIndex == null ? '' : '#$stepIndex ';
    final messagePart = (message ?? '').trim();
    final detail = messagePart.isEmpty
        ? indexPart.trim()
        : '$indexPart$messagePart';
    addStructuredLog(
      category: TerminalLogCategory.script,
      message: AppStrings.values.scriptLogEventVarVarVar.resolve(
        locale.languageCode,
        params: {
          'runId': runId,
          'target': target,
          'event': eventLabel,
          'detail': detail.isEmpty ? '' : ' $detail',
        },
      ),
      notifyListeners: notify,
    );
  }

  void _updateScriptRunSession(ScriptRunEvent event) {
    final runId = event.runId;
    final type = event.type;
    final targetId = event.targetId;
    final stepIndex = event.stepIndex;

    final session = activeScriptRuns[runId];
    if (session == null) return;

    if (type == ScriptRunEventType.runStarted) {
      session.isFinished = false;
      notifyState();
      return;
    }

    if (targetId == null || targetId.isEmpty) {
      if (type == ScriptRunEventType.runFinished) {
        session.isFinished = true;
        notifyState();
      }
      return;
    }

    final targetState = session.targets[targetId];
    if (targetState == null) {
      if (type == ScriptRunEventType.targetStarted ||
          type == ScriptRunEventType.stepStarted ||
          type == ScriptRunEventType.stdout ||
          type == ScriptRunEventType.stderr) {
        final target = session.ensureTarget(targetId, event.target);
        target.status = ScriptTargetRunStatus.running;
        if (type == ScriptRunEventType.targetStarted) {
          target.startedAt = event.timestamp;
        }
        target.currentStep = stepIndex ?? 0;
        target.totalSteps = totalStepsForRun(runId);
        notifyState();
      }
      return;
    }

    switch (type) {
      case ScriptRunEventType.runStarted:
      case ScriptRunEventType.targetStarted:
        targetState.status = ScriptTargetRunStatus.running;
        targetState.startedAt = event.timestamp;
        targetState.totalSteps = totalStepsForRun(runId);
        notifyState();

      case ScriptRunEventType.targetSucceeded:
        targetState.status = ScriptTargetRunStatus.success;
        targetState.finishedAt = event.timestamp;
        targetState.detail = event.message;
        notifyState();

      case ScriptRunEventType.targetFailed:
        targetState.status = ScriptTargetRunStatus.failed;
        targetState.finishedAt = event.timestamp;
        targetState.detail = event.message;
        notifyState();

      case ScriptRunEventType.stepStarted:
        targetState.status = ScriptTargetRunStatus.running;
        if (stepIndex != null) {
          targetState.currentStep = stepIndex;
          final existing = targetState.ensureStep(
            stepIndex,
            event.command ?? '',
          );
          existing.status = ScriptTargetRunStatus.running;
        }
        notifyState();

      case ScriptRunEventType.stepSucceeded:
        if (stepIndex != null) {
          final step = targetState.ensureStep(
            stepIndex,
            event.command ?? '',
          );
          step.status = ScriptTargetRunStatus.success;
          step.exitCode = 0;
        }
        notifyState();

      case ScriptRunEventType.stepFailed:
        if (stepIndex != null) {
          final step = targetState.ensureStep(
            stepIndex,
            event.command ?? '',
          );
          step.status = ScriptTargetRunStatus.failed;
          step.exitCode = -1;
        }
        notifyState();

      case ScriptRunEventType.stdout:
      case ScriptRunEventType.stderr:
        if (stepIndex != null) {
          final step = targetState.ensureStep(
            stepIndex,
            event.command ?? '',
          );
          if (step.lines.length < 5000) {
            step.lines.add(ScriptOutputLine(
              text: event.message ?? '',
              isStderr: type == ScriptRunEventType.stderr,
            ));
          }
        }

      case ScriptRunEventType.runFinished:
        session.isFinished = true;
        notifyState();
    }
  }

  int totalStepsForRun(String runId) {
    final storage = _scriptRunProgressByState[this];
    if (storage == null) return 0;
    final progress = storage[runId];
    if (progress == null) return 0;
    return progress.commandsPerTarget;
  }

  String _scriptEventTypeLabel(ScriptRunEventType type) {
    switch (type) {
      case ScriptRunEventType.runStarted:
        return AppStrings.values.scriptEventRunStarted.resolve(
          locale.languageCode,
        );
      case ScriptRunEventType.targetStarted:
        return AppStrings.values.scriptEventTargetStarted.resolve(
          locale.languageCode,
        );
      case ScriptRunEventType.stepStarted:
        return AppStrings.values.scriptEventStepStarted.resolve(
          locale.languageCode,
        );
      case ScriptRunEventType.stdout:
        return AppStrings.values.scriptEventStdout.resolve(locale.languageCode);
      case ScriptRunEventType.stderr:
        return AppStrings.values.scriptEventStderr.resolve(locale.languageCode);
      case ScriptRunEventType.stepSucceeded:
        return AppStrings.values.scriptEventStepSucceeded.resolve(
          locale.languageCode,
        );
      case ScriptRunEventType.stepFailed:
        return AppStrings.values.scriptEventStepFailed.resolve(
          locale.languageCode,
        );
      case ScriptRunEventType.targetSucceeded:
        return AppStrings.values.scriptEventTargetSucceeded.resolve(
          locale.languageCode,
        );
      case ScriptRunEventType.targetFailed:
        return AppStrings.values.scriptEventTargetFailed.resolve(
          locale.languageCode,
        );
      case ScriptRunEventType.runFinished:
        return AppStrings.values.scriptEventRunFinished.resolve(
          locale.languageCode,
        );
    }
  }

  bool _shouldLogScriptEvent(ScriptRunEventType type) {
    switch (type) {
      case ScriptRunEventType.stepFailed:
        return true;
      case ScriptRunEventType.runFinished:
        return false;
      case ScriptRunEventType.runStarted:
      case ScriptRunEventType.targetStarted:
      case ScriptRunEventType.stepStarted:
      case ScriptRunEventType.stdout:
      case ScriptRunEventType.stderr:
      case ScriptRunEventType.stepSucceeded:
      case ScriptRunEventType.targetSucceeded:
      case ScriptRunEventType.targetFailed:
        return false;
    }
  }

  HostEntry _buildEphemeralLocalHost(LocalShellType shellType) {
    final localUser =
        Platform.environment['USERNAME'] ??
        Platform.environment['USER'] ??
        'local';
    final now = DateTime.now().microsecondsSinceEpoch;
    return HostEntry(
      id: 'script-local-$now-${shellType.name}',
      name: 'Local ${shellType.name}',
      host: 'local',
      port: 0,
      username: localUser,
      group: AppStrings.values.quickConnect.resolve(locale.languageCode),
      authType: AuthType.password,
      connectionType: ConnectionType.local,
      localShellType: shellType,
    );
  }

  String _wrapRemoteShellCommand(String command) {
    final escaped = command.replaceAll("'", "'\"'\"'");
    return "LC_ALL=en_US.UTF-8 sh -lc '$escaped'";
  }

  (String, List<String>)? _resolveBackgroundLocalShellSpec(
    LocalShellType shellType,
    String command,
  ) {
    if (Platform.isWindows) {
      switch (shellType) {
        case LocalShellType.systemDefault:
        case LocalShellType.commandPrompt:
          return ('cmd.exe', <String>['/Q', '/D', '/C', command]);
        case LocalShellType.powershell:
        case LocalShellType.powershellAdmin:
          return (
            'powershell.exe',
            <String>[
              '-NoProfile',
              '-ExecutionPolicy',
              'Bypass',
              '-Command',
              command,
            ],
          );
        case LocalShellType.wsl:
          return ('wsl.exe', <String>['sh', '-lc', command]);
        case LocalShellType.bash:
          return ('bash.exe', <String>['--login', '-c', command]);
      }
    }
    if (Platform.isAndroid) {
      final shell = File('/system/bin/sh').existsSync()
          ? '/system/bin/sh'
          : 'sh';
      return (shell, <String>['-c', command]);
    }
    if (Platform.isLinux || Platform.isMacOS) {
      final shellEnv = Platform.environment['SHELL']?.trim();
      final shell = (shellType == LocalShellType.bash)
          ? '/bin/bash'
          : ((shellEnv != null && shellEnv.isNotEmpty) ? shellEnv : '/bin/sh');
      return (shell, <String>['-lc', command]);
    }
    return null;
  }
}


