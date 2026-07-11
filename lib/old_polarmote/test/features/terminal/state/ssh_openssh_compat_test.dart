import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:asmote/features/terminal/models/host_entry.dart';
import 'package:asmote/features/terminal/state/ssh/ssh_openssh_compat.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'applyOpenSshConfigToHost maps Host directives into HostEntry',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'asmote-ssh-config-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final identityPath = File(
        '${tempDir.path}${Platform.pathSeparator}id_test',
      );
      await identityPath.writeAsString('dummy');
      final agentPath = '${tempDir.path}${Platform.pathSeparator}agent.sock';
      final configFile = File(
        '${tempDir.path}${Platform.pathSeparator}ssh_config',
      );
      await configFile.writeAsString('''
Host *
  ServerAliveInterval 30
  ConnectTimeout 20

Host prod
  HostName 10.0.0.8
  User root
  Port 2222
  ProxyJump bastion
  Compression yes
  IdentityFile ${identityPath.path.replaceAll('\\', '/')}
  IdentityAgent ${agentPath.replaceAll('\\', '/')}
  IdentitiesOnly yes
''');

      final source = HostEntry(
        id: 'host-1',
        name: 'Prod',
        host: 'prod',
        port: 22,
        username: '',
        group: '',
        authType: AuthType.password,
        password: '',
      );

      final resolved = await applyOpenSshConfigToHost(
        source,
        explicitConfigPaths: <String>[configFile.path],
      );

      expect(resolved.host, '10.0.0.8');
      expect(resolved.username, 'root');
      expect(resolved.port, 2222);
      expect(resolved.sshProxyType, SshProxyType.jump);
      expect(resolved.jumpHosts.length, 1);
      expect(resolved.jumpHosts[0].host, 'bastion');
      expect(resolved.jumpHosts[0].port, 22);
      expect(resolved.jumpHosts[0].username, isNull);
      expect(resolved.connectTimeoutSeconds, 20);
      expect(resolved.keepAliveSeconds, 30);
      expect(resolved.authType, AuthType.key);
      expect(resolved.privateKeyPath, contains('id_test'));
      expect(resolved.useSshAgent, isTrue);
      expect(resolved.sshAgentSocketPath, contains('agent.sock'));
    },
  );

  test(
    'checkOpenSshKnownHostFingerprint trusts matching entry and rejects mismatch',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'asmote-known-hosts-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final keyBlob = _sshPublicKeyBlob(
        type: 'ssh-ed25519',
        rawKey: Uint8List.fromList(List<int>.generate(32, (i) => i)),
      );
      final fingerprint = _md5Fingerprint(keyBlob);
      final knownHostsFile = File(
        '${tempDir.path}${Platform.pathSeparator}known_hosts',
      );
      await knownHostsFile.writeAsString(
        'example.com ssh-ed25519 ${base64Encode(keyBlob)}\n',
      );

      final trusted = await checkOpenSshKnownHostFingerprint(
        host: 'example.com',
        port: 22,
        keyType: 'ssh-ed25519',
        fingerprint: fingerprint,
        explicitKnownHostsPaths: <String>[knownHostsFile.path],
      );
      expect(trusted.trusted, isTrue);
      expect(trusted.mismatched, isFalse);

      final mismatched = await checkOpenSshKnownHostFingerprint(
        host: 'example.com',
        port: 22,
        keyType: 'ssh-ed25519',
        fingerprint: '00:11:22:33:44:55:66:77:88:99:aa:bb:cc:dd:ee:ff',
        explicitKnownHostsPaths: <String>[knownHostsFile.path],
      );
      expect(mismatched.trusted, isFalse);
      expect(mismatched.mismatched, isTrue);
      expect(mismatched.expectedFingerprint, fingerprint);
    },
  );
}

Uint8List _sshPublicKeyBlob({required String type, required Uint8List rawKey}) {
  final typeBytes = utf8.encode(type);
  final out = BytesBuilder(copy: false);
  out.add(_u32(typeBytes.length));
  out.add(typeBytes);
  out.add(_u32(rawKey.length));
  out.add(rawKey);
  return out.takeBytes();
}

Uint8List _u32(int value) {
  final data = ByteData(4)..setUint32(0, value);
  return data.buffer.asUint8List();
}

String _md5Fingerprint(Uint8List blob) {
  final bytes = md5.convert(blob).bytes;
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
}
