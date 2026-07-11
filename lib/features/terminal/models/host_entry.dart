enum AuthType { password, key }

enum ConnectionType { ssh, local, serial, telnet }

enum SshProxyType { none, socks5, jump }

class JumpHostEntry {
  const JumpHostEntry({
    required this.host,
    this.port = 22,
    this.username,
  });

  final String host;
  final int port;
  final String? username;

  JumpHostEntry copyWith({String? host, int? port, String? username}) {
    return JumpHostEntry(
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
    );
  }

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        if (username != null && username!.isNotEmpty) 'username': username,
      };

  factory JumpHostEntry.fromJson(Map<String, dynamic> json) => JumpHostEntry(
        host: (json['host']?.toString() ?? '').trim(),
        port: (json['port'] is int ? json['port'] as int : int.tryParse('${json['port'] ?? 22}') ?? 22).clamp(1, 65535),
        username: (json['username']?.toString() ?? '').trim().isEmpty
            ? null
            : json['username']!.toString().trim(),
      );

  @override
  bool operator ==(Object other) =>
      other is JumpHostEntry && host == other.host && port == other.port && username == other.username;

  @override
  int get hashCode => Object.hash(host, port, username);
}

enum LocalShellType {
  systemDefault,
  powershell,
  powershellAdmin,
  commandPrompt,
  wsl,
  bash,
}

enum SerialParity { none, odd, even }

const defaultHostGroup = '';

class HostEntry {
  const HostEntry({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.group,
    required this.authType,
    this.connectionType = ConnectionType.ssh,
    this.sshProxyType = SshProxyType.none,
    this.socksProxyHost,
    this.socksProxyPort = 1080,
    this.socksProxyUsername,
    this.socksProxyPassword,
    this.jumpHosts = const <JumpHostEntry>[],
    this.useSshAgent = false,
    this.sshAgentSocketPath,
    this.privateKeyPassphrase,
    this.keepAliveSeconds = 10,
    this.connectTimeoutSeconds = 12,
    this.localShellType = LocalShellType.systemDefault,
    this.serialPortPath,
    this.serialBaudRate = 9600,
    this.serialDataBits = 8,
    this.serialStopBits = 1,
    this.serialParity = SerialParity.none,
    this.password,
    this.privateKeyPath,
    this.lastConnected,
    this.telnetPort = 23,
    this.fontFamily,
    this.fontSize,
    this.lineHeight,
    this.maxScrollbackLines,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String group;
  final AuthType authType;
  final ConnectionType connectionType;
  final SshProxyType sshProxyType;
  final String? socksProxyHost;
  final int socksProxyPort;
  final String? socksProxyUsername;
  final String? socksProxyPassword;
  final List<JumpHostEntry> jumpHosts;
  final bool useSshAgent;
  final String? sshAgentSocketPath;
  final String? privateKeyPassphrase;
  final int keepAliveSeconds;
  final int connectTimeoutSeconds;
  final LocalShellType localShellType;
  final String? serialPortPath;
  final int serialBaudRate;
  final int serialDataBits;
  final int serialStopBits;
  final SerialParity serialParity;
  final String? password;
  final String? privateKeyPath;
  final DateTime? lastConnected;
  final int telnetPort;
  final String? fontFamily;
  final double? fontSize;
  final double? lineHeight;
  final int? maxScrollbackLines;

  bool get isLocal => connectionType == ConnectionType.local;
  bool get isSsh => connectionType == ConnectionType.ssh;
  bool get isSerial => connectionType == ConnectionType.serial;
  bool get isTelnet => connectionType == ConnectionType.telnet;

  Map<String, dynamic> toJson({bool includeSecrets = false}) {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'username': username,
      'group': group,
      'authType': authType.name,
      'connectionType': connectionType.name,
      'sshProxyType': sshProxyType.name,
      'socksProxyHost': socksProxyHost,
      'socksProxyPort': socksProxyPort,
      'socksProxyUsername': socksProxyUsername,
      'jumpHosts': jumpHosts.map((j) => j.toJson()).toList(growable: false),
      'useSshAgent': useSshAgent,
      'sshAgentSocketPath': sshAgentSocketPath,
      'keepAliveSeconds': keepAliveSeconds,
      'connectTimeoutSeconds': connectTimeoutSeconds,
      'localShellType': localShellType.name,
      'serialPortPath': serialPortPath,
      'serialBaudRate': serialBaudRate,
      'serialDataBits': serialDataBits,
      'serialStopBits': serialStopBits,
      'serialParity': serialParity.name,
      'privateKeyPath': privateKeyPath,
      if (includeSecrets) 'password': password,
      if (includeSecrets) 'privateKeyPassphrase': privateKeyPassphrase,
      if (includeSecrets) 'socksProxyPassword': socksProxyPassword,
      'lastConnected': lastConnected?.toIso8601String(),
      'telnetPort': telnetPort,
      'fontFamily': fontFamily,
      'fontSize': fontSize,
      'lineHeight': lineHeight,
      'maxScrollbackLines': maxScrollbackLines,
    };
  }

  factory HostEntry.fromJson(Map<String, dynamic> json) {
    final authRaw = json['authType'];
    final auth = authRaw == 'key' ? AuthType.key : AuthType.password;
    final connectionRaw = json['connectionType']?.toString();
    final connectionType = switch (connectionRaw) {
      'local' => ConnectionType.local,
      'serial' => ConnectionType.serial,
      'telnet' => ConnectionType.telnet,
      _ => ConnectionType.ssh,
    };
    final proxyRaw = json['sshProxyType']?.toString();
    final sshProxyType = switch (proxyRaw) {
      'socks5' => SshProxyType.socks5,
      'jump' => SshProxyType.jump,
      _ => SshProxyType.none,
    };
    final shellRaw = json['localShellType']?.toString();
    final localShellType = LocalShellType.values
        .where((shell) {
          return shell.name == shellRaw;
        })
        .fold<LocalShellType>(
          LocalShellType.systemDefault,
          (_, shell) => shell,
        );
    final portValue = json['port'];
    final parsedPort = portValue is int
        ? portValue
        : int.tryParse('${portValue ?? 22}') ?? 22;
    final proxyPortValue = json['socksProxyPort'];
    final parsedProxyPort = proxyPortValue is int
        ? proxyPortValue
        : int.tryParse('${proxyPortValue ?? 1080}') ?? 1080;
    final keepAliveValue = json['keepAliveSeconds'];
    final keepAliveSeconds = keepAliveValue is int
        ? keepAliveValue
        : int.tryParse('${keepAliveValue ?? 10}') ?? 10;
    final connectTimeoutValue = json['connectTimeoutSeconds'];
    final connectTimeoutSeconds = connectTimeoutValue is int
        ? connectTimeoutValue
        : int.tryParse('${connectTimeoutValue ?? 12}') ?? 12;
    final serialBaudRateValue = json['serialBaudRate'];
    final serialBaudRate = serialBaudRateValue is int
        ? serialBaudRateValue
        : int.tryParse('${serialBaudRateValue ?? 9600}') ?? 9600;
    final serialDataBitsValue = json['serialDataBits'];
    final serialDataBits = serialDataBitsValue is int
        ? serialDataBitsValue
        : int.tryParse('${serialDataBitsValue ?? 8}') ?? 8;
    final serialStopBitsValue = json['serialStopBits'];
    final serialStopBits = serialStopBitsValue is int
        ? serialStopBitsValue
        : int.tryParse('${serialStopBitsValue ?? 1}') ?? 1;
    final serialParityRaw = json['serialParity']?.toString();
    final serialParity = switch (serialParityRaw) {
      'odd' => SerialParity.odd,
      'even' => SerialParity.even,
      _ => SerialParity.none,
    };
    final last = json['lastConnected'];
    return HostEntry(
      id:
          json['id']?.toString() ??
          'host-${DateTime.now().microsecondsSinceEpoch}',
      name: json['name']?.toString() ?? '',
      host: json['host']?.toString() ?? '',
      port: parsedPort,
      username: json['username']?.toString() ?? '',
      group: json['group']?.toString() ?? defaultHostGroup,
      authType: auth,
      connectionType: connectionType,
      sshProxyType: sshProxyType,
      socksProxyHost: json['socksProxyHost']?.toString(),
      socksProxyPort: parsedProxyPort.clamp(1, 65535).toInt(),
      socksProxyUsername: json['socksProxyUsername']?.toString(),
      socksProxyPassword: json['socksProxyPassword']?.toString(),
      jumpHosts: _parseJumpHosts(json),
      useSshAgent: json['useSshAgent'] is bool
          ? json['useSshAgent'] as bool
          : false,
      sshAgentSocketPath: json['sshAgentSocketPath']?.toString(),
      privateKeyPassphrase: json['privateKeyPassphrase']?.toString(),
      keepAliveSeconds: keepAliveSeconds.clamp(0, 600).toInt(),
      connectTimeoutSeconds: connectTimeoutSeconds.clamp(3, 120).toInt(),
      localShellType: localShellType,
      serialPortPath: json['serialPortPath']?.toString(),
      serialBaudRate: serialBaudRate.clamp(1200, 4000000).toInt(),
      serialDataBits: serialDataBits.clamp(5, 8).toInt(),
      serialStopBits: serialStopBits == 2 ? 2 : 1,
      serialParity: serialParity,
      password: json['password']?.toString(),
      privateKeyPath: json['privateKeyPath']?.toString(),
      lastConnected: last is String
          ? DateTime.tryParse(last)
          : (last is DateTime ? last : null),
      telnetPort: (json['telnetPort'] is int
              ? json['telnetPort'] as int
              : int.tryParse('${json['telnetPort'] ?? 23}') ?? 23)
          .clamp(1, 65535)
          .toInt(),
      fontFamily: json['fontFamily']?.toString(),
      fontSize: _parseNullableDouble(json['fontSize']),
      lineHeight: _parseNullableDouble(json['lineHeight']),
      maxScrollbackLines: json['maxScrollbackLines'] is int
          ? json['maxScrollbackLines'] as int
          : (json['maxScrollbackLines'] != null
              ? int.tryParse('${json['maxScrollbackLines']}')
              : null),
    );
  }

  static List<JumpHostEntry> _parseJumpHosts(Map<String, dynamic> json) {
    final raw = json['jumpHosts'];
    if (raw is List) {
      return raw
          .whereType<Map<String, dynamic>>()
          .map((item) => JumpHostEntry.fromJson(item))
          .toList(growable: false);
    }
    final legacy = json['jumpHost']?.toString().trim();
    if (legacy != null && legacy.isNotEmpty) {
      final parts = legacy.split(',');
      return parts
          .map((part) => _legacyJumpHost(part.trim()))
          .where((j) => j != null)
          .cast<JumpHostEntry>()
          .toList(growable: false);
    }
    return const <JumpHostEntry>[];
  }

  static JumpHostEntry? _legacyJumpHost(String raw) {
    if (raw.isEmpty) return null;
    var username = '';
    var hostPart = raw;
    final atIdx = raw.indexOf('@');
    if (atIdx > 0) {
      username = raw.substring(0, atIdx).trim();
      hostPart = raw.substring(atIdx + 1).trim();
    }
    if (hostPart.isEmpty) return null;
    var host = hostPart;
    var port = 22;
    if (hostPart.startsWith('[')) {
      final close = hostPart.indexOf(']');
      if (close > 1) {
        host = hostPart.substring(1, close);
        final remain = hostPart.substring(close + 1).trim();
        if (remain.startsWith(':')) {
          port = int.tryParse(remain.substring(1).trim()) ?? 22;
        }
      }
    } else {
      final lastColon = hostPart.lastIndexOf(':');
      final firstColon = hostPart.indexOf(':');
      if (firstColon > 0 && firstColon == lastColon) {
        host = hostPart.substring(0, firstColon).trim();
        port = int.tryParse(hostPart.substring(firstColon + 1).trim()) ?? 22;
      }
    }
    return JumpHostEntry(host: host, port: port.clamp(1, 65535), username: username.isNotEmpty ? username : null);
  }

  static double? _parseNullableDouble(dynamic v) {
    if (v == null) return null;
    final d = double.tryParse(v.toString());
    return d?.isFinite == true ? d : null;
  }

  HostEntry copyWith({
    String? name,
    String? host,
    int? port,
    String? username,
    String? group,
    AuthType? authType,
    ConnectionType? connectionType,
    SshProxyType? sshProxyType,
    String? socksProxyHost,
    int? socksProxyPort,
    String? socksProxyUsername,
    String? socksProxyPassword,
    List<JumpHostEntry>? jumpHosts,
    bool? useSshAgent,
    String? sshAgentSocketPath,
    String? privateKeyPassphrase,
    int? keepAliveSeconds,
    int? connectTimeoutSeconds,
    LocalShellType? localShellType,
    String? serialPortPath,
    int? serialBaudRate,
    int? serialDataBits,
    int? serialStopBits,
    SerialParity? serialParity,
    String? password,
    String? privateKeyPath,
    DateTime? lastConnected,
    int? telnetPort,
    String? fontFamily,
    double? fontSize,
    double? lineHeight,
    int? maxScrollbackLines,
  }) {
    return HostEntry(
      id: id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      group: group ?? this.group,
      authType: authType ?? this.authType,
      connectionType: connectionType ?? this.connectionType,
      sshProxyType: sshProxyType ?? this.sshProxyType,
      socksProxyHost: socksProxyHost ?? this.socksProxyHost,
      socksProxyPort: socksProxyPort ?? this.socksProxyPort,
      socksProxyUsername: socksProxyUsername ?? this.socksProxyUsername,
      socksProxyPassword: socksProxyPassword ?? this.socksProxyPassword,
      jumpHosts: jumpHosts ?? this.jumpHosts,
      useSshAgent: useSshAgent ?? this.useSshAgent,
      sshAgentSocketPath: sshAgentSocketPath ?? this.sshAgentSocketPath,
      privateKeyPassphrase: privateKeyPassphrase ?? this.privateKeyPassphrase,
      keepAliveSeconds: keepAliveSeconds ?? this.keepAliveSeconds,
      connectTimeoutSeconds:
          connectTimeoutSeconds ?? this.connectTimeoutSeconds,
      localShellType: localShellType ?? this.localShellType,
      serialPortPath: serialPortPath ?? this.serialPortPath,
      serialBaudRate: serialBaudRate ?? this.serialBaudRate,
      serialDataBits: serialDataBits ?? this.serialDataBits,
      serialStopBits: serialStopBits ?? this.serialStopBits,
      serialParity: serialParity ?? this.serialParity,
      password: password ?? this.password,
      privateKeyPath: privateKeyPath ?? this.privateKeyPath,
      lastConnected: lastConnected ?? this.lastConnected,
      telnetPort: telnetPort ?? this.telnetPort,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      maxScrollbackLines: maxScrollbackLines ?? this.maxScrollbackLines,
    );
  }
}

