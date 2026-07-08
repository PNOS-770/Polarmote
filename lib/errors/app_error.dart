sealed class AppError {
  const AppError();
  String get message;
  String? get detail;
}

enum ConnectionErrorType {
  authFailed,
  timeout,
  hostKeyChanged,
  hostKeyUnknown,
  networkUnreachable,
  connectionRefused,
  unknown,
}

class ConnectionError extends AppError {
  const ConnectionError({
    required this.type,
    required this.host,
    this.port,
    this.underlyingMessage,
    this.detail,
  });

  final ConnectionErrorType type;
  final String host;
  final int? port;
  final String? underlyingMessage;
  final String? detail;

  @override
  String get message {
    final prefix = port != null ? '$host:$port' : host;
    return switch (type) {
      ConnectionErrorType.authFailed => '认证失败: $prefix',
      ConnectionErrorType.timeout => '连接超时: $prefix',
      ConnectionErrorType.hostKeyChanged => '主机密钥已变更: $prefix',
      ConnectionErrorType.hostKeyUnknown => '未知主机密钥: $prefix',
      ConnectionErrorType.networkUnreachable => '网络不可达: $prefix',
      ConnectionErrorType.connectionRefused => '连接被拒绝: $prefix',
      ConnectionErrorType.unknown => '连接失败: $prefix${underlyingMessage != null ? ' - $underlyingMessage' : ''}',
    };
  }
}

enum TransferErrorType {
  networkError,
  diskFull,
  permissionDenied,
  fileNotFound,
  fileExists,
  cancelled,
  unknown,
}

class TransferError extends AppError {
  const TransferError({
    required this.type,
    this.path,
    this.underlyingMessage,
    this.detail,
  });

  final TransferErrorType type;
  final String? path;
  final String? underlyingMessage;
  final String? detail;

  @override
  String get message {
    final suffix = path != null ? ': $path' : '';
    return switch (type) {
      TransferErrorType.networkError => '传输网络错误$suffix',
      TransferErrorType.diskFull => '磁盘空间不足$suffix',
      TransferErrorType.permissionDenied => '权限不足$suffix',
      TransferErrorType.fileNotFound => '文件不存在$suffix',
      TransferErrorType.fileExists => '文件已存在$suffix',
      TransferErrorType.cancelled => '传输已取消$suffix',
      TransferErrorType.unknown => '传输失败$suffix${underlyingMessage != null ? ' - $underlyingMessage' : ''}',
    };
  }
}

enum ScriptErrorType {
  executionFailed,
  timeout,
  sessionNotConnected,
  invalidScript,
  unknown,
}

class ScriptError extends AppError {
  const ScriptError({
    required this.type,
    this.scriptName,
    this.underlyingMessage,
    this.detail,
  });

  final ScriptErrorType type;
  final String? scriptName;
  final String? underlyingMessage;
  final String? detail;

  @override
  String get message {
    final suffix = scriptName != null ? ': $scriptName' : '';
    return switch (type) {
      ScriptErrorType.executionFailed => '脚本执行失败$suffix',
      ScriptErrorType.timeout => '脚本执行超时$suffix',
      ScriptErrorType.sessionNotConnected => '会话未连接$suffix',
      ScriptErrorType.invalidScript => '无效脚本$suffix',
      ScriptErrorType.unknown => '脚本错误$suffix${underlyingMessage != null ? ' - $underlyingMessage' : ''}',
    };
  }
}

enum PortForwardErrorType {
  bindFailed,
  connectionFailed,
  alreadyExists,
  unknown,
}

class PortForwardError extends AppError {
  const PortForwardError({
    required this.type,
    this.ruleName,
    this.underlyingMessage,
    this.detail,
  });

  final PortForwardErrorType type;
  final String? ruleName;
  final String? underlyingMessage;
  final String? detail;

  @override
  String get message {
    final suffix = ruleName != null ? ': $ruleName' : '';
    return switch (type) {
      PortForwardErrorType.bindFailed => '端口绑定失败$suffix',
      PortForwardErrorType.connectionFailed => '转发连接失败$suffix',
      PortForwardErrorType.alreadyExists => '转发规则已存在$suffix',
      PortForwardErrorType.unknown => '端口转发错误$suffix${underlyingMessage != null ? ' - $underlyingMessage' : ''}',
    };
  }
}

