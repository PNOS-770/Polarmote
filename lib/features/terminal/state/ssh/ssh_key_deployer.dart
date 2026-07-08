import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

class SshKeyDeployResult {
  final bool success;
  final String? error;

  const SshKeyDeployResult({required this.success, this.error});
}

Future<SshKeyDeployResult> deployPublicKey({
  required String host,
  required int port,
  required String username,
  required String password,
  required String publicKeyLine,
  Duration timeout = const Duration(seconds: 15),
}) async {
  try {
    final socket = await SSHSocket.connect(
      host,
      port,
      timeout: timeout,
    );
    final client = SSHClient(
      socket,
      username: username,
      onPasswordRequest: () async => password,
      onVerifyHostKey: (type, fingerprint) async => true,
    );
    try {
      final cmd =
          'mkdir -p ~/.ssh && chmod 700 ~/.ssh && '
          'echo \'$publicKeyLine\' >> ~/.ssh/authorized_keys && '
          'chmod 600 ~/.ssh/authorized_keys && '
          'echo "DEPLOY_OK"';

      final session = await client.execute(cmd);
      final stdoutBytes = await session.stdout.fold<Uint8List>(
        Uint8List(0),
        (prev, chunk) {
          final combined = Uint8List(prev.length + chunk.length);
          combined.setRange(0, prev.length, prev);
          combined.setRange(prev.length, combined.length, chunk);
          return combined;
        },
      );
      final stderrBytes = await session.stderr.fold<Uint8List>(
        Uint8List(0),
        (prev, chunk) {
          final combined = Uint8List(prev.length + chunk.length);
          combined.setRange(0, prev.length, prev);
          combined.setRange(prev.length, combined.length, chunk);
          return combined;
        },
      );
      await session.done;

      final stdout = utf8.decode(stdoutBytes);
      final stderr = utf8.decode(stderrBytes);

      if (stdout.trim().endsWith('DEPLOY_OK')) {
        return const SshKeyDeployResult(success: true);
      }
      return SshKeyDeployResult(
        success: false,
        error: stderr.isNotEmpty ? stderr : stdout,
      );
    } finally {
      client.close();
    }
  } catch (e) {
    return SshKeyDeployResult(
      success: false,
      error: '$e',
    );
  }
}

