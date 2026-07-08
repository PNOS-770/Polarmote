import 'script_entry.dart';
import 'host_entry.dart';

enum ScriptScheduleMissedRunPolicy { skip, catchUpOnce, catchUpAll }

ScriptScheduleMissedRunPolicy _parseMissedRunPolicy(String raw) {
  final value = raw.trim().toLowerCase();
  for (final policy in ScriptScheduleMissedRunPolicy.values) {
    if (policy.name.toLowerCase() == value) {
      return policy;
    }
  }
  return ScriptScheduleMissedRunPolicy.skip;
}

class ScriptScheduleEntry {
  const ScriptScheduleEntry({
    required this.id,
    required this.scriptId,
    required this.cronExpression,
    required this.enabled,
    required this.hostIds,
    required this.localShellTypes,
    required this.failurePolicy,
    required this.retryPerHost,
    required this.silentExecution,
    required this.timezoneOffsetMinutes,
    required this.missedRunPolicy,
    required this.createdAt,
    required this.updatedAt,
    this.lastTriggeredAt,
    this.lastEvaluatedAt,
  });

  final String id;
  final String scriptId;
  final String cronExpression;
  final bool enabled;
  final List<String> hostIds;
  final List<LocalShellType> localShellTypes;
  final ScriptFailurePolicy failurePolicy;
  final int retryPerHost;
  final bool silentExecution;
  final int timezoneOffsetMinutes;
  final ScriptScheduleMissedRunPolicy missedRunPolicy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastTriggeredAt;
  final DateTime? lastEvaluatedAt;

  ScriptScheduleEntry copyWith({
    String? cronExpression,
    bool? enabled,
    List<String>? hostIds,
    List<LocalShellType>? localShellTypes,
    ScriptFailurePolicy? failurePolicy,
    int? retryPerHost,
    bool? silentExecution,
    int? timezoneOffsetMinutes,
    ScriptScheduleMissedRunPolicy? missedRunPolicy,
    DateTime? updatedAt,
    DateTime? lastTriggeredAt,
    DateTime? lastEvaluatedAt,
  }) {
    return ScriptScheduleEntry(
      id: id,
      scriptId: scriptId,
      cronExpression: cronExpression ?? this.cronExpression,
      enabled: enabled ?? this.enabled,
      hostIds: hostIds ?? this.hostIds,
      localShellTypes: localShellTypes ?? this.localShellTypes,
      failurePolicy: failurePolicy ?? this.failurePolicy,
      retryPerHost: retryPerHost ?? this.retryPerHost,
      silentExecution: silentExecution ?? this.silentExecution,
      timezoneOffsetMinutes:
          timezoneOffsetMinutes ?? this.timezoneOffsetMinutes,
      missedRunPolicy: missedRunPolicy ?? this.missedRunPolicy,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastTriggeredAt: lastTriggeredAt ?? this.lastTriggeredAt,
      lastEvaluatedAt: lastEvaluatedAt ?? this.lastEvaluatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'scriptId': scriptId,
      'cronExpression': cronExpression,
      'enabled': enabled,
      'hostIds': hostIds,
      'localShellTypes': localShellTypes.map((item) => item.name).toList(),
      'failurePolicy': failurePolicy.name,
      'retryPerHost': retryPerHost,
      'silentExecution': silentExecution,
      'timezoneOffsetMinutes': timezoneOffsetMinutes,
      'missedRunPolicy': missedRunPolicy.name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'lastTriggeredAt': lastTriggeredAt?.toIso8601String(),
      'lastEvaluatedAt': lastEvaluatedAt?.toIso8601String(),
    };
  }

  factory ScriptScheduleEntry.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final shellNames = (json['localShellTypes'] as List? ?? const <dynamic>[])
        .map((item) => item?.toString() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final shells = shellNames
        .map((name) {
          for (final type in LocalShellType.values) {
            if (type.name == name) {
              return type;
            }
          }
          return null;
        })
        .whereType<LocalShellType>()
        .toList(growable: false);
    final policyRaw = json['failurePolicy']?.toString() ?? '';
    final failurePolicy = switch (policyRaw) {
      'stopOnFailure' => ScriptFailurePolicy.stopOnFailure,
      'retryHost' => ScriptFailurePolicy.retryHost,
      _ => ScriptFailurePolicy.continueOnFailure,
    };
    final retryRaw = json['retryPerHost'];
    final retry = retryRaw is int
        ? retryRaw
        : int.tryParse('${retryRaw ?? 1}') ?? 1;
    final timezoneRaw = json['timezoneOffsetMinutes'];
    final timezoneOffsetMinutes = timezoneRaw is int
        ? timezoneRaw
        : int.tryParse(
                '${timezoneRaw ?? DateTime.now().timeZoneOffset.inMinutes}',
              ) ??
              DateTime.now().timeZoneOffset.inMinutes;
    return ScriptScheduleEntry(
      id:
          json['id']?.toString() ??
          'script-schedule-${DateTime.now().microsecondsSinceEpoch}',
      scriptId: json['scriptId']?.toString() ?? '',
      cronExpression: json['cronExpression']?.toString() ?? '* * * * *',
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      hostIds: (json['hostIds'] as List? ?? const <dynamic>[])
          .map((item) => item?.toString() ?? '')
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      localShellTypes: shells,
      failurePolicy: failurePolicy,
      retryPerHost: retry.clamp(1, 6),
      silentExecution: json['silentExecution'] is bool
          ? json['silentExecution'] as bool
          : true,
      timezoneOffsetMinutes: timezoneOffsetMinutes.clamp(-12 * 60, 14 * 60),
      missedRunPolicy: _parseMissedRunPolicy(
        json['missedRunPolicy']?.toString() ?? '',
      ),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? now,
      lastTriggeredAt: DateTime.tryParse(
        json['lastTriggeredAt']?.toString() ?? '',
      ),
      lastEvaluatedAt:
          DateTime.tryParse(json['lastEvaluatedAt']?.toString() ?? '') ?? now,
    );
  }
}

class ScriptHostRunRecord {
  const ScriptHostRunRecord({
    required this.id,
    required this.runId,
    required this.scriptId,
    required this.scriptName,
    required this.hostId,
    required this.hostName,
    required this.success,
    required this.detail,
    required this.finishedAt,
  });

  final String id;
  final String runId;
  final String scriptId;
  final String scriptName;
  final String hostId;
  final String hostName;
  final bool success;
  final String detail;
  final DateTime finishedAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'runId': runId,
      'scriptId': scriptId,
      'scriptName': scriptName,
      'hostId': hostId,
      'hostName': hostName,
      'success': success,
      'detail': detail,
      'finishedAt': finishedAt.toIso8601String(),
    };
  }

  factory ScriptHostRunRecord.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return ScriptHostRunRecord(
      id: json['id']?.toString() ?? 'script-run-${now.microsecondsSinceEpoch}',
      runId: json['runId']?.toString() ?? '',
      scriptId: json['scriptId']?.toString() ?? '',
      scriptName: json['scriptName']?.toString() ?? '',
      hostId: json['hostId']?.toString() ?? '',
      hostName: json['hostName']?.toString() ?? '',
      success: json['success'] is bool ? json['success'] as bool : false,
      detail: json['detail']?.toString() ?? '',
      finishedAt:
          DateTime.tryParse(json['finishedAt']?.toString() ?? '') ?? now,
    );
  }
}
