import 'host_entry.dart';

enum ScriptFailurePolicy { continueOnFailure, stopOnFailure, retryHost }

enum ScriptStepCondition { always, onSuccess, onFailure }

enum ScriptStepFailurePolicy { continueOnFailure, stopOnFailure }

class ScriptStepConfig {
  const ScriptStepConfig({
    this.condition = ScriptStepCondition.always,
    this.timeoutSeconds,
    this.captureOutput = false,
    this.failurePolicy = ScriptStepFailurePolicy.continueOnFailure,
    this.retryCount = 1,
  });

  final ScriptStepCondition condition;
  final int? timeoutSeconds;
  final bool captureOutput;
  final ScriptStepFailurePolicy failurePolicy;
  final int retryCount;

  static const defaultConfig = ScriptStepConfig();

  Map<String, dynamic> toJson() {
    return {
      if (condition != ScriptStepCondition.always) 'condition': condition.name,
      if (timeoutSeconds != null) 'timeoutSeconds': timeoutSeconds,
      if (captureOutput) 'captureOutput': true,
      if (failurePolicy != ScriptStepFailurePolicy.continueOnFailure)
        'failurePolicy': failurePolicy.name,
      if (retryCount > 1) 'retryCount': retryCount,
    };
  }

  factory ScriptStepConfig.fromJson(Map<String, dynamic> json) {
    return ScriptStepConfig(
      condition: _parseCondition(json['condition']?.toString()),
      timeoutSeconds: json['timeoutSeconds'] is int
          ? json['timeoutSeconds'] as int
          : null,
      captureOutput: json['captureOutput'] == true,
      failurePolicy: _parseStepFailurePolicy(json['failurePolicy']?.toString()),
      retryCount: _normalizeRetryCountJson(json['retryCount']),
    );
  }

  static ScriptStepCondition _parseCondition(String? raw) {
    for (final value in ScriptStepCondition.values) {
      if (value.name == raw) return value;
    }
    return ScriptStepCondition.always;
  }

  static ScriptStepFailurePolicy _parseStepFailurePolicy(String? raw) {
    for (final value in ScriptStepFailurePolicy.values) {
      if (value.name == raw) return value;
    }
    return ScriptStepFailurePolicy.continueOnFailure;
  }

  static int _normalizeRetryCountJson(dynamic value) {
    if (value is int) return value.clamp(1, 10);
    if (value is num) return value.toInt().clamp(1, 10);
    return 1;
  }
}

class ScriptEntry {
  const ScriptEntry({
    required this.id,
    required this.name,
    required this.commands,
    required this.createdAt,
    required this.updatedAt,
    this.folderId = '',
    this.lastRunConfig,
    this.variables = const <String, String>{},
    this.environment = const <String, String>{},
    this.precheckCommands = const <String>[],
    this.maxConcurrency = 1,
    this.stepConfigs = const <ScriptStepConfig?>[],
  });

  final String id;
  final String name;
  final String folderId;
  final List<String> commands;
  final DateTime createdAt;
  final DateTime updatedAt;
  final ScriptLastRunConfig? lastRunConfig;
  final Map<String, String> variables;
  final Map<String, String> environment;
  final List<String> precheckCommands;
  final int maxConcurrency;
  final List<ScriptStepConfig?> stepConfigs;

  ScriptEntry copyWith({
    String? id,
    String? name,
    String? folderId,
    List<String>? commands,
    DateTime? createdAt,
    DateTime? updatedAt,
    ScriptLastRunConfig? lastRunConfig,
    Map<String, String>? variables,
    Map<String, String>? environment,
    List<String>? precheckCommands,
    int? maxConcurrency,
    List<ScriptStepConfig?>? stepConfigs,
  }) {
    return ScriptEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      folderId: folderId ?? this.folderId,
      commands: commands ?? this.commands,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastRunConfig: lastRunConfig ?? this.lastRunConfig,
      variables: variables ?? this.variables,
      environment: environment ?? this.environment,
      precheckCommands: precheckCommands ?? this.precheckCommands,
      maxConcurrency: maxConcurrency ?? this.maxConcurrency,
      stepConfigs: stepConfigs ?? this.stepConfigs,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (folderId.trim().isNotEmpty) 'folderId': folderId.trim(),
      'commands': commands,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      if (variables.isNotEmpty) 'variables': variables,
      if (environment.isNotEmpty) 'environment': environment,
      if (precheckCommands.isNotEmpty) 'precheckCommands': precheckCommands,
      if (maxConcurrency > 1) 'maxConcurrency': maxConcurrency,
      if (stepConfigs.any((c) => c != null)) 'stepConfigs': stepConfigs
          .map((c) => c?.toJson())
          .toList(growable: false),
      if (lastRunConfig != null) 'lastRunConfig': lastRunConfig!.toJson(),
    };
  }

  factory ScriptEntry.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return ScriptEntry(
      id: (json['id']?.toString() ?? '').trim(),
      name: (json['name']?.toString() ?? '').trim(),
      folderId: (json['folderId']?.toString() ?? '').trim(),
      commands: ((json['commands'] as List?) ?? const [])
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? now,
      variables: _normalizeStringMap(json['variables']),
      environment: _normalizeStringMap(json['environment']),
      precheckCommands: ((json['precheckCommands'] as List?) ?? const [])
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      maxConcurrency: _normalizeConcurrency(json['maxConcurrency']),
      stepConfigs: _normalizeStepConfigs(json['stepConfigs']),
      lastRunConfig: ScriptLastRunConfig.fromDynamic(json['lastRunConfig']),
    );
  }
}

List<ScriptStepConfig?> _normalizeStepConfigs(dynamic raw) {
  if (raw is! List) return const <ScriptStepConfig?>[];
  return raw.map((item) {
    if (item is! Map) return null;
    return ScriptStepConfig.fromJson(item.cast<String, dynamic>());
  }).toList(growable: false);
}

class ScriptLastRunConfig {
  const ScriptLastRunConfig({
    required this.hostIds,
    required this.localShellTypes,
    required this.notifyEnabled,
    required this.silentExecution,
    required this.failurePolicy,
    required this.retryPerHost,
    required this.templateArgs,
    required this.environmentOverrides,
    required this.maxConcurrency,
  });

  final List<String> hostIds;
  final List<LocalShellType> localShellTypes;
  final bool notifyEnabled;
  final bool silentExecution;
  final ScriptFailurePolicy failurePolicy;
  final int retryPerHost;
  final Map<String, String> templateArgs;
  final Map<String, String> environmentOverrides;
  final int maxConcurrency;

  bool get stopOnFailure => failurePolicy == ScriptFailurePolicy.stopOnFailure;

  Map<String, dynamic> toJson() {
    return {
      'hostIds': hostIds,
      'localShellTypes': localShellTypes.map((it) => it.name).toList(),
      'notifyEnabled': notifyEnabled,
      'silentExecution': silentExecution,
      'failurePolicy': failurePolicy.name,
      'retryPerHost': retryPerHost,
      if (templateArgs.isNotEmpty) 'templateArgs': templateArgs,
      if (environmentOverrides.isNotEmpty)
        'environmentOverrides': environmentOverrides,
      if (maxConcurrency > 1) 'maxConcurrency': maxConcurrency,
    };
  }

  factory ScriptLastRunConfig.fromDynamic(dynamic raw) {
    if (raw is! Map) {
      return const ScriptLastRunConfig(
        hostIds: <String>[],
        localShellTypes: <LocalShellType>[],
        notifyEnabled: true,
        silentExecution: false,
        failurePolicy: ScriptFailurePolicy.continueOnFailure,
        retryPerHost: 1,
        templateArgs: <String, String>{},
        environmentOverrides: <String, String>{},
        maxConcurrency: 1,
      );
    }
    final map = <String, dynamic>{};
    raw.forEach((key, value) => map['$key'] = value);
    final hostIds = ((map['hostIds'] as List?) ?? const <dynamic>[])
        .map((item) => item?.toString() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final shellNames = ((map['localShellTypes'] as List?) ?? const <dynamic>[])
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
    final policyRaw = map['failurePolicy']?.toString() ?? '';
    ScriptFailurePolicy failurePolicy;
    if (policyRaw == ScriptFailurePolicy.stopOnFailure.name ||
        (map['stopOnFailure'] is bool && map['stopOnFailure'] == true)) {
      failurePolicy = ScriptFailurePolicy.stopOnFailure;
    } else if (policyRaw == ScriptFailurePolicy.retryHost.name) {
      failurePolicy = ScriptFailurePolicy.retryHost;
    } else {
      failurePolicy = ScriptFailurePolicy.continueOnFailure;
    }
    final retryPerHost = _normalizeRetryCount(map['retryPerHost']);
    return ScriptLastRunConfig(
      hostIds: hostIds,
      localShellTypes: shells,
      notifyEnabled: map['notifyEnabled'] is bool
          ? map['notifyEnabled'] as bool
          : true,
      silentExecution: map['silentExecution'] is bool
          ? map['silentExecution'] as bool
          : false,
      failurePolicy: failurePolicy,
      retryPerHost: retryPerHost,
      templateArgs: _normalizeStringMap(map['templateArgs']),
      environmentOverrides: _normalizeStringMap(map['environmentOverrides']),
      maxConcurrency: _normalizeConcurrency(map['maxConcurrency']),
    );
  }
}

Map<String, String> _normalizeStringMap(dynamic raw) {
  if (raw is! Map) {
    return const <String, String>{};
  }
  final result = <String, String>{};
  raw.forEach((key, value) {
    final normalizedKey = key?.toString().trim() ?? '';
    if (normalizedKey.isEmpty) return;
    final normalizedValue = value?.toString() ?? '';
    result[normalizedKey] = normalizedValue;
  });
  return result;
}

int _normalizeConcurrency(dynamic value) {
  if (value is int) {
    return value.clamp(1, 8);
  }
  if (value is num) {
    return value.toInt().clamp(1, 8);
  }
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null) {
      return parsed.clamp(1, 8);
    }
  }
  return 1;
}

int _normalizeRetryCount(dynamic value) {
  if (value is int) {
    return value.clamp(1, 6);
  }
  if (value is num) {
    return value.toInt().clamp(1, 6);
  }
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null) {
      return parsed.clamp(1, 6);
    }
  }
  return 1;
}
