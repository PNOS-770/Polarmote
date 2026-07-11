class ScriptFolderEntry {
  const ScriptFolderEntry({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.parentId = '',
  });

  final String id;
  final String name;
  final String parentId;
  final DateTime createdAt;
  final DateTime updatedAt;

  ScriptFolderEntry copyWith({
    String? id,
    String? name,
    String? parentId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ScriptFolderEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: parentId ?? this.parentId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (parentId.trim().isNotEmpty) 'parentId': parentId.trim(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ScriptFolderEntry.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return ScriptFolderEntry(
      id: (json['id']?.toString() ?? '').trim(),
      name: (json['name']?.toString() ?? '').trim(),
      parentId: (json['parentId']?.toString() ?? '').trim(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? now,
    );
  }
}

