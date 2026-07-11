import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../models/host_entry.dart';
import '../ssh/ssh_openssh_compat.dart';
import '../terminal_app_state.dart';
class _SshSocketRoute {
  const _SshSocketRoute({required this.socket, required this.auxiliaryClients});

  final SSHSocket socket;
  final List<SSHClient> auxiliaryClients;
}

class _PendingSocksRead {
  const _PendingSocksRead({required this.length, required this.completer});

  final int length;
  final Completer<Uint8List> completer;
}

class _BufferedSshSocket implements SSHSocket {
  _BufferedSshSocket(this._socket) {
    _subscription = _socket.listen(
      (data) {
        if (_handshakeDone) {
          _streamController.add(data);
          return;
        }
        _buffer.addAll(data);
        _drainPendingReads();
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_doneCompleter.isCompleted) {
          _doneCompleter.completeError(error, stackTrace);
        }
        for (final pending in _pendingReads) {
          if (!pending.completer.isCompleted) {
            pending.completer.completeError(error, stackTrace);
          }
        }
        _pendingReads.clear();
        _streamController.addError(error, stackTrace);
      },
      onDone: () {
        if (!_doneCompleter.isCompleted) {
          _doneCompleter.complete();
        }
        for (final pending in _pendingReads) {
          if (!pending.completer.isCompleted) {
            pending.completer.completeError(
              const SocketException('socket closed during SOCKS handshake'),
            );
          }
        }
        _pendingReads.clear();
        unawaited(_streamController.close());
      },
      cancelOnError: false,
    );
  }

  final Socket _socket;
  final StreamController<Uint8List> _streamController =
      StreamController<Uint8List>();
  final List<int> _buffer = <int>[];
  final List<_PendingSocksRead> _pendingReads = <_PendingSocksRead>[];
  final Completer<void> _doneCompleter = Completer<void>();
  late final StreamSubscription<Uint8List> _subscription;
  bool _handshakeDone = false;

  @override
  Stream<Uint8List> get stream => _streamController.stream;

  @override
  StreamSink<List<int>> get sink => _socket;

  @override
  Future<void> get done => _doneCompleter.future;

  Future<void> writeBytes(List<int> bytes) async {
    _socket.add(bytes);
    await _socket.flush();
  }

  Future<Uint8List> readExact(int length, {required Duration timeout}) async {
    if (length <= 0) {
      return Uint8List(0);
    }
    if (_buffer.length >= length) {
      return Uint8List.fromList(_consume(length));
    }
    final completer = Completer<Uint8List>();
    final pending = _PendingSocksRead(length: length, completer: completer);
    _pendingReads.add(pending);
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      _pendingReads.remove(pending);
      throw TimeoutException(
        'SOCKS handshake timeout while waiting for $length bytes',
      );
    }
  }

  void finishHandshake() {
    if (_handshakeDone) {
      return;
    }
    _handshakeDone = true;
    if (_buffer.isNotEmpty) {
      _streamController.add(Uint8List.fromList(_buffer));
      _buffer.clear();
    }
  }

  List<int> _consume(int length) {
    final next = _buffer.sublist(0, length);
    _buffer.removeRange(0, length);
    return next;
  }

  void _drainPendingReads() {
    while (_pendingReads.isNotEmpty) {
      final next = _pendingReads.first;
      if (_buffer.length < next.length) {
        break;
      }
      _pendingReads.removeAt(0);
      if (!next.completer.isCompleted) {
        next.completer.complete(Uint8List.fromList(_consume(next.length)));
      }
    }
  }

  @override
  Future<void> close() async {
    try {
      await _socket.close();
    } finally {
      await _subscription.cancel();
      if (!_doneCompleter.isCompleted) {
        _doneCompleter.complete();
      }
      await _streamController.close();
    }
  }

  @override
  void destroy() {
    _socket.destroy();
    unawaited(_subscription.cancel());
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
    unawaited(_streamController.close());
  }
}

extension TerminalAppStateSsh on TerminalAppState {
  Future<SSHClient> connectSshClientForHost(
    HostEntry host, {
    List<SSHClient>? auxiliaryClients,
    Set<String>? visitedHostIds,
  }) async {
    final effectiveHost = await applyOpenSshConfigToHost(host);
    final route = await _openSshSocketRoute(
      effectiveHost,
      visitedHostIds ?? <String>{},
    );
    final identities = await _loadHostIdentities(effectiveHost);
    var pass = (effectiveHost.password ?? '').trim();
    if (pass.isEmpty && effectiveHost.authType == AuthType.password) {
      final stored = await readHostSecret(effectiveHost.id);
      pass = (stored?.password ?? '').trim();
    }
    final keepAliveSeconds = effectiveHost.keepAliveSeconds.clamp(0, 600);
    final keepAlive = keepAliveSeconds > 0
        ? Duration(seconds: keepAliveSeconds)
        : null;

    final client = SSHClient(
      route.socket,
      username: effectiveHost.username,
      onPasswordRequest: effectiveHost.authType == AuthType.password
          ? () async => pass.isEmpty ? null : pass
          : null,
      identities: identities.isEmpty ? null : identities,
      keepAliveInterval: keepAlive,
      onVerifyHostKey: (type, fingerprint) {
        final fingerprintText = fingerprint
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join(':');
        return verifyHostFingerprint(
          host: effectiveHost,
          keyType: type,
          fingerprint: fingerprintText,
        );
      },
    );

    if (auxiliaryClients != null && route.auxiliaryClients.isNotEmpty) {
      auxiliaryClients.addAll(route.auxiliaryClients);
    }
    return client;
  }

  Future<_SshSocketRoute> _openSshSocketRoute(
    HostEntry host,
    Set<String> visitedHostIds,
  ) async {
    final hostId = host.id.trim();
    if (hostId.isNotEmpty && !visitedHostIds.add(hostId)) {
      throw StateError('SSH proxy loop detected for host: ${host.name}');
    }

    final proxyType = host.sshProxyType;
    final jumpHosts = host.jumpHosts;

    if (proxyType == SshProxyType.jump && jumpHosts.isNotEmpty) {
      return _openSshViaJumpChain(host, jumpHosts, visitedHostIds);
    }

    if (proxyType == SshProxyType.socks5) {
      final proxyHost = (host.socksProxyHost ?? '').trim();
      if (proxyHost.isEmpty) {
        throw StateError('SOCKS proxy host is empty');
      }
      final socket = await _connectViaSocks5(host);
      return _SshSocketRoute(
        socket: socket,
        auxiliaryClients: const <SSHClient>[],
      );
    }

    final socket = await SSHSocket.connect(
      host.host,
      host.port,
      timeout: _connectTimeoutForHost(host),
    );
    return _SshSocketRoute(
      socket: socket,
      auxiliaryClients: const <SSHClient>[],
    );
  }

  Future<_SshSocketRoute> _openSshViaJumpChain(
    HostEntry finalHost,
    List<JumpHostEntry> chain,
    Set<String> visitedHostIds,
  ) async {
    var allAux = <SSHClient>[];
    SSHClient? prevClient;

    for (var i = 0; i < chain.length; i++) {
      final jump = chain[i];
      final isLast = i == chain.length - 1;
      final hopEntry = _buildJumpHostEntry(finalHost, jump);

      SSHClient hopClient;
      try {
        if (i == 0) {
          hopClient = await connectSshClientForHost(
            hopEntry,
            auxiliaryClients: allAux,
            visitedHostIds: visitedHostIds,
          );
        } else {
          final nextHost = isLast ? finalHost.host : chain[i + 1].host;
          final nextPort = isLast ? finalHost.port : chain[i + 1].port;
          final socket = await prevClient!.forwardLocal(nextHost, nextPort);
          hopClient = await _buildClientOnSocket(socket, hopEntry);
        }
      } catch (error) {
        for (final c in allAux.reversed) { try { c.close(); } catch (_) {} }
        rethrow;
      }
      allAux.add(hopClient);
      prevClient = hopClient;

      if (!isLast) continue;
      try {
        final finalSocket = await hopClient.forwardLocal(
          finalHost.host,
          finalHost.port,
        );
        return _SshSocketRoute(socket: finalSocket, auxiliaryClients: allAux);
      } catch (error) {
        for (final c in allAux.reversed) { try { c.close(); } catch (_) {} }
        rethrow;
      }
    }
    throw StateError('ProxyJump chain is empty');
  }

  Future<SSHClient> _buildClientOnSocket(SSHSocket socket, HostEntry host) async {
    final identities = await _loadHostIdentities(host);
    var pass = (host.password ?? '').trim();
    if (pass.isEmpty && host.authType == AuthType.password) {
      final stored = await readHostSecret(host.id);
      pass = (stored?.password ?? '').trim();
    }
    return SSHClient(
      socket,
      username: host.username,
      onPasswordRequest: host.authType == AuthType.password
          ? () async => pass.isEmpty ? null : pass
          : null,
      identities: identities.isEmpty ? null : identities,
      keepAliveInterval: host.keepAliveSeconds > 0
          ? Duration(seconds: host.keepAliveSeconds)
          : null,
      onVerifyHostKey: (type, fingerprint) {
        final fingerprintText = fingerprint
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join(':');
        return verifyHostFingerprint(
          host: host,
          keyType: type,
          fingerprint: fingerprintText,
        );
      },
    );
  }

  HostEntry _buildJumpHostEntry(HostEntry sourceHost, JumpHostEntry jump) {
    final username = (jump.username ?? sourceHost.username).trim();
    final safeId = '$username@${jump.host}:${jump.port}'
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return HostEntry(
      id: 'jump-manual-$safeId',
      name: jump.host,
      host: jump.host,
      port: jump.port,
      username: username,
      group: sourceHost.group,
      authType: sourceHost.authType,
      connectionType: ConnectionType.ssh,
      sshProxyType: SshProxyType.none,
      socksProxyHost: null,
      socksProxyPort: 1080,
      socksProxyUsername: null,
      socksProxyPassword: null,
      jumpHosts: const <JumpHostEntry>[],
      sshAgentSocketPath: sourceHost.sshAgentSocketPath,
      privateKeyPassphrase: sourceHost.privateKeyPassphrase,
      keepAliveSeconds: sourceHost.keepAliveSeconds,
      connectTimeoutSeconds: sourceHost.connectTimeoutSeconds,
      localShellType: LocalShellType.systemDefault,
      password: sourceHost.password,
      privateKeyPath: sourceHost.privateKeyPath,
    );
  }



  Duration _connectTimeoutForHost(HostEntry host) {
    return Duration(seconds: host.connectTimeoutSeconds.clamp(3, 120));
  }

  Future<List<SSHKeyPair>> _loadHostIdentities(HostEntry host) async {
    final identities = <SSHKeyPair>[];
    if (host.authType == AuthType.key) {
      final keyPath = (host.privateKeyPath ?? '').trim();
      if (keyPath.isNotEmpty) {
        final pem = await File(keyPath).readAsString();
        final passphrase = (host.privateKeyPassphrase ?? host.password ?? '')
            .trim();
        try {
          identities.addAll(
            SSHKeyPair.fromPem(pem, passphrase.isEmpty ? null : passphrase),
          );
        } catch (error) {
          final encrypted = SSHKeyPair.isEncryptedPem(pem);
          if (encrypted && passphrase.isEmpty) {
            throw StateError(
              locale.languageCode == 'zh'
                  ? '私钥需要口令，请在会话配置中填写私钥口令'
                  : 'Encrypted private key requires a passphrase',
            );
          }
          rethrow;
        }
      }
    }

    return _dedupeIdentities(identities);
  }

  List<SSHKeyPair> _dedupeIdentities(List<SSHKeyPair> identities) {
    final deduped = <SSHKeyPair>[];
    final unique = <String>{};
    for (final identity in identities) {
      final encodedPublicKey = identity.toPublicKey().encode();
      final signature = '${identity.type}:${base64Encode(encodedPublicKey)}';
      if (unique.add(signature)) {
        deduped.add(identity);
      }
    }
    return deduped;
  }

  Future<SSHSocket> _connectViaSocks5(HostEntry host) async {
    final proxyHost = host.socksProxyHost!.trim();
    final proxyPort = host.socksProxyPort.clamp(1, 65535);
    final timeout = _connectTimeoutForHost(host);
    final socket = await Socket.connect(proxyHost, proxyPort, timeout: timeout);
    final bufferedSocket = _BufferedSshSocket(socket);
    try {
      final user = (host.socksProxyUsername ?? '').trim();
      final pass = host.socksProxyPassword ?? '';
      const noAuth = 0x00;
      const userPassAuth = 0x02;
      final methods = <int>[
        noAuth,
        if (user.isNotEmpty || pass.isNotEmpty) userPassAuth,
      ];

      await bufferedSocket.writeBytes(<int>[0x05, methods.length, ...methods]);
      final methodSelection = await bufferedSocket.readExact(
        2,
        timeout: timeout,
      );
      if (methodSelection[0] != 0x05) {
        throw StateError('SOCKS version mismatch');
      }
      final selectedMethod = methodSelection[1];
      if (selectedMethod == 0xFF) {
        throw StateError('SOCKS server rejected all authentication methods');
      }
      if (selectedMethod == userPassAuth) {
        final userBytes = utf8.encode(user);
        final passBytes = utf8.encode(pass);
        if (userBytes.length > 255 || passBytes.length > 255) {
          throw StateError('SOCKS username/password is too long');
        }
        await bufferedSocket.writeBytes(<int>[
          0x01,
          userBytes.length,
          ...userBytes,
          passBytes.length,
          ...passBytes,
        ]);
        final authReply = await bufferedSocket.readExact(2, timeout: timeout);
        if (authReply[1] != 0x00) {
          throw StateError('SOCKS authentication failed');
        }
      }

      final address = host.host.trim();
      final port = host.port.clamp(1, 65535);
      final destination = _encodeSocksDestination(address);
      await bufferedSocket.writeBytes(<int>[
        0x05,
        0x01,
        0x00,
        destination.atyp,
        ...destination.addressBytes,
        (port >> 8) & 0xFF,
        port & 0xFF,
      ]);
      final replyHead = await bufferedSocket.readExact(4, timeout: timeout);
      if (replyHead[0] != 0x05) {
        throw StateError('Invalid SOCKS connect reply');
      }
      final replyCode = replyHead[1];
      if (replyCode != 0x00) {
        throw StateError(
          'SOCKS connect failed: ${_socksReplyMessage(replyCode)}',
        );
      }
      final boundAddressType = replyHead[3];
      if (boundAddressType == 0x01) {
        await bufferedSocket.readExact(4, timeout: timeout);
      } else if (boundAddressType == 0x04) {
        await bufferedSocket.readExact(16, timeout: timeout);
      } else if (boundAddressType == 0x03) {
        final length = await bufferedSocket.readExact(1, timeout: timeout);
        await bufferedSocket.readExact(length.first, timeout: timeout);
      } else {
        throw StateError('Unknown SOCKS bound address type: $boundAddressType');
      }
      await bufferedSocket.readExact(2, timeout: timeout);
      bufferedSocket.finishHandshake();
      return bufferedSocket;
    } catch (_) {
      try {
        await bufferedSocket.close();
      } catch (_) {}
      rethrow;
    }
  }

  _SocksDestination _encodeSocksDestination(String host) {
    final parsed = InternetAddress.tryParse(host);
    if (parsed != null) {
      if (parsed.type == InternetAddressType.IPv4) {
        return _SocksDestination(atyp: 0x01, addressBytes: parsed.rawAddress);
      }
      if (parsed.type == InternetAddressType.IPv6) {
        return _SocksDestination(atyp: 0x04, addressBytes: parsed.rawAddress);
      }
    }
    final encoded = utf8.encode(host);
    if (encoded.length > 255) {
      throw StateError('SOCKS destination hostname is too long');
    }
    return _SocksDestination(
      atyp: 0x03,
      addressBytes: <int>[encoded.length, ...encoded],
    );
  }

  String _socksReplyMessage(int code) {
    switch (code) {
      case 0x01:
        return 'general SOCKS server failure';
      case 0x02:
        return 'connection not allowed by ruleset';
      case 0x03:
        return 'network unreachable';
      case 0x04:
        return 'host unreachable';
      case 0x05:
        return 'connection refused by destination host';
      case 0x06:
        return 'TTL expired';
      case 0x07:
        return 'command not supported';
      case 0x08:
        return 'address type not supported';
      default:
        return 'unknown error code $code';
    }
  }
}

class _SocksDestination {
  const _SocksDestination({required this.atyp, required this.addressBytes});

  final int atyp;
  final List<int> addressBytes;
}


