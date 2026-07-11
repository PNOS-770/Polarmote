part of 'terminal_app_state.dart';

enum NavSection { sessions, sftp, transfers, scripts, settings }

enum SessionSortMode { smart, name, recent }


enum HomeLayoutMode { mobile, desktop }

enum TerminalCursorShape { block, verticalBar, underline }

class TerminalAppearanceProfile {
  const TerminalAppearanceProfile({
    this.fontFamily = 'monospace',
    this.fontSize = 14.0,
    this.lineHeight = 1.25,
    this.cursorShape = TerminalCursorShape.block,
  });

  final String fontFamily;
  final double fontSize;
  final double lineHeight;
  final TerminalCursorShape cursorShape;

  Map<String, dynamic> toJson() => {
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'cursorShape': cursorShape.name,
  };

  factory TerminalAppearanceProfile.fromJson(Map<String, dynamic> json) {
    return TerminalAppearanceProfile(
      fontFamily: json['fontFamily']?.toString() ?? 'monospace',
      fontSize: _parseDouble(json['fontSize'], 13.0),
      lineHeight: _parseDouble(json['lineHeight'], 1.25),
      cursorShape: TerminalCursorShape.values.firstWhere(
        (e) => e.name == json['cursorShape']?.toString(),
        orElse: () => TerminalCursorShape.block,
      ),
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
  });

  final String id;
  final String sessionId;

  TerminalSplitPaneConfig copyWith({String? sessionId}) {
    return TerminalSplitPaneConfig(
      id: id,
      sessionId: sessionId ?? this.sessionId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sessionId': sessionId,
  };

  factory TerminalSplitPaneConfig.fromJson(Map<String, dynamic> json) {
    return TerminalSplitPaneConfig(
      id: json['id']?.toString() ?? '',
      sessionId: json['sessionId']?.toString() ?? '',
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


enum MemoryMode { 
  low,      // 2000 lines - ~0.4MB per terminal
  medium,   // 5000 lines - ~1MB per terminal
  high,     // 10000 lines - ~2MB per terminal
  custom,   // User-defined
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
    ShortcutBinding(id: 'newSession', name: 'New session', defaultKeys: 'Ctrl+N'),
    ShortcutBinding(id: 'quickConnect', name: 'Quick connect', defaultKeys: 'Ctrl+K'),
    ShortcutBinding(id: 'closeSession', name: 'Close current workspace', defaultKeys: 'Ctrl+W'),
    ShortcutBinding(id: 'closeAllSessions', name: 'Close all sessions', defaultKeys: 'Ctrl+Shift+W'),
    ShortcutBinding(id: 'newScript', name: 'New script', defaultKeys: 'Ctrl+Shift+N'),
    ShortcutBinding(id: 'runScript', name: 'Run script', defaultKeys: 'Ctrl+Shift+R'),
    ShortcutBinding(id: 'scriptList', name: 'Script list', defaultKeys: 'Ctrl+Shift+L'),
    ShortcutBinding(id: 'scriptMonitor', name: 'Script monitor', defaultKeys: 'Ctrl+Shift+M'),
    ShortcutBinding(id: 'sftpBrowser', name: 'SFTP browser', defaultKeys: 'Ctrl+Shift+F'),
    ShortcutBinding(id: 'transferManager', name: 'Transfer manager', defaultKeys: 'Ctrl+Shift+T'),
    ShortcutBinding(id: 'portForwarding', name: 'Port forwarding', defaultKeys: 'Ctrl+Shift+P'),
    ShortcutBinding(id: 'lanScan', name: 'LAN scan', defaultKeys: 'Ctrl+Shift+A'),
    ShortcutBinding(id: 'openSettings', name: 'Settings', defaultKeys: 'Ctrl+,')
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

class TerminalStage {
  const TerminalStage({
    required this.id,
    required this.name,
    required this.sessionIds,
    this.createdAt,
    this.backgroundImageId = '',
    this.connectedHostIds = const [],
    this.fileTreeHeight = 220,
  });

  final String id;
  final String name;
  final List<String> sessionIds;
  final DateTime? createdAt;
  final String backgroundImageId;
  final List<String> connectedHostIds;
  final double fileTreeHeight;

  TerminalStage copyWith({
    String? id,
    String? name,
    List<String>? sessionIds,
    String? backgroundImageId,
    List<String>? connectedHostIds,
    double? fileTreeHeight,
  }) {
    return TerminalStage(
      id: id ?? this.id,
      name: name ?? this.name,
      sessionIds: sessionIds ?? this.sessionIds,
      createdAt: createdAt,
      backgroundImageId: backgroundImageId ?? this.backgroundImageId,
      connectedHostIds: connectedHostIds ?? this.connectedHostIds,
      fileTreeHeight: fileTreeHeight ?? this.fileTreeHeight,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sessionIds': sessionIds,
    'createdAt': createdAt?.toIso8601String(),
    'backgroundImageId': backgroundImageId,
    'connectedHostIds': connectedHostIds,
    'fileTreeHeight': fileTreeHeight,
  };

  factory TerminalStage.fromJson(Map<String, dynamic> json) {
    final createdStr = json['createdAt']?.toString() ?? '';
    final rawIds = json['sessionIds'];
    List<String> ids;
    if (rawIds is List) {
      ids = rawIds.whereType<String>().toList(growable: false);
    } else {
      ids = const <String>[];
    }
    // 向后兼容：读取旧的 sessionId 字段
    if (ids.isEmpty) {
      final legacyId = json['sessionId']?.toString() ?? '';
      if (legacyId.isNotEmpty) ids = [legacyId];
    }
    final rawHostIds = json['connectedHostIds'];
    final hostIds = rawHostIds is List
        ? rawHostIds.whereType<String>().toList(growable: false)
        : const <String>[];
    return TerminalStage(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      sessionIds: ids,
      createdAt: createdStr.trim().isNotEmpty
          ? DateTime.tryParse(createdStr)
          : null,
      backgroundImageId: json['backgroundImageId']?.toString() ?? '',
      connectedHostIds: hostIds,
      fileTreeHeight: (json['fileTreeHeight'] as num?)?.toDouble() ?? 220,
    );
  }
}

