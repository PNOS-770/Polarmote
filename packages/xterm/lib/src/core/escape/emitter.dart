class EscapeEmitter {
  const EscapeEmitter();

  String primaryDeviceAttributes() {
    // VT400 with multiple capabilities including mouse reporting (95)
    // 1=132cols, 2=printer, 6=color, 7=ansi locator, 15=polyglot,
    // 22=color, 29=window positioning, 95=mouse reporting
    return '\x1b[?1;2;6;7;15;22;29;95c';
  }

  String secondaryDeviceAttributes() {
    // xterm model 0, version 400 (matches modern xterm)
    const model = 0;
    const version = 400;
    return '\x1b[>$model;$version;0c';
  }

  String tertiaryDeviceAttributes() {
    return '\x1bP!|00000000\x1b\\';
  }

  String operatingStatus() {
    return '\x1b[0n';
  }

  String cursorPosition(int x, int y) {
    // DSR cursor position report uses 1-based row/column coordinates.
    return '\x1b[${y + 1};${x + 1}R';
  }

  String bracketedPaste(String text) {
    return '\x1b[200~$text\x1b[201~';
  }

  String size(int rows, int cols) {
    return '\x1b[8;$rows;${cols}t';
  }
}
