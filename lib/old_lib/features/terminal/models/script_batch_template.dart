import 'host_entry.dart';
import 'script_entry.dart';

class ScriptBatchTemplate {
  const ScriptBatchTemplate({
    required this.id,
    required this.scriptId,
    required this.name,
    required this.hostIds,
    required this.localShellTypes,
    required this.silentExecution,
    required this.failurePolicy,
    required this.retryPerHost,
    required this.maxConcurrency,
    required this.templateArgs,
    required this.environmentOverrides,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String scriptId;
  final String name;
  final List<String> hostIds;
  final List<LocalShellType> localShellTypes;
  final bool silentExecution;
  final ScriptFailurePolicy failurePolicy;
  final int retryPerHost;
  final int maxConcurrency;
  final Map<String, String> templateArgs;
  final Map<String, String> environmentOverrides;
  final DateTime createdAt;
  final DateTime updatedAt;

  ScriptBatchTemplate copyWith({
    String? id,
    String? scriptId,
    String? name,
    List<String>? hostIds,
    List<LocalShellType>? localShellTypes,
    bool? silentExecution,
    ScriptFailurePolicy? failurePolicy,
    int? retryPerHost,
    int? maxConcurrency,
    Map<String, String>? templateArgs,
    Map<String, String>? environmentOverrides,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ScriptBatchTemplate(
      id: id ?? this.id,
      scriptId: scriptId ?? this.scriptId,
      name: name ?? this.name,
      hostIds: hostIds ?? this.hostIds,
      localShellTypes: localShellTypes ?? this.localShellTypes,
      silentExecution: silentExecution ?? this.silentExecution,
      failurePolicy: failurePolicy ?? this.failurePolicy,
      retryPerHost: retryPerHost ?? this.retryPerHost,
      maxConcurrency: maxConcurrency ?? this.maxConcurrency,
      templateArgs: templateArgs ?? this.templateArgs,
      environmentOverrides: environmentOverrides ?? this.environmentOverrides,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'scriptId': scriptId,
      'name': name,
      'hostIds': hostIds,
      'localShellTypes': localShellTypes
          .map((shell) => shell.name)
          .toList(growable: false),
      'silentExecution': silentExecution,
      'failurePolicy': failurePolicy.name,
      'retryPerHost': retryPerHost,
      'maxConcurrency': maxConcurrency,
      'templateArgs': templateArgs,
      'environmentOverrides': environmentOverrides,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ScriptBatchTemplate.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final shellNames = ((json['localShellTypes'] as List?) ?? const <dynamic>[])
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final localShellTypes = shellNames
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
    final failureRaw = json['failurePolicy']?.toString() ?? '';
    final failurePolicy = switch (failureRaw) {
      'stopOnFailure' => ScriptFailurePolicy.stopOnFailure,
      'retryHost' => ScriptFailurePolicy.retryHost,
      _ => ScriptFailurePolicy.continueOnFailure,
    };
    return ScriptBatchTemplate(
      id: (json['id']?.toString() ?? '').trim(),
      scriptId: (json['scriptId']?.toString() ?? '').trim(),
      name: (json['name']?.toString() ?? '').trim(),
      hostIds: ((json['hostIds'] as List?) ?? const <dynamic>[])
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      localShellTypes: localShellTypes,
      silentExecution: json['silentExecution'] is bool
          ? json['silentExecution'] as bool
          : false,
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
      templateArgs: _normalizeStringMap(json['templateArgs']),
      environmentOverrides: _normalizeStringMap(json['environmentOverrides']),
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

Map<String, String> _normalizeStringMap(dynamic raw) {
  if (raw is! Map) {
    return const <String, String>{};
  }
  final result = <String, String>{};
  raw.forEach((key, value) {
    final normalizedKey = key?.toString().trim() ?? '';
    if (normalizedKey.isEmpty) {
      return;
    }
    result[normalizedKey] = value?.toString() ?? '';
  });
  return result;
}
