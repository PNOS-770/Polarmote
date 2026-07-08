import 'package:Polarmote/features/terminal/models/host_entry.dart';
import 'package:Polarmote/features/terminal/models/script_batch_template.dart';
import 'package:Polarmote/features/terminal/models/script_entry.dart';
import 'package:Polarmote/features/terminal/models/script_trigger_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ScriptBatchTemplate json roundtrip keeps key fields', () {
    final now = DateTime(2026, 2, 23, 12, 0, 0);
    final source = ScriptBatchTemplate(
      id: 'tpl-1',
      scriptId: 'script-1',
      name: 'Prod Rolling',
      hostIds: const <String>['host-a', 'host-b'],
      localShellTypes: const <LocalShellType>[LocalShellType.bash],
      silentExecution: true,
      failurePolicy: ScriptFailurePolicy.retryHost,
      retryPerHost: 2,
      maxConcurrency: 3,
      templateArgs: const <String, String>{'env': 'prod'},
      environmentOverrides: const <String, String>{'DEBUG': '0'},
      createdAt: now,
      updatedAt: now,
    );

    final parsed = ScriptBatchTemplate.fromJson(source.toJson());
    expect(parsed.id, source.id);
    expect(parsed.scriptId, source.scriptId);
    expect(parsed.name, source.name);
    expect(parsed.hostIds, source.hostIds);
    expect(parsed.localShellTypes, source.localShellTypes);
    expect(parsed.failurePolicy, ScriptFailurePolicy.retryHost);
    expect(parsed.retryPerHost, 2);
    expect(parsed.maxConcurrency, 3);
    expect(parsed.templateArgs['env'], 'prod');
    expect(parsed.environmentOverrides['DEBUG'], '0');
  });

  test('ScriptTriggerEntry fromJson normalizes values', () {
    final parsed = ScriptTriggerEntry.fromJson({
      'id': 'trigger-1',
      'scriptId': 'script-1',
      'name': 'on connect',
      'enabled': true,
      'eventType': 'sessionConnected',
      'matchType': 'regex',
      'commandPattern': 'deploy.*',
      'hostIds': ['host-a', ''],
      'executeAsMacro': true,
      'silentExecution': false,
      'failurePolicy': 'stopOnFailure',
      'retryPerHost': 7,
      'maxConcurrency': 99,
      'cooldownSeconds': -1,
    });

    expect(parsed.id, 'trigger-1');
    expect(parsed.scriptId, 'script-1');
    expect(parsed.hostIds, const <String>['host-a']);
    expect(parsed.eventType, ScriptTriggerEventType.sessionConnected);
    expect(parsed.matchType, ScriptTriggerMatchType.regex);
    expect(parsed.failurePolicy, ScriptFailurePolicy.stopOnFailure);
    expect(parsed.retryPerHost, 6);
    expect(parsed.maxConcurrency, 8);
    expect(parsed.cooldownSeconds, 0);
    expect(parsed.executeAsMacro, isTrue);
  });
}
