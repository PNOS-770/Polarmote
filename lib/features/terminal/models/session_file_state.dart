import 'package:flutter/foundation.dart';

import 'file_node.dart';

class SessionFileState {
  SessionFileState({required this.rootPath}) : currentPath = rootPath;

  String rootPath;
  String currentPath;
  String? homePath;
  String? forwardPath;
  final List<String> backStack = [];
  final List<String> forwardStack = [];
  final Map<String, List<FileNode>> directories = {};
  final Map<String, double> scrollOffsets = {};
  final Set<String> expanded = {};
  final Set<String> selected = {};
  final Set<String> loading = {};
  int version = 0;
  final ValueNotifier<int> selectionVersion = ValueNotifier(0);

  static const int _maxCachedDirectories = 50;

  void bumpSelection() {
    selectionVersion.value += 1;
  }

  void pruneDirectoryCache() {
    if (directories.length > _maxCachedDirectories) {
      final keysToKeep = <String>{
        currentPath,
        if (homePath != null) homePath!,
        ...backStack.take(10),
        ...forwardStack.take(10),
      };

      directories.removeWhere((key, value) => !keysToKeep.contains(key));
      scrollOffsets.removeWhere((key, value) => !keysToKeep.contains(key));
    }
  }

  void dispose() {
    directories.clear();
    scrollOffsets.clear();
    expanded.clear();
    selected.clear();
    loading.clear();
    backStack.clear();
    forwardStack.clear();
    selectionVersion.dispose();
  }
}

