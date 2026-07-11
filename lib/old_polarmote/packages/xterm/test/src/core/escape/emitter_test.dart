import 'package:test/test.dart';
import 'package:xterm/src/core/escape/emitter.dart';

void main() {
  group('EscapeEmitter', () {
    test('cursorPosition reports 1-based row/column', () {
      const emitter = EscapeEmitter();
      expect(emitter.cursorPosition(0, 0), '\x1b[1;1R');
      expect(emitter.cursorPosition(2, 3), '\x1b[4;3R');
    });
  });
}
