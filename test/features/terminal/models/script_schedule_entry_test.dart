import 'package:Polarmote/features/terminal/models/host_entry.dart';
import 'package:Polarmote/features/terminal/models/script_entry.dart';
import 'package:Polarmote/features/terminal/models/script_schedule_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ScriptScheduleEntry json round-trip keeps new fields', () {
    final createdAt = DateTime.utc(2026, 2, 21, 10, 30);
    final updatedAt = DateTime.utc(2026, 2, 21, 10, 35);
    final lastTriggeredAt = DateTime.utc(2026, 2, 21, 10, 40);
    final lastEvaluatedAt = DateTime.utc(2026, 2, 21, 10, 41);
    final entry = ScriptScheduleEntry(
      id: 'schedule-1',
      scriptId: 'script-1',
      cronExpression: '*/5 * * * *',
      enabled: true,
      hostIds: const ['host-1'],
      localShellTypes: const [LocalShellType.powershell],
      failurePolicy: ScriptFailurePolicy.retryHost,
      retryPerHost: 3,
      silentExecution: true,
      timezoneOffsetMinutes: 480,
      missedRunPolicy: ScriptScheduleMissedRunPolicy.catchUpAll,
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastTriggeredAt: lastTriggeredAt,
      lastEvaluatedAt: lastEvaluatedAt,
    );

    final decoded = ScriptScheduleEntry.fromJson(entry.toJson());
    expect(decoded.id, entry.id);
    expect(decoded.scriptId, entry.scriptId);
    expect(decoded.cronExpression, entry.cronExpression);
    expect(decoded.enabled, isTrue);
    expect(decoded.hostIds, entry.hostIds);
    expect(decoded.localShellTypes, entry.localShellTypes);
    expect(decoded.failurePolicy, entry.failurePolicy);
    expect(decoded.retryPerHost, entry.retryPerHost);
    expect(decoded.silentExecution, isTrue);
    expect(decoded.timezoneOffsetMinutes, 480);
    expect(decoded.missedRunPolicy, ScriptScheduleMissedRunPolicy.catchUpAll);
    expect(decoded.createdAt.toIso8601String(), createdAt.toIso8601String());
    expect(decoded.updatedAt.toIso8601String(), updatedAt.toIso8601String());
    expect(
      decoded.lastTriggeredAt?.toIso8601String(),
      lastTriggeredAt.toIso8601String(),
    );
    expect(
      decoded.lastEvaluatedAt?.toIso8601String(),
      lastEvaluatedAt.toIso8601String(),
    );
  });

  test('ScriptScheduleEntry.fromJson keeps backward compatibility', () {
    final before = DateTime.now().toUtc();
    final entry = ScriptScheduleEntry.fromJson({
      'id': 'legacy',
      'scriptId': 'script-legacy',
      'cronExpression': '0 0 * * *',
      'retryPerHost': 'invalid',
      'failurePolicy': 'unknown',
      'localShellTypes': const ['not-found'],
      'timezoneOffsetMinutes': 'not-number',
      'missedRunPolicy': 'unknown',
    });
    final after = DateTime.now().toUtc();

    expect(entry.id, 'legacy');
    expect(entry.scriptId, 'script-legacy');
    expect(entry.retryPerHost, 1);
    expect(entry.failurePolicy, ScriptFailurePolicy.continueOnFailure);
    expect(entry.localShellTypes, isEmpty);
    expect(entry.missedRunPolicy, ScriptScheduleMissedRunPolicy.skip);
    expect(
      entry.timezoneOffsetMinutes,
      DateTime.now().timeZoneOffset.inMinutes,
    );
    expect(entry.lastEvaluatedAt, isNotNull);
    expect(entry.lastEvaluatedAt!.toUtc().isBefore(before), isFalse);
    expect(entry.lastEvaluatedAt!.toUtc().isAfter(after), isFalse);
  });
}
