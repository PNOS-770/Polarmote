import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartssh2/dartssh2.dart';
// ignore: implementation_imports
import 'package:dartssh2/src/ssh_hostkey.dart';
import 'package:path/path.dart' as p;

import '../../models/host_entry.dart' show AuthType, HostEntry, JumpHostEntry, SshProxyType;

const int _sshAgentRequestIdentities = 11;
const int _sshAgentIdentitiesAnswer = 12;
const int _sshAgentSignRequest = 13;
const int _sshAgentSignResponse = 14;
const int _sshAgentFailure = 5;
const int _sshAgentFlagRsaSha2_256 = 2;
const int _sshAgentFlagRsaSha2_512 = 4;

String normalizeSshHostKeyType(String keyType) {
  final raw = keyType.trim().toLowerCase();
  if (raw == 'rsa-sha2-256' || raw == 'rsa-sha2-512') {
    return 'ssh-rsa';
  }
  return raw;
}

String normalizeFingerprint(String fingerprint) {
  return fingerprint.trim().toLowerCase();
}

class OpenSshKnownHostDecision {
  const OpenSshKnownHostDecision({
    required this.trusted,
    required this.mismatched,
    this.expectedFingerprint,
  });

  final bool trusted;
  final bool mismatched;
  final String? expectedFingerprint;
}

Future<HostEntry> applyOpenSshConfigToHost(
  HostEntry sourceHost, {
  List<String>? explicitConfigPaths,
}) async {
  if (!sourceHost.isSsh) {
    return sourceHost;
  }
  final target = sourceHost.host.trim();
  if (target.isEmpty) {
    return sourceHost;
  }
  final records = await _loadOpenSshDirectiveRecords(
    explicitConfigPaths: explicitConfigPaths,
  );
  if (records.isEmpty) {
    return sourceHost;
  }

  final options = _resolveOpenSshHostOptions(records, target: target);
  if (options == null) {
    return sourceHost;
  }

  final home = _resolveHomeDirectory();
  final resolvedHost = (options.hostName ?? sourceHost.host).trim();
  final resolvedUser =
      (sourceHost.username.trim().isEmpty ? options.user : sourceHost.username)
          ?.trim();
  final resolvedPort =
      (options.port != null && (sourceHost.port <= 0 || sourceHost.port == 22))
      ? options.port!
      : sourceHost.port;
  final expandedIdentityFiles = options.identityFiles
      .map(
        (item) => _expandOpenSshPath(
          item,
          home: home,
          host: resolvedHost,
          user: resolvedUser ?? '',
          port: resolvedPort,
        ),
      )
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  String? resolvedKeyPath = sourceHost.privateKeyPath;
  if ((resolvedKeyPath ?? '').trim().isEmpty &&
      expandedIdentityFiles.isNotEmpty) {
    resolvedKeyPath = expandedIdentityFiles.first;
  }

  var resolvedAuthType = sourceHost.authType;
  if (options.identitiesOnly == true &&
      resolvedAuthType == AuthType.password &&
      (sourceHost.password ?? '').trim().isEmpty &&
      (resolvedKeyPath ?? '').trim().isNotEmpty) {
    resolvedAuthType = AuthType.key;
  }

  var resolvedProxyType = sourceHost.sshProxyType;
  var resolvedJumpHosts = sourceHost.jumpHosts;
  final proxyJump = (options.proxyJump ?? '').trim();
  if (resolvedProxyType == SshProxyType.none &&
      proxyJump.isNotEmpty &&
      proxyJump.toLowerCase() != 'none') {
    resolvedProxyType = SshProxyType.jump;
    resolvedJumpHosts = proxyJump
        .split(',')
        .map((part) => _legacyJumpHostFromConfig(part.trim(), sourceHost.username))
        .where((j) => j != null)
        .cast<JumpHostEntry>()
        .toList(growable: false);
  }

  var resolvedUseAgent = sourceHost.useSshAgent;
  String? resolvedAgentSocketPath = sourceHost.sshAgentSocketPath;
  final identityAgent = options.identityAgent?.trim();
  if (identityAgent != null && identityAgent.isNotEmpty) {
    if (identityAgent.toLowerCase() == 'none') {
      resolvedUseAgent = false;
      resolvedAgentSocketPath = null;
    } else {
      resolvedUseAgent = true;
      resolvedAgentSocketPath = _expandOpenSshPath(
        identityAgent,
        home: home,
        host: resolvedHost,
        user: resolvedUser ?? '',
        port: resolvedPort,
      );
    }
  }

  final keepAliveSeconds =
      (sourceHost.keepAliveSeconds == 10 &&
          options.serverAliveIntervalSeconds != null)
      ? options.serverAliveIntervalSeconds!.clamp(0, 600).toInt()
      : sourceHost.keepAliveSeconds;
  final connectTimeoutSeconds =
      (sourceHost.connectTimeoutSeconds == 12 &&
          options.connectTimeoutSeconds != null)
      ? options.connectTimeoutSeconds!.clamp(3, 120).toInt()
      : sourceHost.connectTimeoutSeconds;

  return sourceHost.copyWith(
    host: resolvedHost,
    username: resolvedUser ?? sourceHost.username,
    port: resolvedPort,
    authType: resolvedAuthType,
    privateKeyPath: resolvedKeyPath,
    sshProxyType: resolvedProxyType,
    jumpHosts: resolvedJumpHosts,
    useSshAgent: resolvedUseAgent,
    sshAgentSocketPath: resolvedAgentSocketPath,
    keepAliveSeconds: keepAliveSeconds,
    connectTimeoutSeconds: connectTimeoutSeconds,
  );
}

Future<OpenSshKnownHostDecision> checkOpenSshKnownHostFingerprint({
  required String host,
  required int port,
  required String keyType,
  required String fingerprint,
  List<String>? explicitKnownHostsPaths,
}) async {
  final normalizedType = normalizeSshHostKeyType(keyType);
  final normalizedFingerprint = normalizeFingerprint(fingerprint);
  if (host.trim().isEmpty ||
      normalizedType.isEmpty ||
      normalizedFingerprint.isEmpty) {
    return const OpenSshKnownHostDecision(
      trusted: false,
      mismatched: false,
      expectedFingerprint: null,
    );
  }

  final entries = await _loadKnownHostEntries(
    explicitKnownHostsPaths: explicitKnownHostsPaths,
  );
  var foundMismatch = false;
  String? expected;
  for (final entry in entries) {
    if (entry.keyType != normalizedType) {
      continue;
    }
    if (!_matchesKnownHostsHostList(entry.hostsField, host, port)) {
      continue;
    }
    if (entry.fingerprint == normalizedFingerprint) {
      return const OpenSshKnownHostDecision(trusted: true, mismatched: false);
    }
    foundMismatch = true;
    expected ??= entry.fingerprint;
  }
  return OpenSshKnownHostDecision(
    trusted: false,
    mismatched: foundMismatch,
    expectedFingerprint: expected,
  );
}

String? resolveSshAgentSocketPath(HostEntry host) {
  final configured = (host.sshAgentSocketPath ?? '').trim();
  if (configured.isNotEmpty) {
    if (configured.toLowerCase() == 'none') {
      return null;
    }
    if (_looksLikeWindowsNamedPipe(configured)) {
      return null;
    }
    return configured;
  }
  final fromEnv = (Platform.environment['SSH_AUTH_SOCK'] ?? '').trim();
  if (fromEnv.isEmpty) {
    return null;
  }
  if (_looksLikeWindowsNamedPipe(fromEnv)) {
    return null;
  }
  return fromEnv;
}

Future<List<SSHKeyPair>> loadSshAgentIdentities(HostEntry host) async {
  final socketPath = resolveSshAgentSocketPath(host);
  if (socketPath == null || socketPath.isEmpty) {
    return const <SSHKeyPair>[];
  }
  try {
    final client = _SshAgentClient(socketPath);
    final identities = client.listIdentities();
    return identities
        .map((identity) => _SshAgentKeyPair(client: client, identity: identity))
        .toList(growable: false);
  } catch (_) {
    return const <SSHKeyPair>[];
  }
}

class _OpenSshResolvedOptions {
  String? hostName;
  String? user;
  int? port;
  String? proxyJump;
  int? connectTimeoutSeconds;
  int? serverAliveIntervalSeconds;
  bool? identitiesOnly;
  String? identityAgent;
  final List<String> identityFiles = <String>[];
}

class _OpenSshDirectiveRecord {
  const _OpenSshDirectiveRecord({
    required this.hostPatterns,
    required this.key,
    required this.value,
  });

  final List<String>? hostPatterns;
  final String key;
  final String value;
}

class _KnownHostEntry {
  const _KnownHostEntry({
    required this.hostsField,
    required this.keyType,
    required this.fingerprint,
  });

  final String hostsField;
  final String keyType;
  final String fingerprint;
}

class _SshAgentIdentity {
  const _SshAgentIdentity({
    required this.publicKeyBlob,
    required this.comment,
    required this.keyType,
  });

  final Uint8List publicKeyBlob;
  final String comment;
  final String keyType;
}

class _SshAgentClient {
  const _SshAgentClient(this.socketPath);

  final String socketPath;

  List<_SshAgentIdentity> listIdentities() {
    final request = Uint8List.fromList(<int>[_sshAgentRequestIdentities]);
    final payload = _exchange(request);
    if (payload.isEmpty) {
      throw const FormatException('ssh-agent response is empty');
    }
    final messageId = payload[0];
    if (messageId == _sshAgentFailure) {
      throw const FormatException('ssh-agent failed to list identities');
    }
    if (messageId != _sshAgentIdentitiesAnswer) {
      throw FormatException('unexpected ssh-agent response id=$messageId');
    }
    final reader = _SshBinaryReader(Uint8List.sublistView(payload, 1));
    final count = reader.readUint32();
    final result = <_SshAgentIdentity>[];
    for (var i = 0; i < count; i++) {
      final blob = reader.readString();
      final comment = utf8.decode(reader.readString(), allowMalformed: true);
      final type = _readSshStringHead(blob);
      if (type.isEmpty) {
        continue;
      }
      result.add(
        _SshAgentIdentity(publicKeyBlob: blob, comment: comment, keyType: type),
      );
    }
    return result;
  }

  Uint8List sign({
    required Uint8List publicKeyBlob,
    required Uint8List data,
    required String algorithm,
  }) {
    final writer = _SshBinaryWriter();
    writer.writeUint8(_sshAgentSignRequest);
    writer.writeString(publicKeyBlob);
    writer.writeString(data);
    writer.writeUint32(_flagsForAlgorithm(algorithm));
    final payload = _exchange(writer.takeBytes());
    if (payload.isEmpty) {
      throw const FormatException('ssh-agent signature response is empty');
    }
    final messageId = payload[0];
    if (messageId == _sshAgentFailure) {
      throw const FormatException('ssh-agent refused sign request');
    }
    if (messageId != _sshAgentSignResponse) {
      throw FormatException('unexpected ssh-agent sign response id=$messageId');
    }
    final reader = _SshBinaryReader(Uint8List.sublistView(payload, 1));
    return reader.readString();
  }

  Uint8List _exchange(Uint8List requestPayload) {
    final address = InternetAddress(socketPath, type: InternetAddressType.unix);
    final socket = RawSynchronousSocket.connectSync(address, 0);
    try {
      final frame = _frame(requestPayload);
      socket.writeFromSync(frame);
      return _readFrame(socket);
    } finally {
      socket.closeSync();
    }
  }

  Uint8List _frame(Uint8List payload) {
    final writer = _SshBinaryWriter();
    writer.writeUint32(payload.length);
    writer.writeRaw(payload);
    return writer.takeBytes();
  }

  Uint8List _readFrame(RawSynchronousSocket socket) {
    final sizeBytes = _readExact(socket, 4);
    final size = _readUint32(sizeBytes, 0);
    if (size < 0 || size > 8 * 1024 * 1024) {
      throw FormatException('invalid ssh-agent frame size: $size');
    }
    return _readExact(socket, size);
  }

  Uint8List _readExact(RawSynchronousSocket socket, int length) {
    if (length <= 0) {
      return Uint8List(0);
    }
    final out = Uint8List(length);
    var offset = 0;
    while (offset < length) {
      final read = socket.readIntoSync(out, offset, length);
      if (read <= 0) {
        throw const SocketException('unexpected EOF from ssh-agent');
      }
      offset += read;
    }
    return out;
  }

  int _flagsForAlgorithm(String algorithm) {
    final normalized = algorithm.trim().toLowerCase();
    if (normalized == 'rsa-sha2-512') {
      return _sshAgentFlagRsaSha2_512;
    }
    if (normalized == 'rsa-sha2-256') {
      return _sshAgentFlagRsaSha2_256;
    }
    return 0;
  }
}

class _SshAgentKeyPair implements SSHKeyPair {
  const _SshAgentKeyPair({required this.client, required this.identity});

  final _SshAgentClient client;
  final _SshAgentIdentity identity;

  @override
  String get name => identity.keyType;

  @override
  String get type =>
      identity.keyType == 'ssh-rsa' ? 'rsa-sha2-256' : identity.keyType;

  @override
  SSHHostKey toPublicKey() => _OpaqueHostKey(identity.publicKeyBlob);

  @override
  SSHSignature sign(Uint8List data) {
    final signature = client.sign(
      publicKeyBlob: identity.publicKeyBlob,
      data: data,
      algorithm: type,
    );
    return _OpaqueSignature(signature);
  }

  @override
  String toPem() {
    throw UnsupportedError(
      'SSH agent key does not expose private key material',
    );
  }
}

class _OpaqueHostKey implements SSHHostKey {
  const _OpaqueHostKey(this.encoded);

  final Uint8List encoded;

  @override
  Uint8List encode() => encoded;
}

class _OpaqueSignature implements SSHSignature {
  const _OpaqueSignature(this.encoded);

  final Uint8List encoded;

  @override
  Uint8List encode() => encoded;
}

class _SshBinaryWriter {
  _SshBinaryWriter() : _buffer = BytesBuilder(copy: false);

  final BytesBuilder _buffer;

  void writeUint8(int value) {
    _buffer.add(<int>[value & 0xFF]);
  }

  void writeUint32(int value) {
    final data = ByteData(4)..setUint32(0, value);
    _buffer.add(data.buffer.asUint8List());
  }

  void writeString(Uint8List value) {
    writeUint32(value.length);
    _buffer.add(value);
  }

  void writeRaw(Uint8List value) {
    _buffer.add(value);
  }

  Uint8List takeBytes() => _buffer.takeBytes();
}

class _SshBinaryReader {
  _SshBinaryReader(this._source);

  final Uint8List _source;
  int _offset = 0;

  int readUint32() {
    _ensureAvailable(4);
    final value = _readUint32(_source, _offset);
    _offset += 4;
    return value;
  }

  Uint8List readString() {
    final length = readUint32();
    _ensureAvailable(length);
    final value = Uint8List.sublistView(_source, _offset, _offset + length);
    _offset += length;
    return Uint8List.fromList(value);
  }

  void _ensureAvailable(int required) {
    if (_offset + required > _source.length) {
      throw const FormatException('ssh binary reader out of bounds');
    }
  }
}

int _readUint32(Uint8List source, int offset) {
  return ByteData.sublistView(source, offset, offset + 4).getUint32(0);
}

String _readSshStringHead(Uint8List encoded) {
  if (encoded.length < 4) {
    return '';
  }
  final length = _readUint32(encoded, 0);
  if (length <= 0 || 4 + length > encoded.length) {
    return '';
  }
  final value = Uint8List.sublistView(encoded, 4, 4 + length);
  return utf8.decode(value, allowMalformed: true).trim();
}

Future<List<_OpenSshDirectiveRecord>> _loadOpenSshDirectiveRecords({
  List<String>? explicitConfigPaths,
}) async {
  final records = <_OpenSshDirectiveRecord>[];
  final visited = <String>{};
  final files = await _candidateOpenSshConfigFiles(
    explicitConfigPaths: explicitConfigPaths,
  );
  for (final filePath in files) {
    await _parseOpenSshConfigFile(
      filePath: filePath,
      hostPatterns: null,
      out: records,
      visited: visited,
    );
  }
  return records;
}

Future<void> _parseOpenSshConfigFile({
  required String filePath,
  required List<String>? hostPatterns,
  required List<_OpenSshDirectiveRecord> out,
  required Set<String> visited,
}) async {
  final file = File(filePath);
  if (!await file.exists()) {
    return;
  }
  final canonical = p.normalize(file.absolute.path);
  if (!visited.add(canonical)) {
    return;
  }

  var currentPatterns = hostPatterns;
  final lines = await file.readAsLines();
  for (final rawLine in lines) {
    final line = _stripInlineComment(rawLine).trim();
    if (line.isEmpty) {
      continue;
    }
    final parts = _splitDirective(line);
    if (parts == null) {
      continue;
    }
    final key = parts.$1;
    final value = parts.$2;
    if (key == 'host') {
      currentPatterns = _splitWords(value);
      continue;
    }
    if (key == 'match') {
      currentPatterns = const <String>[];
      continue;
    }
    if (currentPatterns != null && currentPatterns.isEmpty) {
      continue;
    }
    if (key == 'include') {
      final patterns = _splitWords(value);
      for (final includePath in patterns) {
        final resolved = await _expandIncludePaths(
          includePath,
          baseDirectory: p.dirname(file.path),
        );
        for (final item in resolved) {
          await _parseOpenSshConfigFile(
            filePath: item,
            hostPatterns: currentPatterns,
            out: out,
            visited: visited,
          );
        }
      }
      continue;
    }
    out.add(
      _OpenSshDirectiveRecord(
        hostPatterns: currentPatterns,
        key: key,
        value: value.trim(),
      ),
    );
  }
}

_OpenSshResolvedOptions? _resolveOpenSshHostOptions(
  List<_OpenSshDirectiveRecord> records, {
  required String target,
}) {
  final resolved = _OpenSshResolvedOptions();
  var touched = false;
  for (final record in records) {
    if (!_matchesHostPatterns(record.hostPatterns, target)) {
      continue;
    }
    touched = true;
    final value = _stripOuterQuotes(record.value.trim());
    switch (record.key) {
      case 'hostname':
        resolved.hostName ??= value;
      case 'user':
        resolved.user ??= value;
      case 'port':
        resolved.port ??= int.tryParse(value);
      case 'proxyjump':
        resolved.proxyJump ??= value;
      case 'connecttimeout':
        resolved.connectTimeoutSeconds ??= int.tryParse(value);
      case 'serveraliveinterval':
        resolved.serverAliveIntervalSeconds ??= int.tryParse(value);
      case 'identitiesonly':
        resolved.identitiesOnly ??= _parseOpenSshBool(value);
      case 'identityagent':
        resolved.identityAgent ??= value;
      case 'identityfile':
        resolved.identityFiles.add(value);
    }
  }
  return touched ? resolved : null;
}

Future<List<_KnownHostEntry>> _loadKnownHostEntries({
  List<String>? explicitKnownHostsPaths,
}) async {
  final files = await _candidateKnownHostsFiles(
    explicitKnownHostsPaths: explicitKnownHostsPaths,
  );
  final entries = <_KnownHostEntry>[];
  for (final filePath in files) {
    final file = File(filePath);
    if (!await file.exists()) {
      continue;
    }
    final lines = await file.readAsLines();
    for (final rawLine in lines) {
      final line = _stripInlineComment(rawLine).trim();
      if (line.isEmpty) {
        continue;
      }
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 3) {
        continue;
      }
      var offset = 0;
      if (parts[0].startsWith('@')) {
        if (parts.length < 4) {
          continue;
        }
        offset = 1;
      }
      final hostsField = parts[offset];
      if (hostsField.startsWith('|')) {
        continue;
      }
      final keyType = normalizeSshHostKeyType(parts[offset + 1]);
      final keyBlobRaw = parts[offset + 2];
      Uint8List keyBlob;
      try {
        keyBlob = base64Decode(keyBlobRaw);
      } catch (_) {
        continue;
      }
      final fingerprint = _md5Fingerprint(keyBlob);
      entries.add(
        _KnownHostEntry(
          hostsField: hostsField,
          keyType: keyType,
          fingerprint: fingerprint,
        ),
      );
    }
  }
  return entries;
}

String _md5Fingerprint(Uint8List keyBlob) {
  final bytes = md5.convert(keyBlob).bytes;
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
}

bool _matchesKnownHostsHostList(String hostsField, String host, int port) {
  final tokens = hostsField
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  if (tokens.isEmpty) {
    return false;
  }
  var positiveMatch = false;
  for (final token in tokens) {
    final negated = token.startsWith('!');
    final raw = negated ? token.substring(1) : token;
    if (_matchesKnownHostToken(raw, host, port)) {
      if (negated) {
        return false;
      }
      positiveMatch = true;
    }
  }
  return positiveMatch;
}

bool _matchesKnownHostToken(String token, String host, int port) {
  final trimmed = token.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  if (trimmed.startsWith('[')) {
    final close = trimmed.indexOf(']');
    if (close <= 1 || close + 2 > trimmed.length || trimmed[close + 1] != ':') {
      return false;
    }
    final hostPattern = trimmed.substring(1, close);
    final parsedPort = int.tryParse(trimmed.substring(close + 2));
    if (parsedPort == null || parsedPort != port) {
      return false;
    }
    return _matchesWildcardHostPattern(hostPattern, host);
  }
  if (port != 22) {
    return false;
  }
  return _matchesWildcardHostPattern(trimmed, host);
}

bool _matchesHostPatterns(List<String>? patterns, String target) {
  if (patterns == null || patterns.isEmpty) {
    return true;
  }
  var positiveMatch = false;
  for (final pattern in patterns) {
    final token = pattern.trim();
    if (token.isEmpty) {
      continue;
    }
    final negated = token.startsWith('!');
    final raw = negated ? token.substring(1) : token;
    if (_matchesWildcardHostPattern(raw, target)) {
      if (negated) {
        return false;
      }
      positiveMatch = true;
    }
  }
  return positiveMatch;
}

bool _matchesWildcardHostPattern(String pattern, String value) {
  final escaped = RegExp.escape(
    pattern,
  ).replaceAll(r'\*', '.*').replaceAll(r'\?', '.');
  final regex = RegExp('^$escaped\$', caseSensitive: false);
  return regex.hasMatch(value);
}

String _stripInlineComment(String line) {
  var inQuote = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      inQuote = !inQuote;
      continue;
    }
    if (!inQuote && ch == '#') {
      return line.substring(0, i);
    }
  }
  return line;
}

(String, String)? _splitDirective(String line) {
  final firstSpace = line.indexOf(RegExp(r'\s'));
  if (firstSpace <= 0) {
    return null;
  }
  final key = line.substring(0, firstSpace).trim().toLowerCase();
  final value = line.substring(firstSpace + 1).trim();
  if (key.isEmpty || value.isEmpty) {
    return null;
  }
  return (key, value);
}

List<String> _splitWords(String source) {
  final out = <String>[];
  final buffer = StringBuffer();
  var inQuote = false;
  for (var i = 0; i < source.length; i++) {
    final ch = source[i];
    if (ch == '"') {
      inQuote = !inQuote;
      continue;
    }
    if (!inQuote && RegExp(r'\s').hasMatch(ch)) {
      final item = buffer.toString().trim();
      if (item.isNotEmpty) {
        out.add(item);
      }
      buffer.clear();
      continue;
    }
    buffer.write(ch);
  }
  final tail = buffer.toString().trim();
  if (tail.isNotEmpty) {
    out.add(tail);
  }
  return out;
}

String _stripOuterQuotes(String value) {
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

bool _parseOpenSshBool(String value) {
  final raw = value.trim().toLowerCase();
  return raw == 'yes' || raw == 'true' || raw == 'on' || raw == '1';
}

Future<List<String>> _candidateOpenSshConfigFiles({
  List<String>? explicitConfigPaths,
}) async {
  if (explicitConfigPaths != null) {
    return explicitConfigPaths
        .map((it) => p.normalize(it))
        .toList(growable: false);
  }
  final home = _resolveHomeDirectory();
  final candidates = <String>[
    if (home.isNotEmpty) p.join(home, '.ssh', 'config'),
    if (Platform.isWindows)
      p.join(
        Platform.environment['ProgramData'] ?? r'C:\ProgramData',
        'ssh',
        'ssh_config',
      ),
    if (!Platform.isWindows) '/etc/ssh/ssh_config',
  ];
  return candidates.map((it) => p.normalize(it)).toList(growable: false);
}

Future<List<String>> _candidateKnownHostsFiles({
  List<String>? explicitKnownHostsPaths,
}) async {
  if (explicitKnownHostsPaths != null) {
    return explicitKnownHostsPaths
        .map((it) => p.normalize(it))
        .toList(growable: false);
  }
  final home = _resolveHomeDirectory();
  if (home.isEmpty) {
    return const <String>[];
  }
  return <String>[
    p.normalize(p.join(home, '.ssh', 'known_hosts')),
    p.normalize(p.join(home, '.ssh', 'known_hosts2')),
  ];
}

Future<List<String>> _expandIncludePaths(
  String rawPattern, {
  required String baseDirectory,
}) async {
  final home = _resolveHomeDirectory();
  var pattern = _expandOpenSshPath(
    rawPattern,
    home: home,
    host: '',
    user: '',
    port: 22,
  );
  if (!p.isAbsolute(pattern)) {
    pattern = p.normalize(p.join(baseDirectory, pattern));
  }
  final hasWildcard = pattern.contains('*') || pattern.contains('?');
  if (!hasWildcard) {
    return <String>[pattern];
  }
  final dir = Directory(p.dirname(pattern));
  if (!await dir.exists()) {
    return const <String>[];
  }
  final filePattern = p.basename(pattern);
  final entities = await dir.list(followLinks: false).toList();
  final matches = entities
      .whereType<File>()
      .where(
        (file) =>
            _matchesWildcardHostPattern(filePattern, p.basename(file.path)),
      )
      .map((file) => p.normalize(file.path))
      .toList(growable: false);
  return matches;
}

String _expandOpenSshPath(
  String raw, {
  required String home,
  required String host,
  required String user,
  required int port,
}) {
  var value = _stripOuterQuotes(raw.trim());
  if (value.startsWith('~')) {
    value = p.normalize(p.join(home, value.substring(1)));
  }
  value = value.replaceAll('%d', home);
  value = value.replaceAll('%h', host);
  value = value.replaceAll('%r', user);
  value = value.replaceAll('%p', '$port');
  return value;
}

String _resolveHomeDirectory() {
  final home =
      (Platform.environment['USERPROFILE'] ??
              Platform.environment['HOME'] ??
              '')
          .trim();
  return home;
}

bool _looksLikeWindowsNamedPipe(String path) {
  final normalized = path.trim().toLowerCase();
  return normalized.startsWith(r'\\.\pipe\');
}

JumpHostEntry? _legacyJumpHostFromConfig(String raw, String fallbackUsername) {
  if (raw.isEmpty) return null;
  var username = fallbackUsername;
  var hostPart = raw;
  final atIdx = raw.indexOf('@');
  if (atIdx > 0) {
    username = raw.substring(0, atIdx).trim();
    hostPart = raw.substring(atIdx + 1).trim();
  }
  if (hostPart.isEmpty) return null;
  var host = hostPart;
  var port = 22;
  if (hostPart.startsWith('[')) {
    final close = hostPart.indexOf(']');
    if (close > 1) {
      host = hostPart.substring(1, close);
      final remain = hostPart.substring(close + 1).trim();
      if (remain.startsWith(':')) {
        port = int.tryParse(remain.substring(1).trim()) ?? 22;
      }
    }
  } else {
    final firstColon = hostPart.indexOf(':');
    final lastColon = hostPart.lastIndexOf(':');
    if (firstColon > 0 && firstColon == lastColon) {
      host = hostPart.substring(0, firstColon).trim();
      port = int.tryParse(hostPart.substring(firstColon + 1).trim()) ?? 22;
    }
  }
  return JumpHostEntry(
    host: host,
    port: port.clamp(1, 65535),
    username: username != fallbackUsername ? username : null,
  );
}
