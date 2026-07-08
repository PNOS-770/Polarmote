enum WorkflowValidationType { exitCode, outputContains, outputRegex, always }

class WorkflowNode {
  const WorkflowNode({
    required this.id,
    required this.scriptId,
    this.label = '',
    this.validation = WorkflowValidationType.exitCode,
    this.validationPattern,
    this.stopOnFailure = true,
  });

  final String id;
  final String scriptId;
  final String label;
  final WorkflowValidationType validation;
  final String? validationPattern;
  final bool stopOnFailure;

  WorkflowNode copyWith({
    String? id,
    String? scriptId,
    String? label,
    WorkflowValidationType? validation,
    String? validationPattern,
    bool? stopOnFailure,
  }) {
    return WorkflowNode(
      id: id ?? this.id,
      scriptId: scriptId ?? this.scriptId,
      label: label ?? this.label,
      validation: validation ?? this.validation,
      validationPattern: validationPattern ?? this.validationPattern,
      stopOnFailure: stopOnFailure ?? this.stopOnFailure,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'scriptId': scriptId,
      if (label.trim().isNotEmpty) 'label': label.trim(),
      if (validation != WorkflowValidationType.exitCode)
        'validation': validation.name,
      if (validationPattern != null &&
          validationPattern!.trim().isNotEmpty)
        'validationPattern': validationPattern!.trim(),
      if (!stopOnFailure) 'stopOnFailure': false,
    };
  }

  factory WorkflowNode.fromJson(Map<String, dynamic> json) {
    return WorkflowNode(
      id: (json['id']?.toString() ?? '').trim(),
      scriptId: (json['scriptId']?.toString() ?? '').trim(),
      label: (json['label']?.toString() ?? '').trim(),
      validation: _parseValidation(json['validation']?.toString()),
      validationPattern: json['validationPattern']?.toString(),
      stopOnFailure: json['stopOnFailure'] is bool
          ? json['stopOnFailure'] as bool
          : true,
    );
  }

  static WorkflowValidationType _parseValidation(String? raw) {
    for (final v in WorkflowValidationType.values) {
      if (v.name == raw) return v;
    }
    return WorkflowValidationType.exitCode;
  }
}

