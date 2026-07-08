import 'package:flutter_test/flutter_test.dart';
import 'package:Polarmote/errors/app_error.dart';

void main() {
  group('ConnectionError', () {
    test('creates auth failed message', () {
      final error = ConnectionError(
        type: ConnectionErrorType.authFailed,
        host: '192.168.1.1',
        port: 22,
      );
      expect(error.message, contains('认证失败'));
      expect(error.message, contains('192.168.1.1'));
    });

    test('creates timeout message', () {
      final error = ConnectionError(
        type: ConnectionErrorType.timeout,
        host: 'example.com',
        port: 2222,
      );
      expect(error.message, contains('超时'));
    });
  });

  group('TransferError', () {
    test('creates disk full message', () {
      final error = TransferError(
        type: TransferErrorType.diskFull,
        path: '/home/data',
      );
      expect(error.message, contains('磁盘空间不足'));
      expect(error.message, contains('/home/data'));
    });

    test('creates cancelled message', () {
      final error = TransferError(type: TransferErrorType.cancelled);
      expect(error.message, contains('已取消'));
    });
  });

  group('ScriptError', () {
    test('creates execution failed message', () {
      final error = ScriptError(
        type: ScriptErrorType.executionFailed,
        scriptName: 'deploy.sh',
      );
      expect(error.message, contains('执行失败'));
      expect(error.message, contains('deploy.sh'));
    });
  });

  group('PortForwardError', () {
    test('creates bind failed message', () {
      final error = PortForwardError(
        type: PortForwardErrorType.bindFailed,
        ruleName: 'web-tunnel',
      );
      expect(error.message, contains('端口绑定失败'));
      expect(error.message, contains('web-tunnel'));
    });
  });
}
