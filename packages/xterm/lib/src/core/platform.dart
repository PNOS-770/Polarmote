enum TerminalTargetPlatform {
  unknown,

  android,

  ios,

  fuchsia,

  linux,

  macos,

  windows,

  web,
}

/// SGR 鼠标滚轮事件的编码方式。
enum SgrWheelEncoding {
  /// Windows Terminal 编码：滚轮上=64，滚轮下=65。
  windowsTerminal,

  /// xterm 编码：滚轮上=68，滚轮下=69。
  xterm,
}
