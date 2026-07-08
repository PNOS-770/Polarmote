class FileNode {
  const FileNode({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size,
    this.modified,
    this.ownerId,
    this.groupId,
    this.permissions,
    this.children = const [],
  });

  final String name;
  final String path;
  final bool isDirectory;
  final int? size;
  final DateTime? modified;
  final int? ownerId;
  final int? groupId;
  final int? permissions;
  final List<FileNode> children;

  factory FileNode.dir(
    String name,
    String path,
    List<FileNode> children, {
    int? size,
    DateTime? modified,
    int? ownerId,
    int? groupId,
    int? permissions,
  }) {
    return FileNode(
      name: name,
      path: path,
      isDirectory: true,
      size: size,
      modified: modified,
      ownerId: ownerId,
      groupId: groupId,
      permissions: permissions,
      children: children,
    );
  }

  factory FileNode.file(
    String name,
    String path, {
    int? size,
    DateTime? modified,
    int? ownerId,
    int? groupId,
    int? permissions,
  }) {
    return FileNode(
      name: name,
      path: path,
      isDirectory: false,
      size: size,
      modified: modified,
      ownerId: ownerId,
      groupId: groupId,
      permissions: permissions,
    );
  }
}

