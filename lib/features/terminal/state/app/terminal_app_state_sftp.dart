import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../shared/logging/Polarmote_log.dart';
import '../../../../shared/constants/app_string.dart';
import '../../models/file_node.dart';
import '../../models/terminal_session.dart';
import '../../models/terminal_tab.dart';
import '../diagnostics/path_error_diagnostics.dart';
import '../terminal_app_state.dart';

part 'terminal_app_state_sftp_paths.dart';

extension TerminalAppStateSftp on TerminalAppState {
  void _startCurrentDirectoryAutoRefresh(TerminalSession session) {
    session.fileTreeRefreshTimer?.cancel();
    session.fileTreeRefreshTimer = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) {
      if (!sessions.contains(session)) {
        timer.cancel();
        return;
      }
      // navSection 检查已移除 - 不再需要检查当前导航区域
      if (activeSession != session) {
        return;
      }
      if ((!session.profile.isLocal && session.sftp == null) ||
          session.tab.status != TerminalStatus.connected ||
          session.transferCancelRequested) {
        return;
      }
      final path = session.fileState.currentPath.isNotEmpty
          ? session.fileState.currentPath
          : session.fileState.rootPath;
      if (path.isEmpty) return;
      unawaited(refreshDirectory(session, path));
    });
  }

  Future<void> ensureSftpReady(TerminalSession session) async {
    if (session.profile.isLocal) {
      try {
        final homePath = await _resolveLocalHomePath();
        session.fileState.rootPath = Platform.isAndroid ? '/' : homePath;
        session.fileState.homePath = homePath;
        session.fileState.currentPath = homePath;
        session.fileState.directories.clear();
        session.fileState.expanded.clear();
        session.fileState.selected.clear();
        session.fileState.backStack.clear();
        session.fileState.forwardStack.clear();
        _bumpFileTreeVersion(session);
        await loadDirectory(session, homePath, force: true);
        _expandToPath(session, homePath);
        _startCurrentDirectoryAutoRefresh(session);
        notifyState();
      } catch (e) {
        setError(
          AppStrings.values.failedToInitSftpVar.resolve(
            locale.languageCode,
            params: {'error': '$e'},
          ),
        );
      }
      return;
    }
    if (session.sftp != null) return;
    final client = session.client;
    if (client == null) return;
    try {
      final sftp = await client.sftp();
      session.sftp = sftp;
      final homePath = await sftp.absolute('.');
      String rootPath;
      try {
        rootPath = await sftp.absolute('/');
      } catch (_) {
        rootPath = parentOf(homePath);
      }
      rootPath = rootPath.isEmpty ? '/' : rootPath;
      rootPath = await _resolveAccessibleRoot(sftp, homePath, rootPath);
      session.fileState.rootPath = rootPath;
      session.fileState.homePath = homePath.isEmpty
          ? session.fileState.rootPath
          : homePath;
      session.fileState.currentPath = session.fileState.homePath!;
      session.fileState.directories.clear();
      session.fileState.expanded.clear();
      session.fileState.selected.clear();
      session.fileState.backStack.clear();
      session.fileState.forwardStack.clear();
      _bumpFileTreeVersion(session);
      await loadDirectory(session, session.fileState.rootPath, force: true);
      if (session.fileState.currentPath != session.fileState.rootPath) {
        await loadDirectory(
          session,
          session.fileState.currentPath,
          force: true,
        );
        _expandToPath(session, session.fileState.currentPath);
        _bumpFileTreeVersion(session);
      }
      _startCurrentDirectoryAutoRefresh(session);
      notifyState();
    } catch (e) {
      setError(
        AppStrings.values.failedToInitSftpVar.resolve(
          locale.languageCode,
          params: {'error': '$e'},
        ),
      );
    }
  }

  Future<void> loadDirectory(
    TerminalSession session,
    String path, {
    bool force = false,
  }) async {
    final normalizedPath = _normalizePathForSession(session, path);
    if (normalizedPath.isEmpty) return;
    if (!force && session.fileState.directories.containsKey(normalizedPath)) {
      return;
    }
    if (session.fileState.loading.contains(normalizedPath)) return;
    final sftp = session.sftp;
    if (!session.profile.isLocal && sftp == null) return;

    session.fileState.loading.add(normalizedPath);
    notifyState();
    try {
      final entries = <FileNode>[];
      if (session.profile.isLocal) {
        if (Platform.isAndroid) {
          entries.addAll(await _listLocalDirectoryByShell(normalizedPath));
        } else {
          final directory = Directory(normalizedPath);
          await for (final entity in directory.list(followLinks: false)) {
            final name = p.basename(entity.path);
            if (name == '.' || name == '..') continue;
            FileStat stat;
            try {
              stat = await entity.stat();
            } catch (_) {
              continue;
            }
            final isDir = stat.type == FileSystemEntityType.directory;
            entries.add(
              FileNode(
                name: name,
                path: p.normalize(entity.path),
                isDirectory: isDir,
                size: isDir ? null : stat.size,
                modified: stat.modified,
              ),
            );
          }
        }
      } else {
        final names = await sftp!.listdir(normalizedPath);
        for (final name in names) {
          if (name.filename == '.' || name.filename == '..') continue;
          final attrs = name.attr;
          final isDir = attrs.isDirectory;
          final fullPath = joinRemote(normalizedPath, name.filename);
          entries.add(
            FileNode(
              name: name.filename,
              path: fullPath,
              isDirectory: isDir,
              size: attrs.size,
              modified: attrs.modifyTime == null
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(
                      attrs.modifyTime! * 1000,
                    ),
              ownerId: attrs.userID,
              groupId: attrs.groupID,
              permissions: attrs.mode?.value,
            ),
          );
        }
      }
      entries.sort((a, b) {
        if (a.isDirectory != b.isDirectory) {
          return a.isDirectory ? -1 : 1;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      session.fileState.directories[normalizedPath] = entries;
      session.fileState.pruneDirectoryCache(); // 清理过多的缓存
      _bumpFileTreeVersion(session);
    } catch (e) {
      if (_isExpectedSftpDisconnectError(session, e)) {
        return;
      }
      if (_isNoSuchDirectoryError(e)) {
        _handleMissingDirectory(session, normalizedPath);
        return;
      }
      final diagnostic = diagnosePathError(
        e,
        path: normalizedPath,
        preferAndroidRestricted:
            session.profile.isLocal &&
            Platform.isAndroid &&
            normalizedPath.startsWith('/'),
      );
      if (diagnostic.kind == PathErrorKind.restricted) {
        setError(
          AppStrings.values.androidDirectoryRestrictedNoRoot.resolve(
            locale.languageCode,
          ),
        );
        return;
      }
      final operation = AppStrings.values.readDirectory.resolve(locale.languageCode);
      setError(
        formatPathError(
          diagnostic,
          languageCode: locale.languageCode,
          operation: operation,
          path: normalizedPath,
        ),
      );
    } finally {
      session.fileState.loading.remove(normalizedPath);
      notifyState();
    }
  }

  Future<void> refreshDirectory(TerminalSession session, String path) async {
    await loadDirectory(session, path, force: true);
  }

  bool _isNoSuchDirectoryError(Object error) {
    return diagnosePathError(error).kind == PathErrorKind.notFound;
  }

  bool _isExpectedSftpDisconnectError(TerminalSession session, Object error) {
    if (session.profile.isLocal) return false;
    if (session.closedByUser) return true;
    if (session.tab.status != TerminalStatus.connected) return true;
    if (!sessions.contains(session)) return true;

    final text = '$error'.toLowerCase();
    if (text.contains('sftpaborterror') && text.contains('connection closed')) {
      return true;
    }
    if (text.contains('connection closed')) {
      return true;
    }
    return false;
  }

  bool _isSameOrChildPath(
    TerminalSession session,
    String path,
    String parentPath,
  ) {
    final normalizedPath = _normalizePathForCompare(session, path);
    final normalizedParent = _normalizePathForCompare(session, parentPath);
    if (normalizedPath == normalizedParent) return true;
    if (normalizedParent.isEmpty) {
      return false;
    }
    if (normalizedParent == '/') {
      return normalizedPath.startsWith('/');
    }
    return normalizedPath.startsWith('$normalizedParent/');
  }

  void _handleMissingDirectory(TerminalSession session, String missingPath) {
    final normalizedMissing = _normalizePathForSession(session, missingPath);
    session.fileState.directories.removeWhere(
      (key, value) => _isSameOrChildPath(session, key, normalizedMissing),
    );
    session.fileState.expanded.removeWhere(
      (path) => _isSameOrChildPath(session, path, normalizedMissing),
    );
    session.fileState.selected.removeWhere(
      (path) => _isSameOrChildPath(session, path, normalizedMissing),
    );
    _bumpFileTreeVersion(session);
    notifyState();
    final currentPath = session.fileState.currentPath;
    if (!_isSameOrChildPath(session, currentPath, normalizedMissing)) {
      return;
    }
    unawaited(_recoverCurrentPathAfterMissing(session, normalizedMissing));
  }

  Future<void> _recoverCurrentPathAfterMissing(
    TerminalSession session,
    String missingPath,
  ) async {
    final fallback = await _findNearestExistingDirectory(
      session,
      _parentPathForSession(session, missingPath),
    );
    if (!sessions.contains(session)) return;
    session.fileState.currentPath = fallback;
    session.fileState.forwardPath = null;
    await loadDirectory(session, fallback, force: true);
    _expandToPath(session, fallback);
    _bumpFileTreeVersion(session);
    notifyState();
  }

  Future<String> _findNearestExistingDirectory(
    TerminalSession session,
    String startPath,
  ) async {
    final sftp = session.sftp;
    var current = _normalizePathForSession(session, startPath);
    if (current.isEmpty) {
      current = session.fileState.homePath ?? session.fileState.rootPath;
    }
    if (current.isEmpty) {
      current = session.profile.isLocal ? await _resolveLocalHomePath() : '/';
    }
    final visited = <String>{};
    while (visited.add(current)) {
      if (session.profile.isLocal) {
        if (await Directory(current).exists()) {
          return current;
        }
      } else {
        if (sftp == null) {
          return current;
        }
        try {
          await sftp.listdir(current);
          return current;
        } catch (e) {
          if (!_isNoSuchDirectoryError(e)) {
            break;
          }
        }
      }
      final parent = _parentPathForSession(session, current);
      if (parent == current || parent.isEmpty) {
        break;
      }
      current = parent;
    }
    final home = _normalizePathForSession(
      session,
      session.fileState.homePath ?? '',
    );
    if (home.isNotEmpty && home != '/') {
      if (session.profile.isLocal) {
        if (await Directory(home).exists()) {
          return home;
        }
      } else {
        try {
          await sftp?.listdir(home);
          return home;
        } catch (e) { PolarmoteLog.error('terminal_app_state_sftp', '$e'); }
      }
    }
    final root = _normalizePathForSession(session, session.fileState.rootPath);
    if (root.isNotEmpty) {
      if (session.profile.isLocal) {
        if (await Directory(root).exists()) {
          return root;
        }
      } else {
        try {
          await sftp?.listdir(root);
          return root;
        } catch (e) { PolarmoteLog.error('terminal_app_state_sftp', '$e'); }
      }
      return root;
    }
    if (session.profile.isLocal) {
      return await _resolveLocalHomePath();
    }
    return '/';
  }

  void toggleExpanded(TerminalSession session, String path) {
    if (session.fileState.expanded.contains(path)) {
      session.fileState.expanded.remove(path);
    } else {
      session.fileState.expanded.add(path);
      if (!session.fileState.directories.containsKey(path)) {
        unawaited(loadDirectory(session, path));
      }
    }
    _bumpFileTreeVersion(session);
    notifyState();
  }

  void toggleFileSelection(
    TerminalSession session,
    String path, {
    bool multi = false,
    bool isDirectory = false,
  }) {
    if (multi) {
      if (session.fileState.selected.contains(path)) {
        session.fileState.selected.remove(path);
      } else {
        session.fileState.selected.add(path);
      }
    } else {
      session.fileState.selected
        ..clear()
        ..add(path);
    }
    session.fileState.bumpSelection();
  }

  void clearFileSelection(TerminalSession session) {
    session.fileState.selected.clear();
    session.fileState.bumpSelection();
  }

  Future<void> createDirectory(
    TerminalSession session,
    String parentPath,
    String name,
  ) async {
    final sftp = session.sftp;
    if (!session.profile.isLocal && sftp == null) return;
    try {
      final parent = _normalizePathForSession(session, parentPath);
      if (parent.isEmpty) return;
      final path = _joinPathForSession(session, parent, name);
      if (session.profile.isLocal) {
        await Directory(path).create(recursive: false);
      } else {
        await sftp!.mkdir(path);
      }
      await refreshDirectory(session, parentPath);
    } catch (e) {
      final operation = AppStrings.values.createFolder.resolve(locale.languageCode);
      setError(
        formatPathError(
          diagnosePathError(
            e,
            path: parentPath,
            preferAndroidRestricted:
                session.profile.isLocal && Platform.isAndroid,
          ),
          languageCode: locale.languageCode,
          operation: operation,
          path: parentPath,
        ),
      );
    }
  }

  Future<void> createFile(
    TerminalSession session,
    String parentPath,
    String name,
  ) async {
    final sftp = session.sftp;
    if (!session.profile.isLocal && sftp == null) return;
    try {
      final parent = _normalizePathForSession(session, parentPath);
      if (parent.isEmpty) return;
      final path = _joinPathForSession(session, parent, name);
      if (session.profile.isLocal) {
        await File(path).create(recursive: false);
      } else {
        final file = await sftp!.open(
          path,
          mode:
              SftpFileOpenMode.write |
              SftpFileOpenMode.create |
              SftpFileOpenMode.truncate,
        );
        await file.close();
      }
      await refreshDirectory(session, parentPath);
    } catch (e) {
      final operation = AppStrings.values.createFile.resolve(locale.languageCode);
      setError(
        formatPathError(
          diagnosePathError(
            e,
            path: parentPath,
            preferAndroidRestricted:
                session.profile.isLocal && Platform.isAndroid,
          ),
          languageCode: locale.languageCode,
          operation: operation,
          path: parentPath,
        ),
      );
    }
  }

  Future<void> renameEntry(
    TerminalSession session,
    String oldPath,
    String newName,
  ) async {
    final sftp = session.sftp;
    if (!session.profile.isLocal && sftp == null) return;
    try {
      final oldNormalized = _normalizePathForSession(session, oldPath);
      if (oldNormalized.isEmpty) return;
      final parent = _parentPathForSession(session, oldNormalized);
      final newPath = _joinPathForSession(session, parent, newName);
      if (session.profile.isLocal) {
        final stat = await FileSystemEntity.type(oldNormalized);
        if (stat == FileSystemEntityType.directory) {
          await Directory(oldNormalized).rename(newPath);
        } else {
          await File(oldNormalized).rename(newPath);
        }
      } else {
        await sftp!.rename(oldNormalized, newPath);
      }
      await refreshDirectory(session, parent);
    } catch (e) {
      final operation = AppStrings.values.renameFile.resolve(locale.languageCode);
      setError(
        formatPathError(
          diagnosePathError(
            e,
            path: oldPath,
            preferAndroidRestricted:
                session.profile.isLocal && Platform.isAndroid,
          ),
          languageCode: locale.languageCode,
          operation: operation,
          path: oldPath,
        ),
      );
    }
  }

  Future<void> deleteEntry(TerminalSession session, FileNode node) async {
    final sftp = session.sftp;
    if (!session.profile.isLocal && sftp == null) return;
    try {
      if (session.profile.isLocal) {
        if (node.isDirectory) {
          await Directory(node.path).delete(recursive: true);
        } else {
          await File(node.path).delete();
        }
      } else {
        if (node.isDirectory) {
          final ok = await _deleteDirectoryByShell(session, node.path);
          if (!ok) {
            throw StateError(
              AppStrings.values.rmRfFailed.resolve(locale.languageCode),
            );
          }
        } else {
          await sftp!.remove(node.path);
        }
      }
      await refreshDirectory(
        session,
        _parentPathForSession(session, node.path),
      );
      session.fileState.selected.remove(node.path);
      _bumpFileTreeVersion(session);
      notifyState();
    } catch (e) {
      final operation = AppStrings.values.deleteFile.resolve(locale.languageCode);
      setError(
        formatPathError(
          diagnosePathError(
            e,
            path: node.path,
            preferAndroidRestricted:
                session.profile.isLocal && Platform.isAndroid,
          ),
          languageCode: locale.languageCode,
          operation: operation,
          path: node.path,
        ),
      );
    }
  }

  Future<void> deleteEntries(
    TerminalSession session,
    List<FileNode> nodes,
  ) async {
    if (nodes.isEmpty) return;
    for (final node in nodes) {
      await deleteEntry(session, node);
    }
  }

  Future<bool> _deleteDirectoryByShell(
    TerminalSession session,
    String path,
  ) async {
    final client = session.client;
    if (client == null) return false;
    if (!_isSafeDeletePath(session, path)) {
      setError(
        AppStrings.values.refuseToDeleteUnsafePath.resolve(locale.languageCode),
      );
      return false;
    }
    final escaped = _escapeForShell(path);
    try {
      await client.run(
        "sh -c 'rm -rf -- $escaped'",
        stdout: false,
        stderr: false,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  String _escapeForShell(String value) {
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }

  bool _isSafeDeletePath(TerminalSession session, String path) {
    var normalized = path.replaceAll('\\', '/').trim();
    if (normalized.isEmpty) return false;
    if (!normalized.startsWith('/')) {
      normalized = '/$normalized';
    }
    if (normalized == '/' || normalized == '/.' || normalized == '/..') {
      return false;
    }
    final parts = normalized.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.contains('..')) return false;
    final homePath = session.fileState.homePath ?? '';
    final rootPath = session.fileState.rootPath;
    if (homePath.isNotEmpty) {
      if (normalized == homePath) return false;
      return normalized.startsWith('$homePath/');
    }
    if (rootPath.isNotEmpty && rootPath != '/') {
      if (normalized == rootPath) return false;
      return normalized.startsWith('$rootPath/');
    }
    // As last resort, refuse to delete shallow paths like /var or /home.
    return parts.length >= 2;
  }

  void _expandToPath(TerminalSession session, String path) {
    if (session.profile.isLocal) {
      final normalized = _normalizePathForSession(session, path);
      if (normalized.isEmpty) return;
      var current = normalized;
      while (true) {
        session.fileState.expanded.add(current);
        final parent = _parentPathForSession(session, current);
        if (parent == current || parent.isEmpty) break;
        current = parent;
      }
      return;
    }
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    var current = normalized.startsWith('/') ? '/' : '';
    for (final part in parts) {
      current = current == '/' ? '/$part' : '$current/$part';
      session.fileState.expanded.add(current);
      if (!session.fileState.directories.containsKey(current)) {
        unawaited(loadDirectory(session, current));
      }
    }
  }

  Future<void> navigateToPath(
    TerminalSession session,
    String path, {
    bool addToHistory = true,
    bool preserveForward = false,
  }) async {
    final normalized = _normalizePathForSession(session, path);
    if (normalized.isEmpty) return;
    if (!preserveForward) {
      session.fileState.forwardPath = null;
    }
    session.fileState.currentPath = normalized;
    session.fileState.selected.clear();
    await loadDirectory(session, normalized, force: false);
    _expandToPath(session, normalized);
    _bumpFileTreeVersion(session);
    _startCurrentDirectoryAutoRefresh(session);
    notifyState();
  }

  void _bumpFileTreeVersion(TerminalSession session) {
    session.fileState.version += 1;
  }

  Future<String> _resolveAccessibleRoot(
    SftpClient sftp,
    String homePath,
    String rootPath,
  ) async {
    var best = rootPath;
    var current = rootPath;
    if (homePath.isNotEmpty) {
      final parent = parentOf(homePath);
      if (parent.isNotEmpty && parent != homePath) {
        current = parent;
      }
    }
    for (var i = 0; i < 4; i++) {
      if (current.isEmpty) break;
      if (current == best) {
        final parent = parentOf(current);
        if (parent == current) break;
        current = parent;
        continue;
      }
      try {
        await sftp.listdir(current);
        best = current;
      } catch (_) {
        break;
      }
      if (current == '/') break;
      final parent = parentOf(current);
      if (parent == current) break;
      current = parent;
    }
    return best;
  }

  Future<String> _resolveLocalHomePath() async {
    if (Platform.isAndroid) {
      final androidCandidates = <String>[];
      final externalStorageEnv = Platform.environment['EXTERNAL_STORAGE'];
      if (externalStorageEnv != null && externalStorageEnv.trim().isNotEmpty) {
        androidCandidates.add(externalStorageEnv.trim());
      }
      androidCandidates.addAll(const <String>[
        '/storage/emulated/0',
        '/sdcard',
        '/storage/self/primary',
      ]);

      try {
        final primary = await getExternalStorageDirectory();
        if (primary != null) {
          androidCandidates.add(primary.path);
          final sharedRoot = _androidSharedStorageRootFromPath(primary.path);
          if (sharedRoot.isNotEmpty) {
            androidCandidates.add(sharedRoot);
          }
        }
      } catch (e) { PolarmoteLog.error('terminal_app_state_sftp', '$e'); }

      try {
        final externals = await getExternalStorageDirectories();
        if (externals != null) {
          for (final dir in externals) {
            androidCandidates.add(dir.path);
            final sharedRoot = _androidSharedStorageRootFromPath(dir.path);
            if (sharedRoot.isNotEmpty) {
              androidCandidates.add(sharedRoot);
            }
          }
        }
      } catch (e) { PolarmoteLog.error('terminal_app_state_sftp', '$e'); }

      for (final candidate in androidCandidates) {
        final normalized = p.normalize(candidate);
        if (normalized.isEmpty || normalized == '/') continue;
        if (await _canReadLocalDirectory(normalized)) {
          return normalized;
        }
      }
    }

    final candidates = <String>[];
    final home = Platform.environment['HOME'];
    final userProfile = Platform.environment['USERPROFILE'];
    final homeDrive = Platform.environment['HOMEDRIVE'];
    final homePath = Platform.environment['HOMEPATH'];
    if (userProfile != null && userProfile.isNotEmpty) {
      candidates.add(userProfile);
    }
    if (homeDrive != null &&
        homeDrive.isNotEmpty &&
        homePath != null &&
        homePath.isNotEmpty) {
      candidates.add('$homeDrive$homePath');
    }
    if (home != null && home.isNotEmpty) {
      candidates.add(home);
    }
    candidates.add(Directory.current.path);
    for (final candidate in candidates) {
      final normalized = p.normalize(candidate);
      if (normalized.isEmpty || (Platform.isAndroid && normalized == '/')) {
        continue;
      }
      if (await _canReadLocalDirectory(normalized)) {
        return normalized;
      }
    }
    return p.normalize(Directory.current.path);
  }

  String _androidSharedStorageRootFromPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    const marker = '/Android/';
    final markerIndex = normalized.indexOf(marker);
    if (markerIndex <= 0) {
      return '';
    }
    return normalized.substring(0, markerIndex);
  }

  Future<bool> _canReadLocalDirectory(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        return false;
      }
      await dir.list(followLinks: false).take(1).drain<void>();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<FileNode>> _listLocalDirectoryByShell(String dirPath) async {
    final shell = File('/system/bin/sh').existsSync() ? '/system/bin/sh' : 'sh';
    final escapedPath = jsonEncode(dirPath);
    final script =
        '''
set +e
dir=$escapedPath
for entry in "\$dir"/* "\$dir"/.*; do
  [ -e "\$entry" ] || continue
  name=\${entry##*/}
  [ "\$name" = "." ] && continue
  [ "\$name" = ".." ] && continue
  if [ -d "\$entry" ]; then
    type="d"
  else
    type="f"
  fi
  size=""
  if [ "\$type" = "f" ]; then
    size=\$(wc -c < "\$entry" 2>/dev/null || true)
  fi
  printf '%s\\t%s\\t%s\\n' "\$type" "\$entry" "\$size"
done
''';

    final result = await Process.run(shell, ['-c', script]);
    if (result.exitCode != 0) {
      throw FileSystemException(
        'Android shell fallback failed',
        dirPath,
        OSError(result.stderr?.toString().trim() ?? 'exit ${result.exitCode}'),
      );
    }

    final output = result.stdout?.toString() ?? '';
    final nodes = <FileNode>[];
    for (final rawLine in const LineSplitter().convert(output)) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final parts = line.split('\t');
      if (parts.length < 2) continue;
      final type = parts[0];
      final fullPath = p.normalize(parts[1]);
      final name = p.basename(fullPath);
      if (name == '.' || name == '..') continue;
      final isDirectory = type == 'd';
      final size = !isDirectory && parts.length >= 3
          ? int.tryParse(parts[2].trim())
          : null;
      nodes.add(
        FileNode(
          name: name,
          path: fullPath,
          isDirectory: isDirectory,
          size: size,
          modified: null,
        ),
      );
    }
    return nodes;
  }
}


