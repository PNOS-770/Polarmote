import 'package:dartssh2/dartssh2.dart';

import 'host_entry.dart';

class SshConnectionPool {
  final Map<String, _PooledClient> _clients = {};

  int get size => _clients.length;

  Future<SSHClient> acquire(
    HostEntry host,
    Future<SshClientBundle> Function(HostEntry host) connect,
  ) async {
    final key = _hostKey(host);
    final existing = _clients[key];
    if (existing != null) {
      existing.refCount++;
      return existing.client;
    }
    final bundle = await connect(host);
    _clients[key] = _PooledClient(
      client: bundle.client,
      auxiliaryClients: bundle.auxiliaryClients,
      refCount: 1,
    );
    return bundle.client;
  }

  void release(HostEntry host) {
    final key = _hostKey(host);
    final pooled = _clients[key];
    if (pooled == null) return;
    pooled.refCount--;
    if (pooled.refCount <= 0) {
      _clients.remove(key);
      try {
        pooled.client.close();
      } catch (_) {}
      for (final auxiliary in pooled.auxiliaryClients.reversed) {
        try {
          auxiliary.close();
        } catch (_) {}
      }
    }
  }

  void dispose() {
    for (final pooled in _clients.values) {
      try {
        pooled.client.close();
      } catch (_) {}
      for (final auxiliary in pooled.auxiliaryClients.reversed) {
        try {
          auxiliary.close();
        } catch (_) {}
      }
    }
    _clients.clear();
  }

  String _hostKey(HostEntry host) {
    return '${host.host}:${host.port}:${host.username}';
  }
}

class _PooledClient {
  _PooledClient({
    required this.client,
    required this.auxiliaryClients,
    required this.refCount,
  });

  final SSHClient client;
  final List<SSHClient> auxiliaryClients;
  int refCount;
}

class SshClientBundle {
  SshClientBundle(this.client, this.auxiliaryClients);
  final SSHClient client;
  final List<SSHClient> auxiliaryClients;
}



