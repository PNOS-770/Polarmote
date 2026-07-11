enum PortForwardType { local, reverse, socks }

PortForwardType _parsePortForwardType(String raw) {
  final value = raw.trim().toLowerCase();
  for (final type in PortForwardType.values) {
    if (type.name == value) {
      return type;
    }
  }
  return PortForwardType.local;
}

class PortForwardEntry {
  const PortForwardEntry({
    required this.id,
    required this.name,
    required this.hostId,
    required this.localHost,
    required this.localPort,
    required this.remoteHost,
    required this.remotePort,
    required this.createdAt,
    this.autoStart = false,
    this.type = PortForwardType.local,
  });

  final String id;
  final String name;
  final String hostId;
  final String localHost;
  final int localPort;
  final String remoteHost;
  final int remotePort;
  final DateTime createdAt;
  final bool autoStart;
  final PortForwardType type;

  PortForwardEntry copyWith({
    String? name,
    String? hostId,
    String? localHost,
    int? localPort,
    String? remoteHost,
    int? remotePort,
    DateTime? createdAt,
    bool? autoStart,
    PortForwardType? type,
  }) {
    return PortForwardEntry(
      id: id,
      name: name ?? this.name,
      hostId: hostId ?? this.hostId,
      localHost: localHost ?? this.localHost,
      localPort: localPort ?? this.localPort,
      remoteHost: remoteHost ?? this.remoteHost,
      remotePort: remotePort ?? this.remotePort,
      createdAt: createdAt ?? this.createdAt,
      autoStart: autoStart ?? this.autoStart,
      type: type ?? this.type,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'hostId': hostId,
      'localHost': localHost,
      'localPort': localPort,
      'remoteHost': remoteHost,
      'remotePort': remotePort,
      'createdAt': createdAt.toIso8601String(),
      'autoStart': autoStart,
      'type': type.name,
    };
  }

  factory PortForwardEntry.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final localPortRaw = json['localPort'];
    final remotePortRaw = json['remotePort'];
    final localPort = localPortRaw is int
        ? localPortRaw
        : int.tryParse('${localPortRaw ?? 0}') ?? 0;
    final remotePort = remotePortRaw is int
        ? remotePortRaw
        : int.tryParse('${remotePortRaw ?? 0}') ?? 0;
    return PortForwardEntry(
      id: (json['id']?.toString() ?? '').trim(),
      name: (json['name']?.toString() ?? '').trim(),
      hostId: (json['hostId']?.toString() ?? '').trim(),
      localHost: (json['localHost']?.toString() ?? '127.0.0.1').trim(),
      localPort: localPort,
      remoteHost: (json['remoteHost']?.toString() ?? '').trim(),
      remotePort: remotePort,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? now,
      autoStart: json['autoStart'] is bool ? json['autoStart'] as bool : false,
      type: _parsePortForwardType(json['type']?.toString() ?? ''),
    );
  }
}

class PortForwardTemplate {
  const PortForwardTemplate({
    required this.id,
    required this.name,
    required this.type,
    required this.localHost,
    required this.localPort,
    required this.remoteHost,
    required this.remotePort,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final PortForwardType type;
  final String localHost;
  final int localPort;
  final String remoteHost;
  final int remotePort;
  final DateTime createdAt;
  final DateTime updatedAt;

  PortForwardTemplate copyWith({
    String? name,
    PortForwardType? type,
    String? localHost,
    int? localPort,
    String? remoteHost,
    int? remotePort,
    DateTime? updatedAt,
  }) {
    return PortForwardTemplate(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      localHost: localHost ?? this.localHost,
      localPort: localPort ?? this.localPort,
      remoteHost: remoteHost ?? this.remoteHost,
      remotePort: remotePort ?? this.remotePort,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'localHost': localHost,
      'localPort': localPort,
      'remoteHost': remoteHost,
      'remotePort': remotePort,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory PortForwardTemplate.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final localPortRaw = json['localPort'];
    final remotePortRaw = json['remotePort'];
    final localPort = localPortRaw is int
        ? localPortRaw
        : int.tryParse('${localPortRaw ?? 0}') ?? 0;
    final remotePort = remotePortRaw is int
        ? remotePortRaw
        : int.tryParse('${remotePortRaw ?? 0}') ?? 0;
    return PortForwardTemplate(
      id: (json['id']?.toString() ?? '').trim().isEmpty
          ? 'pft-${now.microsecondsSinceEpoch}'
          : (json['id']?.toString() ?? '').trim(),
      name: (json['name']?.toString() ?? '').trim(),
      type: _parsePortForwardType(json['type']?.toString() ?? ''),
      localHost: (json['localHost']?.toString() ?? '127.0.0.1').trim(),
      localPort: localPort,
      remoteHost: (json['remoteHost']?.toString() ?? '').trim(),
      remotePort: remotePort,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? now,
    );
  }
}

