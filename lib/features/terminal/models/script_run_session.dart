import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
enum ScriptTargetRunStatus { pending, running, success, failed, cancelled }

class _CancellableProcess {
  final Process? process;
  final SSHSession? sshSession;

  _CancellableProcess(this.process, this.sshSession);

  void kill() {
    process?.kill(ProcessSignal.sigterm);
    try {
      sshSession?.close();
    } catch (_) {}
  }
}

class ScriptRunSession {
  ScriptRunSession({
    required this.runId,
    required this.scriptId,
    required this.scriptName,
    required this.targetCount,
    this.silent = true,
    this.stepTimeoutSeconds,
    this.runTimeoutSeconds,
    this.workingDirectory,
  })  : targets = {},
        createdAt = DateTime.now();

  final String runId;
  final String scriptId;
  final String scriptName;
  final DateTime createdAt;
  final Map<String, ScriptRunTargetState> targets;
  int targetCount;
  final bool silent;
  bool isFinished = false;
  bool isCancelled = false;
  int? stepTimeoutSeconds;
  int? runTimeoutSeconds;
  String? workingDirectory;
  bool _cancelling = false;
  final List<_CancellableProcess> _activeProcesses = [];

  int get completedTargets =>
      targets.values.where((t) => t.isCompleted).length;
  int get failedTargets =>
      targets.values.where((t) => t.status == ScriptTargetRunStatus.failed).length;
  int get cancelledTargets =>
      targets.values.where((t) => t.status == ScriptTargetRunStatus.cancelled).length;
  double get progress =>
      targetCount == 0 ? 0 : completedTargets / targetCount;
  bool get isRunning => !isFinished && targets.values.any((t) => t.status == ScriptTargetRunStatus.running);

  ScriptRunTargetState ensureTarget(String targetId, String targetName) {
    return targets.putIfAbsent(
      targetId,
      () => ScriptRunTargetState(targetId: targetId, targetName: targetName),
    );
  }

  void registerProcess(Process? process, SSHSession? sshSession) {
    if (_cancelling) {
      try { process?.kill(ProcessSignal.sigterm); } catch (_) {}
      try { sshSession?.close(); } catch (_) {}
      return;
    }
    _activeProcesses.add(_CancellableProcess(process, sshSession));
  }

  void unregisterProcess(Process process) {
    _activeProcesses.removeWhere((p) => p.process == process);
  }
  void unregisterSshSession(SSHSession sshSession) {
    _activeProcesses.removeWhere((p) => p.sshSession == sshSession);
  }

  void cancel() {
    _cancelling = true;
    isCancelled = true;
    for (final proc in _activeProcesses) {
      proc.kill();
    }
    _activeProcesses.clear();
    for (final target in targets.values) {
      if (target.status == ScriptTargetRunStatus.running ||
          target.status == ScriptTargetRunStatus.pending) {
        target.status = ScriptTargetRunStatus.cancelled;
        target.detail = 'cancelled';
      }
    }
    isFinished = true;
  }
}

class ScriptRunTargetState {
  ScriptRunTargetState({
    required this.targetId,
    required this.targetName,
  }) : steps = [];

  final String targetId;
  final String targetName;
  ScriptTargetRunStatus status = ScriptTargetRunStatus.pending;
  int currentStep = 0;
  int totalSteps = 0;
  DateTime? startedAt;
  DateTime? finishedAt;
  String? detail;
  final List<ScriptRunStepState> steps;

  bool get isCompleted =>
      status == ScriptTargetRunStatus.success ||
      status == ScriptTargetRunStatus.failed ||
      status == ScriptTargetRunStatus.cancelled;

  ScriptRunStepState ensureStep(int index, String command,
      {bool isPrecheck = false, bool allowFailure = false}) {
    for (final step in steps) {
      if (step.index == index) return step;
    }
    final step = ScriptRunStepState(
      index: index,
      command: command,
      isPrecheck: isPrecheck,
      allowFailure: allowFailure,
    );
    steps.add(step);
    steps.sort((a, b) => a.index.compareTo(b.index));
    return step;
  }
}

class ScriptRunStepState {
  ScriptRunStepState({
    required this.index,
    required this.command,
    this.isPrecheck = false,
    this.allowFailure = false,
  }) : lines = [];

  final int index;
  final String command;
  final bool isPrecheck;
  final bool allowFailure;
  ScriptTargetRunStatus status = ScriptTargetRunStatus.pending;
  int? exitCode;
  final List<ScriptOutputLine> lines;
}

class ScriptOutputLine {
  ScriptOutputLine({
    required this.text,
    this.isStderr = false,
  });

  final String text;
  final bool isStderr;
}



