part of 'terminal_app_state_sftp.dart';

extension TerminalAppStateSftpPaths on TerminalAppState {
  bool canGoBack(TerminalSession session) {
    final current = session.fileState.currentPath.isNotEmpty
        ? session.fileState.currentPath
        : session.fileState.rootPath;
    final parent = _parentPathForSession(session, current);
    return parent != current;
  }

  bool canGoForward(TerminalSession session) =>
      session.fileState.forwardPath != null;

  Future<void> goBack(TerminalSession session) async {
    final current = session.fileState.currentPath.isNotEmpty
        ? session.fileState.currentPath
        : session.fileState.rootPath;
    final parent = _parentPathForSession(session, current);
    if (parent == current) return;
    session.fileState.forwardPath = current;
    await navigateToPath(session, parent, addToHistory: false, preserveForward: true);
  }

  Future<void> goForward(TerminalSession session) async {
    final target = session.fileState.forwardPath;
    if (target == null || target.isEmpty) return;
    session.fileState.forwardPath = null;
    await navigateToPath(session, target, addToHistory: false, preserveForward: true);
  }

  String _normalizePath(String path) {
    final normalized = path.replaceAll('\\', '/').trim();
    if (normalized.isEmpty) return '';
    if (normalized.startsWith('/')) return normalized;
    return '/$normalized';
  }

  String _normalizePathForSession(TerminalSession session, String path) {
    if (!session.profile.isLocal) return _normalizePath(path);
    final trimmed = path.trim();
    if (trimmed.isEmpty) return '';
    var candidate = trimmed;
    if (candidate == '~') candidate = session.fileState.homePath ?? '';
    else if (candidate.startsWith('~/') || candidate.startsWith('~\\')) {
      final home = session.fileState.homePath ?? '';
      if (home.isNotEmpty) candidate = p.join(home, candidate.substring(2));
    }
    if (!p.isAbsolute(candidate)) {
      final base = session.fileState.currentPath.isNotEmpty
          ? session.fileState.currentPath
          : session.fileState.rootPath;
      candidate = p.join(base, candidate);
    }
    return p.normalize(candidate);
  }

  String _joinPathForSession(TerminalSession session, String parent, String child) {
    if (!session.profile.isLocal) return joinRemote(parent, child);
    return p.normalize(p.join(parent, child));
  }

  String _parentPathForSession(TerminalSession session, String path) {
    if (!session.profile.isLocal) return parentOf(path);
    final normalized = _normalizePathForSession(session, path);
    if (normalized.isEmpty) return '';
    final parent = p.dirname(normalized);
    if (parent == '.' || parent.isEmpty) return normalized;
    return p.normalize(parent);
  }

  String _normalizePathForCompare(TerminalSession session, String path) {
    if (!session.profile.isLocal) {
      var normalized = _normalizePath(path);
      while (normalized.length > 1 && normalized.endsWith('/')) normalized = normalized.substring(0, normalized.length - 1);
      return normalized;
    }
    var normalized = _normalizePathForSession(session, path);
    normalized = normalized.replaceAll('\\', '/');
    while (normalized.length > 1 && normalized.endsWith('/')) normalized = normalized.substring(0, normalized.length - 1);
    if (Platform.isWindows) normalized = normalized.toLowerCase();
    return normalized;
  }
}

