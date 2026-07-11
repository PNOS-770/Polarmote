import 'workflow_node.dart';

class ScriptWorkflowEntry {
  const ScriptWorkflowEntry({
    required this.id,
    required this.name,
    required this.nodes,
    required this.createdAt,
    required this.updatedAt,
    this.folderId = '',
    this.stopOnFailure = true,
  });

  final String id;
  final String name;
  final String folderId;
  final List<WorkflowNode> nodes;
  final bool stopOnFailure;
  final DateTime createdAt;
  final DateTime updatedAt;

  List<String> get scriptIds => nodes.map((n) => n.scriptId).toList(growable: false);

  ScriptWorkflowEntry copyWith({
    String? id,
    String? name,
    String? folderId,
    List<WorkflowNode>? nodes,
    bool? stopOnFailure,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ScriptWorkflowEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      folderId: folderId ?? this.folderId,
      nodes: nodes ?? this.nodes,
      stopOnFailure: stopOnFailure ?? this.stopOnFailure,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (folderId.trim().isNotEmpty) 'folderId': folderId.trim(),
      'nodes': nodes.map((n) => n.toJson()).toList(growable: false),
      'stopOnFailure': stopOnFailure,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ScriptWorkflowEntry.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final List<WorkflowNode> parsedNodes;
    if (json['nodes'] is List) {
      parsedNodes = (json['nodes'] as List)
          .map((item) => WorkflowNode.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
    } else if (json['scriptIds'] is List) {
      parsedNodes = (json['scriptIds'] as List)
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .map((scriptId) => WorkflowNode(
                id: scriptId,
                scriptId: scriptId,
              ))
          .toList(growable: false);
    } else {
      parsedNodes = const <WorkflowNode>[];
    }
    return ScriptWorkflowEntry(
      id: (json['id']?.toString() ?? '').trim(),
      name: (json['name']?.toString() ?? '').trim(),
      folderId: (json['folderId']?.toString() ?? '').trim(),
      nodes: parsedNodes,
      stopOnFailure: json['stopOnFailure'] is bool
          ? json['stopOnFailure'] as bool
          : true,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? now,
    );
  }
}

