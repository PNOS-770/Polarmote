import 'script_entry.dart';

enum ScriptTriggerEventType { sessionConnected, commandSubmitted }

enum ScriptTriggerMatchType { contains, regex }

class ScriptTriggerEntry {
  const ScriptTriggerEntry({
    required this.id,
    required this.scriptId,
    required this.name,
    required this.enabled,
    required this.eventType,
    required this.matchType,
    required this.commandPattern,
    required this.hostIds,
    required this.executeAsMacro,
    required this.silentExecution,
    required this.failurePolicy,
    required this.retryPerHost,
    required this.maxConcurrency,
    required this.cooldownSeconds,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String scriptId;
  final String name;
  final bool enabled;
  final ScriptTriggerEventType eventType;
  final ScriptTriggerMatchType matchType;
  final String commandPattern;
  final List<String> hostIds;
  final bool executeAsMacro;
  final bool silentExecution;
  final ScriptFailurePolicy failurePolicy;
  final int retryPerHost;
  final int maxConcurrency;
  final int cooldownSeconds;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get needsCommandPattern =>
      eventType == ScriptTriggerEventType.commandSubmitted;

  ScriptTriggerEntry copyWith({
    String? id,
    String? scriptId,
    String? name,
    bool? enabled,
    ScriptTriggerEventType? eventType,
    ScriptTriggerMatchType? matchType,
    String? commandPattern,
    List<String>? hostIds,
    bool? executeAsMacro,
    bool? silentExecution,
    ScriptFailurePolicy? failurePolicy,
    int? retryPerHost,
    int? maxConcurrency,
    int? cooldownSeconds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ScriptTriggerEntry(
      id: id ?? this.id,
      scriptId: scriptId ?? this.scriptId,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      eventType: eventType ?? this.eventType,
      matchType: matchType ?? this.matchType,
      commandPattern: commandPattern ?? this.commandPattern,
      hostIds: hostIds ?? this.hostIds,
      executeAsMacro: executeAsMacro ?? this.executeAsMacro,
      silentExecution: silentExecution ?? this.silentExecution,
      failurePolicy: failurePolicy ?? this.failurePolicy,
      retryPerHost: retryPerHost ?? this.retryPerHost,
      maxConcurrency: maxConcurrency ?? this.maxConcurrency,
      cooldownSeconds: cooldownSeconds ?? this.cooldownSeconds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'scriptId': scriptId,
      'name': name,
      'enabled': enabled,
      'eventType': eventType.name,
      'matchType': matchType.name,
      'commandPattern': commandPattern,
      'hostIds': hostIds,
      'executeAsMacro': executeAsMacro,
      'silentExecution': silentExecution,
      'failurePolicy': failurePolicy.name,
      'retryPerHost': retryPerHost,
      'maxConcurrency': maxConcurrency,
      'cooldownSeconds': cooldownSeconds,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ScriptTriggerEntry.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final eventRaw = json['eventType']?.toString() ?? '';
    final eventType = eventRaw == ScriptTriggerEventType.commandSubmitted.name
        ? ScriptTriggerEventType.commandSubmitted
        : ScriptTriggerEventType.sessionConnected;
    final matchRaw = json['matchType']?.toString() ?? '';
    final matchType = matchRaw == ScriptTriggerMatchType.regex.name
        ? ScriptTriggerMatchType.regex
        : ScriptTriggerMatchType.contains;
    final policyRaw = json['failurePolicy']?.toString() ?? '';
    final failurePolicy = switch (policyRaw) {
      'stopOnFailure' => ScriptFailurePolicy.stopOnFailure,
      'retryHost' => ScriptFailurePolicy.retryHost,
      _ => ScriptFailurePolicy.continueOnFailure,
    };
    return ScriptTriggerEntry(
      id: (json['id']?.toString() ?? '').trim(),
      scriptId: (json['scriptId']?.toString() ?? '').trim(),
      name: (json['name']?.toString() ?? '').trim(),
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      eventType: eventType,
      matchType: matchType,
      commandPattern: (json['commandPattern']?.toString() ?? '').trim(),
      hostIds: ((json['hostIds'] as List?) ?? const <dynamic>[])
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      executeAsMacro: json['executeAsMacro'] is bool
          ? json['executeAsMacro'] as bool
          : false,
      silentExecution: json['silentExecution'] is bool
          ? json['silentExecution'] as bool
          : true,
      failurePolicy: failurePolicy,
      retryPerHost: _normalizeInt(
        json['retryPerHost'],
        fallback: 1,
        min: 1,
        max: 6,
      ),
      maxConcurrency: _normalizeInt(
        json['maxConcurrency'],
        fallback: 1,
        min: 1,
        max: 8,
      ),
      cooldownSeconds: _normalizeInt(
        json['cooldownSeconds'],
        fallback: 2,
        min: 0,
        max: 3600,
      ),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? now,
    );
  }
}

int _normalizeInt(
  dynamic value, {
  required int fallback,
  required int min,
  required int max,
}) {
  if (value is int) {
    return value.clamp(min, max);
  }
  if (value is num) {
    return value.toInt().clamp(min, max);
  }
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null) {
      return parsed.clamp(min, max);
    }
  }
  return fallback;
}
