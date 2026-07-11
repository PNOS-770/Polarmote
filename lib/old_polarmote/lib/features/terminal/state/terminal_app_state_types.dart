part of 'terminal_app_state.dart';

enum NavSection { sessions, sftp, transfers, scripts, settings }

enum SessionSortMode { smart, name, recent }

enum TerminalSplitLayout { horizontal, vertical, grid }

enum TerminalSplitAxis { row, column }

enum HomeLayoutMode { mobile, desktop }

class TerminalAppearanceProfile {
  const TerminalAppearanceProfile({
    this.fontFamily = 'monospace',
    this.fontSize = 14.0,
    this.lineHeight = 1.25,
  });

  final String fontFamily;
  final double fontSize;
  final double lineHeight;

  Map<String, dynamic> toJson() => {
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'lineHeight': lineHeight,
  };

  factory TerminalAppearanceProfile.fromJson(Map<String, dynamic> json) {
    return TerminalAppearanceProfile(
      fontFamily: json['fontFamily']?.toString() ?? 'monospace',
      fontSize: _parseDouble(json['fontSize'], 14.0),
      lineHeight: _parseDouble(json['lineHeight'], 1.25),
    );
  }

  static double _parseDouble(dynamic v, double fallback) {
    if (v == null) return fallback;
    final d = double.tryParse(v.toString());
    if (d == null || !d.isFinite) return fallback;
    return d;
  }
}

class KeyBinding {
  const KeyBinding({
    required this.id,
    required this.name,
    required this.keys,
    required this.action,
  });

  final String id;
  final String name;
  final String keys;
  final String action;

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'keys': keys, 'action': action,
  };

  factory KeyBinding.fromJson(Map<String, dynamic> json) {
    return KeyBinding(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      keys: json['keys']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
    );
  }
}

class TerminalSplitPaneConfig {
  const TerminalSplitPaneConfig({
    required this.id,
    this.sessionId = '',
    this.backgroundImageId = '',
  });

  final String id;
  final String sessionId;
  final String backgroundImageId;

  TerminalSplitPaneConfig copyWith({String? sessionId, String? backgroundImageId}) {
    return TerminalSplitPaneConfig(
      id: id,
      sessionId: sessionId ?? this.sessionId,
      backgroundImageId: backgroundImageId ?? this.backgroundImageId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'backgroundImageId': backgroundImageId,
  };

  factory TerminalSplitPaneConfig.fromJson(Map<String, dynamic> json) {
    return TerminalSplitPaneConfig(
      id: json['id']?.toString() ?? '',
      sessionId: json['sessionId']?.toString() ?? '',
      backgroundImageId: json['backgroundImageId']?.toString() ?? '',
    );
  }
}

class BackgroundImageEntry {
  const BackgroundImageEntry({
    required this.id,
    required this.path,
    required this.name,
  });

  final String id;
  final String path;
  final String name;

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'name': name,
  };

  factory BackgroundImageEntry.fromJson(Map<String, dynamic> json) {
    return BackgroundImageEntry(
      id: json['id']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }
}

class TerminalSplitTreeNode {
  const TerminalSplitTreeNode.leaf({required this.id, required this.paneId})
    : axis = null,
      ratio = 0.5,
      first = null,
      second = null;

  const TerminalSplitTreeNode.split({
    required this.id,
    required this.axis,
    required this.ratio,
    required this.first,
    required this.second,
  }) : paneId = '';

  final String id;
  final String paneId;
  final TerminalSplitAxis? axis;
  final double ratio;
  final TerminalSplitTreeNode? first;
  final TerminalSplitTreeNode? second;

  bool get isLeaf => first == null && second == null;

  List<String> get paneIds {
    if (isLeaf) return paneId.isEmpty ? const <String>[] : [paneId];
    return [...?first?.paneIds, ...?second?.paneIds];
  }

  TerminalSplitTreeNode copyWith({
    String? paneId,
    TerminalSplitAxis? axis,
    double? ratio,
    TerminalSplitTreeNode? first,
    TerminalSplitTreeNode? second,
  }) {
    if (isLeaf) {
      return TerminalSplitTreeNode.leaf(id: id, paneId: paneId ?? this.paneId);
    }
    return TerminalSplitTreeNode.split(
      id: id,
      axis: axis ?? this.axis ?? TerminalSplitAxis.row,
      ratio: ratio ?? this.ratio,
      first: first ?? this.first!,
      second: second ?? this.second!,
    );
  }

  Map<String, dynamic> toJson() {
    if (isLeaf) {
      return {'id': id, 'type': 'leaf', 'paneId': paneId};
    }
    return {
      'id': id,
      'type': 'split',
      'axis': axis?.name ?? TerminalSplitAxis.row.name,
      'ratio': ratio,
      'first': first?.toJson(),
      'second': second?.toJson(),
    };
  }

  factory TerminalSplitTreeNode.fromJson(Map<String, dynamic> json) {
    final type = json['type']?.toString();
    final id = json['id']?.toString() ?? '';
    if (type == 'leaf') {
      return TerminalSplitTreeNode.leaf(
        id: id,
        paneId: json['paneId']?.toString() ?? '',
      );
    }
    final axisName = json['axis']?.toString();
    final axis = TerminalSplitAxis.values.firstWhere(
      (item) => item.name == axisName,
      orElse: () => TerminalSplitAxis.row,
    );
    TerminalSplitTreeNode? parseChild(dynamic value) {
      if (value is Map<String, dynamic>) {
        return TerminalSplitTreeNode.fromJson(value);
      }
      return null;
    }

    final first = parseChild(json['first']);
    final second = parseChild(json['second']);
    if (first == null || second == null) {
      return TerminalSplitTreeNode.leaf(id: id, paneId: '');
    }
    final ratio = double.tryParse('${json['ratio'] ?? ''}') ?? 0.5;
    return TerminalSplitTreeNode.split(
      id: id,
      axis: axis,
      ratio: ratio.clamp(0.15, 0.85).toDouble(),
      first: first,
      second: second,
    );
  }
}

class TerminalSplitTemplate {
  const TerminalSplitTemplate({
    required this.id,
    required this.name,
    required this.layout,
    required this.panes,
    this.tree,
    this.primaryRatio = 0.5,
    this.secondaryRatio = 0.5,
  });

  final String id;
  final String name;
  final TerminalSplitLayout layout;
  final List<TerminalSplitPaneConfig> panes;
  final TerminalSplitTreeNode? tree;
  final double primaryRatio;
  final double secondaryRatio;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'layout': layout.name,
    'panes': panes.map((pane) => pane.toJson()).toList(),
    'tree': tree?.toJson(),
    'primaryRatio': primaryRatio,
    'secondaryRatio': secondaryRatio,
  };

  factory TerminalSplitTemplate.fromJson(Map<String, dynamic> json) {
    final layoutName = json['layout']?.toString();
    final layout = TerminalSplitLayout.values.firstWhere(
      (item) => item.name == layoutName,
      orElse: () => TerminalSplitLayout.horizontal,
    );
    final panes = (json['panes'] as List? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(TerminalSplitPaneConfig.fromJson)
        .where((pane) => pane.id.trim().isNotEmpty)
        .toList(growable: false);
    final primary = double.tryParse('${json['primaryRatio'] ?? ''}') ?? 0.5;
    final secondary = double.tryParse('${json['secondaryRatio'] ?? ''}') ?? 0.5;
    final treeJson = json['tree'];
    return TerminalSplitTemplate(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      layout: layout,
      panes: panes,
      tree: treeJson is Map<String, dynamic>
          ? TerminalSplitTreeNode.fromJson(treeJson)
          : null,
      primaryRatio: primary.clamp(0.2, 0.8).toDouble(),
      secondaryRatio: secondary.clamp(0.2, 0.8).toDouble(),
    );
  }
}

class ViewerCacheCleanupResult {
  const ViewerCacheCleanupResult({
    required this.dirs,
    required this.deleted,
    required this.failed,
  });
  final List<String> dirs;
  final int deleted;
  final int failed;
}

class PortableStateSelection {
  const PortableStateSelection({
    this.settings = true,
    this.hosts = true,
    this.scripts = true,
    this.portForwards = true,
    this.commandHistory = true,
    this.knownHostFingerprints = true,
  });
  final bool settings;
  final bool hosts;
  final bool scripts;
  final bool portForwards;
  final bool commandHistory;
  final bool knownHostFingerprints;
  bool get includesAny =>
      settings ||
      hosts ||
      scripts ||
      portForwards ||
      commandHistory ||
      knownHostFingerprints;
}

class PortableStateSnapshot {
  PortableStateSnapshot({
    required this.id,
    required this.createdAt,
    required this.label,
    required this.path,
    this.description,
  });
  final String id;
  final DateTime createdAt;
  String label;
  final String path;
  String? description;

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'label': label,
    'path': path,
    if (description != null) 'description': description,
  };

  factory PortableStateSnapshot.fromJson(Map<String, dynamic> json) =>
      PortableStateSnapshot(
        id: json['id']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
        label: json['label']?.toString() ?? '',
        path: json['path']?.toString() ?? '',
        description: json['description']?.toString(),
      );
}

class VisitedFileEntry {
  const VisitedFileEntry({
    required this.hostId,
    required this.host,
    required this.port,
    required this.username,
    required this.connectionType,
    required this.isLocal,
    required this.filePath,
    required this.displayName,
    required this.lastVisitedAt,
    this.fileSize,
    this.fileModifiedAt,
  });
  final String hostId;
  final String host;
  final int port;
  final String username;
  final String connectionType;
  final bool isLocal;
  final String filePath;
  final String displayName;
  final DateTime lastVisitedAt;
  final int? fileSize;
  final DateTime? fileModifiedAt;
  String get dedupeKey {
    final hk = hostId.trim().isNotEmpty
        ? hostId.trim()
        : '$connectionType|$username@$host:$port';
    final pk = isLocal ? filePath.toLowerCase() : filePath;
    return '$hk|$pk';
  }

  Map<String, dynamic> toJson() => {
    'hostId': hostId,
    'host': host,
    'port': port,
    'username': username,
    'connectionType': connectionType,
    'isLocal': isLocal,
    'filePath': filePath,
    'displayName': displayName,
    'lastVisitedAt': lastVisitedAt.toIso8601String(),
    'fileSize': fileSize,
    'fileModifiedAt': fileModifiedAt?.toIso8601String(),
  };
  factory VisitedFileEntry.fromJson(Map<String, dynamic> json) {
    final va =
        DateTime.tryParse(json['lastVisitedAt']?.toString().trim() ?? '') ??
        DateTime.now();
    final p = json['port'] is int
        ? json['port'] as int
        : int.tryParse('${json['port'] ?? 22}') ?? 22;
    return VisitedFileEntry(
      hostId: json['hostId']?.toString() ?? '',
      host: json['host']?.toString() ?? '',
      port: p.clamp(0, 65535).toInt(),
      username: json['username']?.toString() ?? '',
      connectionType: json['connectionType']?.toString() ?? '',
      isLocal: json['isLocal'] is bool ? json['isLocal'] as bool : false,
      filePath: json['filePath']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      lastVisitedAt: va,
    );
  }
}

enum TerminalLogCategory {
  startup,
  session,
  transfer,
  externalEdit,
  system,
  ui,
  script,
}

enum TerminalLogLevel { info, warn, error, begin, end }

enum LogVerbosity { all, important, errorsOnly }

class _PendingLogLine {
  const _PendingLogLine({required this.line, required this.timestamp});
  final String line;
  final DateTime timestamp;
}

class HostKeyVerificationPrompt {
  const HostKeyVerificationPrompt({
    required this.id,
    required this.hostId,
    required this.hostDisplayName,
    required this.hostAddress,
    required this.keyType,
    required this.fingerprint,
    required this.existedFingerprint,
    required this.createdAt,
  });
  final String id;
  final String hostId;
  final String hostDisplayName;
  final String hostAddress;
  final String keyType;
  final String fingerprint;
  final String? existedFingerprint;
  final DateTime createdAt;
  bool get isChanged => (existedFingerprint ?? '').trim().isNotEmpty;
}

class StoredHostSecret {
  const StoredHostSecret({
    required this.password,
    required this.privateKeyPath,
    required this.privateKeyPassphrase,
    required this.socksProxyPassword,
  });
  final String? password;
  final String? privateKeyPath;
  final String? privateKeyPassphrase;
  final String? socksProxyPassword;
  Map<String, dynamic> toJson() => {
    'password': password,
    'privateKeyPath': privateKeyPath,
    'privateKeyPassphrase': privateKeyPassphrase,
    'socksProxyPassword': socksProxyPassword,
  };
  factory StoredHostSecret.fromJson(Map<String, dynamic> json) =>
      StoredHostSecret(
        password: _n(json['password']),
        privateKeyPath: _n(json['privateKeyPath']),
        privateKeyPassphrase: _n(json['privateKeyPassphrase']),
        socksProxyPassword: _n(json['socksProxyPassword']),
      );
  static String? _n(dynamic v) {
    final s = v?.toString().trim();
    return (s != null && s.isNotEmpty) ? s : null;
  }
}

class ShortcutBinding {
  const ShortcutBinding({
    required this.id,
    required this.name,
    required this.defaultKeys,
    this.customKeys,
  });

  final String id;
  final String name;
  final String defaultKeys;
  final String? customKeys;

  String get effectiveKeys => customKeys ?? defaultKeys;
  bool get isCustomized => customKeys != null;

  ShortcutBinding copyWith({String? customKeys}) {
    return ShortcutBinding(
      id: id,
      name: name,
      defaultKeys: defaultKeys,
      customKeys: customKeys,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'defaultKeys': defaultKeys,
    if (customKeys != null) 'customKeys': customKeys,
  };

  factory ShortcutBinding.fromJson(Map<String, dynamic> json) {
    return ShortcutBinding(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      defaultKeys: json['defaultKeys']?.toString() ?? '',
      customKeys: json['customKeys']?.toString(),
    );
  }
}

class ShortcutPreset {
  const ShortcutPreset({
    required this.id,
    required this.name,
    required this.bindings,
  });

  final String id;
  final String name;
  final List<ShortcutBinding> bindings;

  static List<ShortcutPreset> builtinPresets() {
    return [
      const ShortcutPreset(id: 'default', name: 'Asmote Default', bindings: _defaultBindings),
      ShortcutPreset(
        id: 'vscode',
        name: 'VS Code Style',
        bindings: _vscodeBindings(),
      ),
      ShortcutPreset(
        id: 'iterm2',
        name: 'iTerm2 Style',
        bindings: _iterm2Bindings(),
      ),
      ShortcutPreset(
        id: 'empty',
        name: 'No Bindings',
        bindings: _emptyBindings(),
      ),
    ];
  }

  static const List<ShortcutBinding> _defaultBindings = [
    ShortcutBinding(id: 'copy', name: 'Copy', defaultKeys: 'Ctrl+Shift+C / Ctrl+C'),
    ShortcutBinding(id: 'paste', name: 'Paste', defaultKeys: 'Ctrl+V / Shift+Insert'),
    ShortcutBinding(id: 'selectAll', name: 'Select All', defaultKeys: 'Ctrl+A'),
    ShortcutBinding(id: 'search', name: 'Find in terminal', defaultKeys: 'Ctrl+F'),
    ShortcutBinding(id: 'blockSelect', name: 'Toggle block selection', defaultKeys: 'Alt+B'),
    ShortcutBinding(id: 'splitMaximize', name: 'Maximize / Restore pane', defaultKeys: 'Ctrl+Alt+Enter'),
    ShortcutBinding(id: 'splitBroadcast', name: 'Toggle input broadcast', defaultKeys: 'Ctrl+Alt+B'),
    ShortcutBinding(id: 'splitPrev', name: 'Switch to previous pane', defaultKeys: 'Ctrl+Alt+Left / Ctrl+Alt+Up'),
    ShortcutBinding(id: 'splitNext', name: 'Switch to next pane', defaultKeys: 'Ctrl+Alt+Right / Ctrl+Alt+Down'),
  ];

  static List<ShortcutBinding> _vscodeBindings() {
    return _defaultBindings.map((b) {
      return switch (b.id) {
        'copy' => b.copyWith(customKeys: 'Ctrl+C'),
        'paste' => b.copyWith(customKeys: 'Ctrl+V'),
        'selectAll' => b.copyWith(customKeys: 'Ctrl+A'),
        'search' => b.copyWith(customKeys: 'Ctrl+F'),
        _ => b,
      };
    }).toList();
  }

  static List<ShortcutBinding> _iterm2Bindings() {
    return _defaultBindings.map((b) {
      return switch (b.id) {
        'copy' => b.copyWith(customKeys: 'Ctrl+Shift+C'),
        'paste' => b.copyWith(customKeys: 'Ctrl+Shift+V'),
        'search' => b.copyWith(customKeys: 'Cmd+F'),
        'splitMaximize' => b.copyWith(customKeys: 'Cmd+Enter'),
        'splitBroadcast' => b.copyWith(customKeys: 'Cmd+Shift+I'),
        'splitPrev' => b.copyWith(customKeys: 'Cmd+['),
        'splitNext' => b.copyWith(customKeys: 'Cmd+]'),
        _ => b,
      };
    }).toList();
  }

  static List<ShortcutBinding> _emptyBindings() {
    return _defaultBindings.map((b) => b.copyWith(customKeys: '')).toList();
  }
}

class _ShortcutOwner {
  const _ShortcutOwner(this.id, this.name, this.type);
  final String id;
  final String name;
  final String type;
}
