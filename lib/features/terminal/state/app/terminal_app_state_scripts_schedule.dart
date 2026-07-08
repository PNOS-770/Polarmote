part of 'terminal_app_state_scripts.dart';

extension TerminalAppStateScriptsSchedule on TerminalAppState {
  void ensureScriptScheduleRuntime() {
    final existing = _scriptScheduleTimerByState[this];
    if (existing?.isActive ?? false) return;
    _scriptScheduleTimerByState[this] = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(_runScriptScheduleTick()),
    );
    Future.microtask(() => _runScriptScheduleTick());
  }

  void disposeScriptScheduleRuntime() {
    _scriptScheduleTimerByState[this]?.cancel();
    _scriptScheduleRunningByState[this]?.clear();
  }

  List<ScriptScheduleEntry> scriptSchedulesForScript(String scriptId) {
    return scriptSchedules.where((item) => item.scriptId == scriptId).toList(growable: false);
  }

  DateTime? scriptScheduleNextTriggerTime(ScriptScheduleEntry schedule, {DateTime? from}) {
    final expression = schedule.cronExpression.trim();
    if (!CronExpression.isValid(expression)) return null;
    final offsetMinutes = schedule.timezoneOffsetMinutes.clamp(-12 * 60, 14 * 60);
    final offset = Duration(minutes: offsetMinutes);
    final startUtc = (from ?? DateTime.now()).toUtc();
    final startLocal = startUtc.add(offset);
    var cursor = CronExpression.minuteBucket(startLocal);
    if (!cursor.isAfter(startLocal)) cursor = cursor.add(const Duration(minutes: 1));
    const maxSearchMinutes = 366 * 24 * 60;
    for (var i = 0; i < maxSearchMinutes; i++) {
      if (CronExpression.matches(expression, cursor)) return cursor.subtract(offset).toLocal();
      cursor = cursor.add(const Duration(minutes: 1));
    }
    return null;
  }

  void upsertScriptScheduleEntry(ScriptScheduleEntry entry) {
    final scriptId = entry.scriptId.trim();
    if (scriptId.isEmpty) return;
    final index = scriptSchedules.indexWhere((item) => item.id == entry.id);
    final now = DateTime.now();
    final normalized = entry.copyWith(
      retryPerHost: entry.retryPerHost.clamp(1, 6),
      timezoneOffsetMinutes: entry.timezoneOffsetMinutes.clamp(-12 * 60, 14 * 60),
      updatedAt: now,
      lastEvaluatedAt: entry.lastEvaluatedAt ?? CronExpression.minuteBucket(now.toUtc()),
    );
    if (index >= 0) scriptSchedules[index] = normalized;
    else scriptSchedules.add(normalized);
    ensureScriptScheduleRuntime();
    scheduleStateSave();
    notifyState();
  }

  void removeScriptScheduleEntry(String scheduleId) {
    if (scheduleId.trim().isEmpty) return;
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
}

