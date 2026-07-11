import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:safe_layout_x/utils/platform.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../../../../shared/constants/app_string.dart';
import '../../../../shared/design_system/design_system.dart';
import '../../models/file_node.dart';
import '../../models/terminal_session.dart';
import '../../models/terminal_tab.dart';
import '../../state/terminal_app_state.dart';
import '../common/terminal_formatters.dart';
import '../common/terminal_localization.dart';
import '../common/terminal_ui_palette.dart';
import '../dialogs/terminal_dialogs.dart';
import '../file_viewer/file_open_controller.dart';
import 'file_icon_resolver.dart';
import '../panels/terminal_home_panels.dart';

part 'terminal_file_tree_sections.dart';

const _remoteFileTreeDragLocalDataTag = 'terminal.remote_file_tree_drag';
const _fileTreeMinNameWidth = 180.0;
const _fileTreeModifiedColWidth = 152.0;
const _fileTreePermissionsColWidth = 120.0;
const _fileTreeSizeColWidth = 88.0;
const _fileTreeOwnerColWidth = 88.0;
const _fileTreeGroupColWidth = 88.0;
const _fileTreeColumnGapWidth = 10.0;
const _fileTreeLeadingWidth = 51.0;
const _fileTreeTrailingWidth = 6.0;
const _fileTreeNodeIconWidth = 15.0;
const _fileTreeColumnsContentWidth =
    _fileTreeMinNameWidth +
    _fileTreeSizeColWidth +
    _fileTreeColumnGapWidth +
    _fileTreeModifiedColWidth +
    _fileTreeColumnGapWidth +
    _fileTreePermissionsColWidth +
    _fileTreeColumnGapWidth +
    _fileTreeOwnerColWidth +
    _fileTreeColumnGapWidth +
    _fileTreeGroupColWidth;

class _FileTreeColumnLayout {
  const _FileTreeColumnLayout({
    required this.sizeWidth,
    required this.modifiedWidth,
    required this.permissionsWidth,
    required this.ownerWidth,
    required this.groupWidth,
    required this.gapAfterSize,
    required this.gapAfterModified,
    required this.gapAfterPermissions,
    required this.gapAfterOwner,
  });

  final double sizeWidth;
  bool get hasSize => sizeWidth > 0;
  final double modifiedWidth;
  final double permissionsWidth;
  final double ownerWidth;
  final double groupWidth;
  final double gapAfterSize;
  final double gapAfterModified;
  final double gapAfterPermissions;
  final double gapAfterOwner;

  bool get hasModified => modifiedWidth > 0;
  bool get hasPermissions => permissionsWidth > 0;
  bool get hasOwner => ownerWidth > 0;
  bool get hasGroup => groupWidth > 0;
}

_FileTreeColumnLayout _computeFileTreeColumnLayout(double maxWidth) {
  return const _FileTreeColumnLayout(
    sizeWidth: _fileTreeSizeColWidth,
    modifiedWidth: _fileTreeModifiedColWidth,
    permissionsWidth: _fileTreePermissionsColWidth,
    ownerWidth: _fileTreeOwnerColWidth,
    groupWidth: _fileTreeGroupColWidth,
    gapAfterSize: _fileTreeColumnGapWidth,
    gapAfterModified: _fileTreeColumnGapWidth,
    gapAfterPermissions: _fileTreeColumnGapWidth,
    gapAfterOwner: _fileTreeColumnGapWidth,
  );
}

enum _ModifiedSortOrder { none, desc, asc }

class FileTree extends StatefulWidget {
  const FileTree({
    required this.appState,
    required this.session,
    required this.showHidden,
  });

  final TerminalAppState appState;
  final TerminalSession? session;
  final bool showHidden;

  @override
  State<FileTree> createState() => FileTreeState();
}

class FileTreeState extends State<FileTree> {
  static const double _rowHeight = 32;
  static const double _listVerticalPadding = 0;
  final ScrollController _scrollController = ScrollController();
  final ScrollController _horizontalController = ScrollController();
  final GlobalKey _listKey = GlobalKey();
  String? _lastScrollRestoreToken;
  PointerRoute? _globalPointerRoute;
  _ModifiedSortOrder _modifiedSortOrder = _ModifiedSortOrder.none;
  String _nameFilterQuery = '';

  bool _isMultiSelectPressed() {
    return HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
  }

  List<FileNode> _selectedNodesForEntries(
    TerminalSession session,
    List<FileNode> entries,
  ) {
    final selected = session.fileState.selected;
    if (selected.isEmpty) {
      return const [];
    }
    return entries
        .where((entry) => selected.contains(entry.path))
        .toList(growable: false);
  }

  bool _isPositionOnFileRow(Offset globalPosition, List<FileNode> entries) {
    if (entries.isEmpty) return false;
    final renderBox = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return false;
    final local = renderBox.globalToLocal(globalPosition);
    if (local.dx < 0 ||
        local.dy < 0 ||
        local.dx > renderBox.size.width ||
        local.dy > renderBox.size.height) {
      return false;
    }
    final scrollOffset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    final contentY = (local.dy - _listVerticalPadding) + scrollOffset;
    if (contentY < 0) return false;
    final index = (contentY / _rowHeight).floor();
    return index >= 0 && index < entries.length;
  }

  List<FileNode> _currentVisibleEntries(TerminalSession session) {
    final rootPath = session.fileState.rootPath;
    final currentPath = session.fileState.currentPath.isNotEmpty
        ? session.fileState.currentPath
        : rootPath;
    final nodes = session.fileState.directories[currentPath];
    if (nodes == null) {
      return const [];
    }
    final showHidden = widget.showHidden;
    return nodes
        .where((node) {
          if (!showHidden && node.name.startsWith('.')) return false;
          return _matchesNameFilter(node);
        })
        .toList(growable: false);
  }

  bool _matchesNameFilter(FileNode node) {
    final query = _nameFilterQuery.trim();
    if (query.isEmpty) {
      return true;
    }
    final lowerQuery = query.toLowerCase();
    final nameLower = node.name.toLowerCase();
    final pathLower = node.path.toLowerCase();
    if (nameLower.contains(lowerQuery) || pathLower.contains(lowerQuery)) {
      return true;
    }
    if (query.contains('/')) {
      final parts = query.split('/').where((p) => p.isNotEmpty).toList();
      if (parts.isNotEmpty) {
        final lastPart = parts.last.toLowerCase();
        if (node.isDirectory && nameLower.contains(lastPart)) {
          return true;
        }
      }
    }
    return false;
  }

  void _handleGlobalPointerEvent(PointerEvent event) {
    if (event is! PointerDownEvent) {
      return;
    }
    if (event.buttons & kPrimaryButton == 0) {
      return;
    }
    final session = widget.session;
    if (session == null || session.fileState.selected.isEmpty) {
      return;
    }
    final entries = _currentVisibleEntries(session);
    final clickedRow = _isPositionOnFileRow(event.position, entries);
    if (!clickedRow) {
      widget.appState.clearFileSelection(session);
    }
  }

  bool _isAcceptedDrop(DropOperation? operation) {
    if (operation == null) return false;
    return operation != DropOperation.none &&
        operation != DropOperation.forbidden &&
        operation != DropOperation.userCancelled;
  }

  Future<void> _uploadFromSystemPicker(
    TerminalAppState appState,
    TerminalSession session,
    String rootPath,
  ) async {
    try {
      final files = await openFiles();
      final (localPaths, cleanupTempPaths) = await _resolveUploadLocalPaths(
        files,
      );
      if (localPaths.isEmpty) {
        return;
      }
      final targetDir = session.fileState.currentPath.isNotEmpty
          ? session.fileState.currentPath
          : rootPath;
      try {
        await appState.uploadFiles(session, localPaths, targetDir);
      } finally {
        unawaited(_cleanupTempUploadFiles(cleanupTempPaths));
      }
    } catch (error) {
      appState.setError(
        AppStrings.values.failedToOpenLocalFileVar.resolve(
          appState.locale.languageCode,
          params: {'error': '$error'},
        ),
      );
    }
  }

  Future<(List<String>, List<String>)> _resolveUploadLocalPaths(
    List<XFile> files,
  ) async {
    final localPaths = <String>{};
    final cleanupTempPaths = <String>[];
    if (files.isEmpty) {
      return (<String>[], <String>[]);
    }

    final tempRoot = Directory(
      p.join(Directory.systemTemp.path, 'asmote-mobile-upload-cache'),
    );

    for (final file in files) {
      final path = file.path.trim();
      if (path.isNotEmpty) {
        final type = await FileSystemEntity.type(path);
        if (type != FileSystemEntityType.notFound) {
          localPaths.add(path);
          continue;
        }
      }

      if (!await tempRoot.exists()) {
        await tempRoot.create(recursive: true);
      }
      final fallbackName = file.name.trim().isEmpty
          ? 'upload-${DateTime.now().microsecondsSinceEpoch}'
          : file.name.trim();
      final tempPath = await _allocateUniqueFilePath(
        tempRoot.path,
        fallbackName,
      );
      final sink = File(tempPath).openWrite();
      try {
        await for (final chunk in file.openRead()) {
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }
      localPaths.add(tempPath);
      cleanupTempPaths.add(tempPath);
    }

    return (localPaths.toList(growable: false), cleanupTempPaths);
  }

  Future<String> _allocateUniqueFilePath(
    String directory,
    String fileName,
  ) async {
    final safeName = fileName.isEmpty ? 'upload-file' : fileName;
    final stem = p.basenameWithoutExtension(safeName);
    final ext = p.extension(safeName);
    var candidate = p.join(directory, safeName);
    var index = 1;
    while (await FileSystemEntity.type(candidate) !=
        FileSystemEntityType.notFound) {
      candidate = p.join(directory, '$stem ($index)$ext');
      index += 1;
    }
    return candidate;
  }

  Future<void> _cleanupTempUploadFiles(List<String> paths) async {
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }

  Future<bool> _waitForDrop(DragSession session) async {
    final existing = session.dragCompleted.value;
    if (existing != null) {
      return _isAcceptedDrop(existing);
    }
    final completer = Completer<DropOperation?>();
    void listener() {
      final value = session.dragCompleted.value;
      if (value == null) return;
      session.dragCompleted.removeListener(listener);
      completer.complete(value);
    }

    session.dragCompleted.addListener(listener);
    final result = await completer.future;
    return _isAcceptedDrop(result);
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_cacheCurrentScrollOffset);
    _globalPointerRoute = _handleGlobalPointerEvent;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_globalPointerRoute!);
  }

  @override
  void didUpdateWidget(covariant FileTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      _cacheScrollOffsetForSession(oldWidget.session);
      _lastScrollRestoreToken = null;
      _nameFilterQuery = '';
    }
  }

  @override
  void dispose() {
    _cacheCurrentScrollOffset();
    _scrollController.removeListener(_cacheCurrentScrollOffset);
    _horizontalController.dispose();
    if (_globalPointerRoute != null) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(
        _globalPointerRoute!,
      );
      _globalPointerRoute = null;
    }
    _scrollController.dispose();
    super.dispose();
  }

  String _activePath(TerminalSession session) {
    return session.fileState.currentPath.isNotEmpty
        ? session.fileState.currentPath
        : session.fileState.rootPath;
  }

  void _cacheCurrentScrollOffset() {
    _cacheScrollOffsetForSession(widget.session);
  }

  void _cacheScrollOffsetForSession(TerminalSession? session) {
    if (session == null) return;
    if (!_scrollController.hasClients) return;
    final path = _activePath(session);
    if (path.isEmpty) return;
    session.fileState.scrollOffsets[path] = _scrollController.offset;
  }

  void _restoreScrollOffsetIfNeeded(TerminalSession session, String path) {
    final token = '${session.id}|$path';
    if (_lastScrollRestoreToken == token) return;
    _lastScrollRestoreToken = token;
    final target = session.fileState.scrollOffsets[path] ?? 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      final clamped = target.clamp(0.0, max).toDouble();
      final current = _scrollController.offset;
      if ((current - clamped).abs() < 0.5) return;
      _scrollController.jumpTo(clamped);
    });
  }

  int _compareNullableDate(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }

  List<FileNode> _sortEntries(List<FileNode> source) {
    if (_modifiedSortOrder == _ModifiedSortOrder.none) {
      return List<FileNode>.of(source, growable: false);
    }
    final entries = List<FileNode>.of(source, growable: false);
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      var result = _compareNullableDate(a.modified, b.modified);
      if (_modifiedSortOrder == _ModifiedSortOrder.desc) {
        result = -result;
      }
      if (result != 0) return result;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  void _toggleModifiedSort() {
    setState(() {
      switch (_modifiedSortOrder) {
        case _ModifiedSortOrder.none:
          _modifiedSortOrder = _ModifiedSortOrder.desc;
          break;
        case _ModifiedSortOrder.desc:
          _modifiedSortOrder = _ModifiedSortOrder.asc;
          break;
        case _ModifiedSortOrder.asc:
          _modifiedSortOrder = _ModifiedSortOrder.none;
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = widget.appState;
    final session = widget.session;
    if (session == null) {
      return PlaceholderPanel(
        title: l(appState, AppStrings.values.noActiveSession),
        description: l(appState, AppStrings.values.connectToUseSftp),
        actionLabel: l(appState, AppStrings.values.newSession),
        onAction: () => showHostDialog(context, appState),
      );
    }

    if (session.tab.status != TerminalStatus.connected) {
      return PlaceholderPanel(
        title: l(appState, AppStrings.values.sessionOffline),
        description: l(appState, AppStrings.values.sessionIsOffline),
        actionLabel: l(appState, AppStrings.values.reconnect),
        onAction: () => unawaited(appState.reconnectSession(session)),
      );
    }

    final needsFileTreeInit = session.profile.isLocal
        ? (session.fileState.homePath == null &&
              session.fileState.directories.isEmpty)
        : session.sftp == null;
    if (needsFileTreeInit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(appState.ensureSftpReady(session));
      });
    }

    final rootPath = session.fileState.rootPath;
    final currentPath = session.fileState.currentPath.isNotEmpty
        ? session.fileState.currentPath
        : rootPath;
    _restoreScrollOffsetIfNeeded(session, currentPath);
    final showHidden = widget.showHidden;
    if (rootPath.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final nodes = session.fileState.directories[currentPath];
    if (nodes == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final entries = _sortEntries(
      nodes.where((node) {
        if (!showHidden && node.name.startsWith('.')) return false;
        return _matchesNameFilter(node);
      }).toList(),
    );

    return _FileDropTarget(
      enabled: isDesktopPlatform() && !session.profile.isLocal,
      onFilesDropped: (paths, _) {
        final targetDir = session.fileState.currentPath.isNotEmpty
            ? session.fileState.currentPath
            : rootPath;
        unawaited(appState.uploadFiles(session, paths, targetDir));
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          if (event.buttons & kPrimaryButton == 0) {
            return;
          }
          if (session.fileState.selected.isEmpty) {
            return;
          }
          final clickedRow = _isPositionOnFileRow(event.position, entries);
          if (!clickedRow) {
            appState.clearFileSelection(session);
          }
        },
        child: Column(
          children: [
            FileTreeHeader(
              session: session,
              showHiddenFiles: appState.showHiddenFiles,
              activeFilter: _nameFilterQuery,
              canGoBack: appState.canGoBack(session),
              canGoForward: appState.canGoForward(session),
              onGoBack: () => unawaited(appState.goBack(session)),
              onGoForward: () => unawaited(appState.goForward(session)),
              onRefresh: () {
                final path = session.fileState.currentPath.isNotEmpty
                    ? session.fileState.currentPath
                    : rootPath;
                unawaited(appState.refreshDirectory(session, path));
              },
              onCreateFile: () =>
                  showCreateFileDialog(context, appState, session),
              onCreateFolder: () =>
                  showCreateFolderDialog(context, appState, session),
              onToggleShowHidden: () =>
                  appState.setShowHiddenFiles(!appState.showHiddenFiles),
              onSearchChanged: (value) {
                setState(() {
                  _nameFilterQuery = value;
                });
              },
              onUploadFromSystem: () => unawaited(
                _uploadFromSystemPicker(appState, session, rootPath),
              ),
              onPathSubmitted: (value) =>
                  unawaited(appState.navigateToPath(session, value)),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const minContentWidth =
                      _fileTreeLeadingWidth +
                      _fileTreeColumnsContentWidth +
                      _fileTreeTrailingWidth;
                  final contentWidth = math.max(
                    constraints.maxWidth,
                    minContentWidth,
                  );
                  final enableHorizontalScroll =
                      contentWidth > constraints.maxWidth + 0.5;
                  final columnLayout = _computeFileTreeColumnLayout(
                    constraints.maxWidth,
                  );
                  if (entries.isEmpty) {
                    return Center(
                      child: Text(
                        l(appState, AppStrings.values.noMatchingFiles),
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    );
                  }
                  final listView = ListView.builder(
                    key: _listKey,
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      vertical: _listVerticalPadding,
                    ),
                    itemCount: entries.length,
                    itemExtent: _rowHeight,
                    addAutomaticKeepAlives: false,
                    addSemanticIndexes: false,
                    cacheExtent: 600,
                    itemBuilder: (context, index) {
                      final node = entries[index];
                      final isDesktop = isDesktopPlatform();
                      final row = _FileNodeSelectableRow(
                        session: session,
                        node: node,
                        filterQuery: _nameFilterQuery,
                        rowHeight: _rowHeight,
                        depth: 0,
                        isExpanded: false,
                        showExpand: false,
                        columnLayout: columnLayout,
                        onToggle: null,
                        onSelect: () => appState.toggleFileSelection(
                          session,
                          node.path,
                          multi: _isMultiSelectPressed(),
                          isDirectory: node.isDirectory,
                        ),
                        onOpen: () {
                          unawaited(
                            openFileNodeWithViewer(
                              context,
                              appState,
                              session,
                              node,
                            ),
                          );
                        },
                        onOpenMenu: (position) {
                          final selectedNodes = _selectedNodesForEntries(
                            session,
                            entries,
                          );
                          final selectedPaths = session.fileState.selected;
                          final menuNodes =
                              selectedNodes.length > 1 &&
                                  selectedPaths.contains(node.path)
                              ? selectedNodes
                              : <FileNode>[node];
                          if (menuNodes.length > 1) {
                            unawaited(
                              showFilesMenu(
                                context,
                                appState,
                                session,
                                menuNodes,
                                position,
                              ),
                            );
                            return;
                          }
                          unawaited(
                            showFileMenu(
                              context,
                              appState,
                              session,
                              node,
                              position,
                            ),
                          );
                        },
                      );
                      if (!isDesktop || session.profile.isLocal) {
                        return KeyedSubtree(
                          key: ValueKey<String>('row-${node.path}'),
                          child: row,
                        );
                      }
                      return DragItemWidget(
                        key: ValueKey<String>('drag-${node.path}'),
                        dragItemProvider: (request) async {
                          final selectedNodes = _selectedNodesForEntries(
                            session,
                            entries,
                          );
                          final selectedPaths = session.fileState.selected;
                          final activeSelection =
                              selectedNodes.length > 1 &&
                                  selectedPaths.contains(node.path)
                              ? selectedNodes
                              : <FileNode>[node];
                          if (activeSelection.length > 1) {
                            final folderName =
                                '${session.tab.title.replaceAll(RegExp(r'\s+'), '_')}-selection';
                            final folderPath = await appState
                                .prepareDesktopDropDirectoryBundle(folderName);
                            final item = DragItem(
                              suggestedName: p.basename(folderPath),
                              localData: _remoteFileTreeDragLocalDataTag,
                            );
                            item.add(Formats.fileUri(Uri.file(folderPath)));
                            unawaited(() async {
                              final accepted = await _waitForDrop(
                                request.session,
                              );
                              if (!accepted) {
                                unawaited(
                                  appState.cleanupDragFolder(folderPath),
                                );
                                return;
                              }
                              await appState.downloadSelectionToLocal(
                                session,
                                activeSelection,
                                folderPath,
                              );
                            }());
                            return item;
                          }

                          final item = DragItem(
                            suggestedName: node.name,
                            localData: _remoteFileTreeDragLocalDataTag,
                          );
                          if (node.isDirectory) {
                            final folderPath = await appState
                                .prepareDesktopDropFolder(node.name);
                            item.add(Formats.fileUri(Uri.file(folderPath)));
                            unawaited(() async {
                              final accepted = await _waitForDrop(
                                request.session,
                              );
                              if (!accepted) {
                                unawaited(
                                  appState.cleanupDragFolder(folderPath),
                                );
                                return;
                              }
                              await appState.downloadDirectoryToLocal(
                                session,
                                node.path,
                                folderPath,
                              );
                            }());
                          } else {
                            final filePath = await appState
                                .prepareDesktopDropFile(node.name);
                            item.add(Formats.fileUri(Uri.file(filePath)));
                            unawaited(() async {
                              final accepted = await _waitForDrop(
                                request.session,
                              );
                              if (!accepted) {
                                unawaited(appState.cleanupDragFile(filePath));
                                return;
                              }
                              await appState.downloadFileToLocal(
                                session,
                                node.path,
                                filePath,
                                displayName: node.name,
                              );
                            }());
                          }
                          return item;
                        },
                        allowedOperations: () => [DropOperation.copy],
                        child: DraggableWidget(
                          child: KeyedSubtree(
                            key: ValueKey<String>('row-${node.path}'),
                            child: row,
                          ),
                        ),
                      );
                    },
                  );
                  return Scrollbar(
                    controller: _horizontalController,
                    thumbVisibility:
                        enableHorizontalScroll && isDesktopPlatform(),
                    child: SingleChildScrollView(
                      controller: _horizontalController,
                      scrollDirection: Axis.horizontal,
                      physics: enableHorizontalScroll
                          ? const ClampingScrollPhysics()
                          : const NeverScrollableScrollPhysics(),
                      child: SizedBox(
                        width: contentWidth,
                        child: Column(
                          children: [
                            _FileTreeColumnsHeader(
                              appState: appState,
                              columnLayout: columnLayout,
                              modifiedSortOrder: _modifiedSortOrder,
                              onToggleModifiedSort: _toggleModifiedSort,
                            ),
                            Expanded(child: listView),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
