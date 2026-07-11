part of 'terminal_file_tree.dart';

class _FileTreeColumnsHeader extends StatelessWidget {
  const _FileTreeColumnsHeader({
    required this.appState,
    required this.columnLayout,
    required this.modifiedSortOrder,
    required this.onToggleModifiedSort,
  });

  final TerminalAppState appState;
  final _FileTreeColumnLayout columnLayout;
  final _ModifiedSortOrder modifiedSortOrder;
  final VoidCallback onToggleModifiedSort;

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
      fontSize: 11,
      color: Colors.grey[700],
      fontWeight: FontWeight.w600,
    );
    Widget buildModifiedHeader({
      required String text,
      required VoidCallback onTap,
      required double width,
    }) {
      final active = modifiedSortOrder != _ModifiedSortOrder.none;
      final color = active ? const Color(0xFF2C5EEA) : Colors.grey[700];
      final arrow = switch (modifiedSortOrder) {
        _ModifiedSortOrder.asc => ' ^',
        _ModifiedSortOrder.desc => ' v',
        _ModifiedSortOrder.none => '',
      };
      return SizedBox(
        width: width,
        child: InkWell(
          onTap: onTap,
          child: Text(
            '$text$arrow',
            style: textStyle.copyWith(color: color),
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    return Container(
      height: 24,
      padding: const EdgeInsets.fromLTRB(
        _fileTreeLeadingWidth,
        0,
        _fileTreeTrailingWidth,
        0,
      ),
      decoration: const BoxDecoration(
        color: TerminalUiPalette.panelBackground,
        border: Border(bottom: BorderSide(color: TerminalUiPalette.border)),
      ),
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          minWidth: 0,
          maxWidth: double.infinity,
          child: SizedBox(
            width: _fileTreeColumnsContentWidth,
            child: Row(
              children: [
                SizedBox(
                  width: _fileTreeMinNameWidth,
                  child: Text(
                    l(appState, AppStrings.values.name),
                    style: textStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (columnLayout.hasSize)
                  SizedBox(
                    width: columnLayout.sizeWidth,
                    child: Text(
                      l(appState, AppStrings.values.size),
                      style: textStyle,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (columnLayout.gapAfterSize > 0)
                  SizedBox(width: columnLayout.gapAfterSize),
                if (columnLayout.hasModified)
                  buildModifiedHeader(
                    text: l(appState, AppStrings.values.modified),
                    onTap: onToggleModifiedSort,
                    width: columnLayout.modifiedWidth,
                  ),
                if (columnLayout.gapAfterModified > 0)
                  SizedBox(width: columnLayout.gapAfterModified),
                if (columnLayout.hasPermissions)
                  SizedBox(
                    width: columnLayout.permissionsWidth,
                    child: Text(
                      l(appState, AppStrings.values.permissions),
                      style: textStyle,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (columnLayout.gapAfterPermissions > 0)
                  SizedBox(width: columnLayout.gapAfterPermissions),
                if (columnLayout.hasOwner)
                  SizedBox(
                    width: columnLayout.ownerWidth,
                    child: Text(
                      l(appState, AppStrings.values.fileOwner),
                      style: textStyle,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (columnLayout.gapAfterOwner > 0)
                  SizedBox(width: columnLayout.gapAfterOwner),
                if (columnLayout.hasGroup)
                  SizedBox(
                    width: columnLayout.groupWidth,
                    child: Text(
                      l(appState, AppStrings.values.fileGroup),
                      style: textStyle,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (columnLayout.gapAfterGroup > 0)
                  SizedBox(width: columnLayout.gapAfterGroup),
                if (columnLayout.hasTransfer)
                  SizedBox(
                    width: columnLayout.transferWidth,
                    child: Text(
                      l(appState, AppStrings.values.transfers),
                      style: textStyle,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FileTreeHeader extends StatefulWidget {
  const FileTreeHeader({
    required this.session,
    required this.showHiddenFiles,
    required this.activeFilter,
    required this.canGoBack,
    required this.canGoForward,
    required this.onGoBack,
    required this.onGoForward,
    required this.onRefresh,
    required this.onCreateFile,
    required this.onCreateFolder,
    required this.onToggleShowHidden,
    required this.onSearchChanged,
    required this.onPathSubmitted,
    required this.onGoHome,
  });

  final TerminalSession session;
  final bool showHiddenFiles;
  final String activeFilter;
  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback onGoBack;
  final VoidCallback onGoForward;
  final VoidCallback onRefresh;
  final VoidCallback onCreateFile;
  final VoidCallback onCreateFolder;
  final VoidCallback onToggleShowHidden;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onPathSubmitted;
  final VoidCallback onGoHome;

  @override
  State<FileTreeHeader> createState() => FileTreeHeaderState();
}

class FileTreeHeaderState extends State<FileTreeHeader> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _currentPath());
  }

  @override
  void didUpdateWidget(covariant FileTreeHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus) {
      final path = _currentPath();
      if (_controller.text != path) {
        _controller.text = path;
      }
    }
  }

  String _currentPath() {
    final path = widget.session.fileState.currentPath;
    return path.isEmpty ? widget.session.fileState.rootPath : path;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<TerminalAppState>(context, listen: false);
    Widget toolbarIconButton({
      required VoidCallback? onPressed,
      required IconData icon,
      required String semanticsLabel,
      bool active = false,
    }) {
      final enabled = onPressed != null;
      final iconColor = !enabled
          ? TerminalUiPalette.textSecondary.withValues(alpha: 0.45)
          : active
          ? TerminalUiPalette.accent
          : TerminalUiPalette.inkBlue;
      final backgroundColor = !enabled
          ? TerminalUiPalette.cardBackground
          : active
          ? TerminalUiPalette.accentSelected
          : TerminalUiPalette.cardBackground;
      final borderColor = active
          ? TerminalUiPalette.accent
          : TerminalUiPalette.border;
      return Semantics(
        button: true,
        label: semanticsLabel,
        child: Tooltip(
          message: semanticsLabel,
          waitDuration: const Duration(milliseconds: 250),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor),
              ),
              child: Icon(icon, size: 14, color: iconColor),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      decoration: const BoxDecoration(
        color: TerminalUiPalette.panelBackground,
        border: Border(bottom: BorderSide(color: TerminalUiPalette.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            toolbarIconButton(
              onPressed: widget.onGoHome,
              icon: Icons.home_outlined,
              semanticsLabel: 'Home',
            ),
            const SizedBox(width: 4),
            toolbarIconButton(
              onPressed: widget.canGoBack ? widget.onGoBack : null,
              icon: Icons.arrow_back,
              semanticsLabel: l(appState, AppStrings.values.back),
            ),
            const SizedBox(width: 2),
            toolbarIconButton(
              onPressed: widget.canGoForward ? widget.onGoForward : null,
              icon: Icons.arrow_forward,
              semanticsLabel: l(appState, AppStrings.values.forward),
            ),
            const SizedBox(width: 4),
            toolbarIconButton(
              onPressed: widget.onCreateFile,
              icon: Icons.note_add_outlined,
              semanticsLabel: l(appState, AppStrings.values.newFile),
            ),
            const SizedBox(width: 2),
            toolbarIconButton(
              onPressed: widget.onCreateFolder,
              icon: Icons.create_new_folder_outlined,
              semanticsLabel: l(appState, AppStrings.values.newFolder),
            ),
            const SizedBox(width: 2),
            toolbarIconButton(
              onPressed: widget.onToggleShowHidden,
              icon: widget.showHiddenFiles
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              semanticsLabel: l(
                appState,
                AppStrings.values.showHiddenFiles,
              ),
              active: widget.showHiddenFiles,
            ),
            const SizedBox(width: 2),
            toolbarIconButton(
              onPressed: widget.onRefresh,
              icon: Icons.refresh,
              semanticsLabel: l(appState, AppStrings.values.refresh),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 200,
              height: 28,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                style: const TextStyle(
                  fontSize: 12,
                  color: TerminalUiPalette.textPrimary,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: l(appState, AppStrings.values.enterPath),
                  hintStyle: const TextStyle(
                    color: TerminalUiPalette.textSecondary,
                    fontSize: 12,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 14,
                    color: TerminalUiPalette.textSecondary,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: TerminalUiPalette.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: TerminalUiPalette.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(
                      color: TerminalUiPalette.accent,
                      width: 1.2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  filled: true,
                  fillColor: TerminalUiPalette.cardBackground,
                ),
                onChanged: (value) {
                  widget.onSearchChanged(value.trim());
                },
                onSubmitted: (value) {
                  widget.onPathSubmitted(value);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileNodeRow extends StatefulWidget {
  const _FileNodeRow({
    required this.node,
    required this.filterQuery,
    required this.depth,
    required this.isExpanded,
    this.showExpand = true,
    required this.isSelected,
    required this.columnLayout,
    required this.onSelect,
    required this.onOpen,
    this.onToggle,
    this.onOpenMenu,
    this.transferTask,
  });

  final FileNode node;
  final String filterQuery;
  final int depth;
  final bool isExpanded;
  final bool showExpand;
  final bool isSelected;
  final _FileTreeColumnLayout columnLayout;
  final VoidCallback onSelect;
  final VoidCallback onOpen;
  final VoidCallback? onToggle;
  final ValueChanged<Offset>? onOpenMenu;
  final TransferTask? transferTask;

  @override
  State<_FileNodeRow> createState() => _FileNodeRowState();
}

class _FileNodeRowState extends State<_FileNodeRow> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return '-';
    final local = value.toLocal();
    String pad2(int part) => part.toString().padLeft(2, '0');
    return '${local.year}-${pad2(local.month)}-${pad2(local.day)} '
        '${pad2(local.hour)}:${pad2(local.minute)}:${pad2(local.second)}';
  }

  String _formatPermissions(int? rawMode) {
    if (rawMode == null) return '-';
    final bits = rawMode & 0x1FF;
    String triplet(int value) {
      final read = (value & 0x4) != 0 ? 'r' : '-';
      final write = (value & 0x2) != 0 ? 'w' : '-';
      final execute = (value & 0x1) != 0 ? 'x' : '-';
      return '$read$write$execute';
    }

    final user = triplet((bits >> 6) & 0x7);
    final group = triplet((bits >> 3) & 0x7);
    final other = triplet(bits & 0x7);
    final octal = bits.toRadixString(8).padLeft(3, '0');
    return '$user$group$other ($octal)';
  }

  String _formatOwner(int? ownerId) {
    if (ownerId == null) return '-';
    if (ownerId == 0) return 'root (0)';
    return ownerId.toString();
  }

  String _formatGroup(int? groupId) {
    if (groupId == null) return '-';
    if (groupId == 0) return 'root (0)';
    return groupId.toString();
  }

  Widget _buildTransferCell() {
    final task = widget.transferTask;
    if (task == null) return const SizedBox.shrink();

    final progress = task.progress;
    switch (task.status) {
      case TransferStatus.running:
      case TransferStatus.queued:
        return Center(
          child: Stack(
            alignment: Alignment.centerRight,
            children: [
              SizedBox(
                width: _fileTreeTransferColWidth - 4,
                height: 14,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                    backgroundColor: TerminalUiPalette.border,
                    valueColor: const AlwaysStoppedAnimation(
                      TerminalUiPalette.accent,
                    ),
                    minHeight: 14,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Text(
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 9,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      case TransferStatus.completed:
        return const Center(
          child: Icon(Icons.check_circle, size: 14, color: Colors.green),
        );
      case TransferStatus.failed:
        return const Center(
          child: Icon(Icons.error, size: 14, color: Colors.red),
        );
      case TransferStatus.paused:
        return const Center(
          child: Icon(Icons.pause_circle, size: 14, color: Colors.orange),
        );
      case TransferStatus.canceled:
        return const Center(
          child: Icon(Icons.cancel, size: 14, color: Colors.grey),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rowContentWidth =
        6 +
        widget.depth * 12 +
        20 +
        4 +
        _fileTreeNodeIconWidth +
        6 +
        _fileTreeColumnsContentWidth +
        6;
    final iconStyle = FileIconResolver.resolve(widget.node);
    final hiddenDirectory =
        widget.node.isDirectory && widget.node.name.startsWith('.');
    final iconOpacity = hiddenDirectory ? 0.55 : 1.0;
    final showHover = _hovered && !widget.isSelected;
    final background = widget.isSelected
        ? TerminalUiPalette.accentSelected
        : showHover
        ? TerminalUiPalette.accentSoft
        : null;
    final border = widget.isSelected
        ? Border.all(color: TerminalUiPalette.accent, width: 1)
        : null;
    final iconWidget = iconStyle.svgAssetPath != null
        ? SvgPicture.asset(
            iconStyle.svgAssetPath!,
            width: 15,
            height: 15,
            fit: BoxFit.contain,
          )
        : Icon(iconStyle.icon, size: 15, color: iconStyle.color);

    final rowContent = GestureDetector(
      onSecondaryTapDown: (details) =>
          widget.onOpenMenu?.call(details.globalPosition),
      onLongPressStart: (details) =>
          widget.onOpenMenu?.call(details.globalPosition),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if (event.buttons & kPrimaryButton == 0) return;
          widget.onSelect();
        },
        child: InkWell(
          onHover: _setHovered,
          onDoubleTap: widget.onOpen,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            decoration: BoxDecoration(
              color: background,
              border: border,
              borderRadius: BorderRadius.circular(6),
            ),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: 0,
                maxWidth: double.infinity,
                child: SizedBox(
                  width: rowContentWidth.toDouble(),
                  child: Row(
                    children: [
                      SizedBox(width: 6 + widget.depth * 12),
                      if (widget.showExpand && widget.node.isDirectory)
                        IconButton(
                          icon: Icon(
                            widget.isExpanded
                                ? Icons.expand_more
                                : Icons.chevron_right,
                            size: 16,
                          ),
                          onPressed: widget.onToggle,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 20,
                            height: 20,
                          ),
                        )
                      else
                        const SizedBox(width: 20),
                      const SizedBox(width: 4),
                      Opacity(opacity: iconOpacity, child: iconWidget),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: _fileTreeMinNameWidth,
                        child: Builder(
                          builder: (context) {
                            final query = widget.filterQuery.trim();
                            if (query.isEmpty) {
                              return Text(
                                widget.node.name,
                                style: const TextStyle(fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                              );
                            }
                            final lowerQuery = query.toLowerCase();
                            final nameLower = widget.node.name.toLowerCase();
                            if (nameLower.contains(lowerQuery)) {
                              return Text.rich(
                                AppTextStyles.highlightSpan(
                                  text: widget.node.name,
                                  query: query,
                                  baseStyle: const TextStyle(fontSize: 13),
                                  matchColor: TerminalUiPalette.error,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                              );
                            }
                            if (query.contains('/')) {
                              final parts = query
                                  .split('/')
                                  .where((p) => p.isNotEmpty)
                                  .toList();
                              if (parts.isNotEmpty) {
                                final lastPart = parts.last.toLowerCase();
                                if (nameLower.contains(lastPart)) {
                                  return Text.rich(
                                    AppTextStyles.highlightSpan(
                                      text: widget.node.name,
                                      query: parts.last,
                                      baseStyle: const TextStyle(fontSize: 13),
                                      matchColor: TerminalUiPalette.error,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    softWrap: false,
                                  );
                                }
                              }
                            }
                            return Text(
                              widget.node.name,
                              style: const TextStyle(fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                            );
                          },
                        ),
                      ),
                      if (widget.columnLayout.hasSize) ...[
                        SizedBox(
                          width: widget.columnLayout.sizeWidth.clamp(
                            0.0,
                            _fileTreeSizeColWidth,
                          ),
                          child: Text(
                            widget.node.isDirectory
                                ? '-'
                                : formatBytes(widget.node.size),
                            style: TextStyle(
                              fontSize: 11,
                              color: TerminalUiPalette.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                          ),
                        ),
                        if (widget.columnLayout.gapAfterSize > 0)
                          SizedBox(width: widget.columnLayout.gapAfterSize),
                      ],
                      if (widget.columnLayout.hasModified) ...[
                        SizedBox(
                          width: widget.columnLayout.modifiedWidth,
                          child: Text(
                            _formatDateTime(widget.node.modified),
                            style: TextStyle(
                              fontSize: 11,
                              color: TerminalUiPalette.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                          ),
                        ),
                        if (widget.columnLayout.gapAfterModified > 0)
                          SizedBox(width: widget.columnLayout.gapAfterModified),
                      ],
                      if (widget.columnLayout.hasPermissions)
                        Padding(
                          padding: EdgeInsets.zero,
                          child: SizedBox(
                            width: widget.columnLayout.permissionsWidth,
                            child: Text(
                              _formatPermissions(widget.node.permissions),
                              style: TextStyle(
                                fontSize: 11,
                                color: TerminalUiPalette.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              softWrap: false,
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ),
                      if (widget.columnLayout.gapAfterPermissions > 0)
                        SizedBox(
                          width: widget.columnLayout.gapAfterPermissions,
                        ),
                      if (widget.columnLayout.hasOwner)
                        SizedBox(
                          width: widget.columnLayout.ownerWidth,
                          child: Text(
                            _formatOwner(widget.node.ownerId),
                            style: TextStyle(
                              fontSize: 11,
                              color: TerminalUiPalette.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            textAlign: TextAlign.right,
                          ),
                        ),
                      if (widget.columnLayout.gapAfterOwner > 0)
                        SizedBox(width: widget.columnLayout.gapAfterOwner),
                      if (widget.columnLayout.hasGroup)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: SizedBox(
                            width: widget.columnLayout.groupWidth,
                            child: Text(
                              _formatGroup(widget.node.groupId),
                              style: TextStyle(
                                fontSize: 11,
                                color: TerminalUiPalette.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ),
                      if (widget.columnLayout.gapAfterGroup > 0)
                        SizedBox(width: widget.columnLayout.gapAfterGroup),
                      if (widget.columnLayout.hasTransfer)
                        SizedBox(
                          width: widget.columnLayout.transferWidth,
                          child: _buildTransferCell(),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (!isDesktopPlatform()) {
      return rowContent;
    }

    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: rowContent,
    );
  }
}

class _FileNodeSelectableRow extends StatefulWidget {
  const _FileNodeSelectableRow({
    required this.session,
    required this.node,
    required this.filterQuery,
    required this.rowHeight,
    required this.depth,
    required this.isExpanded,
    required this.columnLayout,
    this.showExpand = true,
    required this.onSelect,
    required this.onOpen,
    this.onToggle,
    this.onOpenMenu,
    this.transferTask,
  });

  final TerminalSession session;
  final FileNode node;
  final String filterQuery;
  final double rowHeight;
  final int depth;
  final bool isExpanded;
  final _FileTreeColumnLayout columnLayout;
  final bool showExpand;
  final VoidCallback onSelect;
  final VoidCallback onOpen;
  final VoidCallback? onToggle;
  final ValueChanged<Offset>? onOpenMenu;
  final TransferTask? transferTask;

  @override
  State<_FileNodeSelectableRow> createState() => _FileNodeSelectableRowState();
}

class _FileNodeSelectableRowState extends State<_FileNodeSelectableRow> {
  late bool _selected;
  ValueNotifier<int>? _notifier;

  @override
  void initState() {
    super.initState();
    _selected = widget.session.fileState.selected.contains(widget.node.path);
    _attachNotifier(widget.session.fileState.selectionVersion);
  }

  @override
  void didUpdateWidget(covariant _FileNodeSelectableRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      _detachNotifier();
      _attachNotifier(widget.session.fileState.selectionVersion);
    }
    if (oldWidget.node.path != widget.node.path) {
      _selected = widget.session.fileState.selected.contains(widget.node.path);
    }
  }

  void _attachNotifier(ValueNotifier<int> notifier) {
    _notifier = notifier;
    notifier.addListener(_handleSelectionChanged);
  }

  void _detachNotifier() {
    _notifier?.removeListener(_handleSelectionChanged);
    _notifier = null;
  }

  void _handleSelectionChanged() {
    final next = widget.session.fileState.selected.contains(widget.node.path);
    if (next != _selected && mounted) {
      setState(() => _selected = next);
    }
  }

  @override
  void dispose() {
    _detachNotifier();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.rowHeight,
      child: _FileNodeRow(
        node: widget.node,
        filterQuery: widget.filterQuery,
        depth: widget.depth,
        isExpanded: widget.isExpanded,
        columnLayout: widget.columnLayout,
        showExpand: widget.showExpand,
        isSelected: _selected,
        onToggle: widget.onToggle,
        onSelect: widget.onSelect,
        onOpen: widget.onOpen,
        onOpenMenu: widget.onOpenMenu,
        transferTask: widget.transferTask,
      ),
    );
  }
}

class _FileDropTarget extends StatefulWidget {
  const _FileDropTarget({
    required this.enabled,
    required this.onFilesDropped,
    required this.child,
  });

  final bool enabled;
  final void Function(List<String> paths, Offset? globalPosition)
  onFilesDropped;
  final Widget child;

  @override
  State<_FileDropTarget> createState() => _FileDropTargetState();
}

class _FileDropTargetState extends State<_FileDropTarget> {
  static const String _windowsCfHdropFormat = 'NativeShell_CF_15';

  bool _dragging = false;
  bool _forbidden = false;
  Offset? _lastDropOverGlobalPosition;

  bool _containsInternalDragData(List<DropItem> items) {
    return items.any(
      (item) => item.localData == _remoteFileTreeDragLocalDataTag,
    );
  }

  Future<Uri?> _readFileUri(Object reader) async {
    final dynamic dynamicReader = reader;
    final completer = Completer<Uri?>();
    final progress = dynamicReader.getValue<Uri>(
      Formats.fileUri,
      (value) {
        if (!completer.isCompleted) {
          completer.complete(value);
        }
      },
      onError: (_) {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      },
    );
    if (progress == null) {
      return null;
    }
    return completer.future;
  }

  Future<String?> _readPlainText(Object reader) async {
    final dynamic dynamicReader = reader;
    final completer = Completer<String?>();
    final progress = dynamicReader.getValue<String>(
      Formats.plainText,
      (value) {
        if (!completer.isCompleted) {
          completer.complete(value);
        }
      },
      onError: (_) {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      },
    );
    if (progress == null) {
      return null;
    }
    return completer.future;
  }

  List<String> _parsePlainTextDropPaths(String text) {
    final rawLines = text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final parsed = <String>[];
    for (final line in rawLines) {
      if (line.startsWith('file://')) {
        try {
          final uri = Uri.parse(line);
          parsed.add(uri.toFilePath(windows: Platform.isWindows));
          continue;
        } catch (_) {}
      }
      parsed.add(line);
    }
    return parsed;
  }

  Future<String?> _readSuggestedName(Object reader) async {
    try {
      final dynamic dynamicReader = reader;
      final name = await dynamicReader.getSuggestedName() as String?;
      if (name == null) {
        return null;
      }
      final trimmed = name.trim();
      return trimmed.isEmpty ? null : trimmed;
    } catch (_) {
      return null;
    }
  }

  String _normalizeDroppedPath(String path) {
    var normalized = path.replaceAll('\u0000', '').trim();
    if (normalized.startsWith('"') && normalized.endsWith('"')) {
      normalized = normalized.substring(1, normalized.length - 1);
    }
    if (normalized.startsWith('\\?\\')) {
      normalized = normalized.substring(4);
    }
    if (normalized.startsWith('\\') &&
        normalized.length > 3 &&
        RegExp(r'^[A-Za-z]:').hasMatch(normalized.substring(1))) {
      normalized = normalized.substring(1);
    }
    if (normalized.startsWith('/') &&
        normalized.length > 3 &&
        RegExp(r'^[A-Za-z]:').hasMatch(normalized.substring(1))) {
      normalized = normalized.substring(1);
    }
    if (normalized.contains('*') || normalized.contains('?')) {
      return '';
    }
    normalized = p.normalize(normalized);
    if (!p.isAbsolute(normalized)) {
      return '';
    }
    final normalizedSegments = normalized.replaceAll('\\', '/').split('/');
    if (normalizedSegments.contains('..')) {
      return '';
    }
    return normalized;
  }

  bool _pathExists(String path) {
    try {
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      return type != FileSystemEntityType.notFound;
    } catch (_) {
      return false;
    }
  }

  bool _isDirectoryPath(String path) {
    try {
      return FileSystemEntity.typeSync(path, followLinks: false) ==
          FileSystemEntityType.directory;
    } catch (_) {
      return false;
    }
  }

  bool _samePathIgnoreCase(String a, String b) {
    var left = a.replaceAll('\\', '/');
    var right = b.replaceAll('\\', '/');
    while (left.length > 1 && left.endsWith('/')) {
      left = left.substring(0, left.length - 1);
    }
    while (right.length > 1 && right.endsWith('/')) {
      right = right.substring(0, right.length - 1);
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return left.toLowerCase() == right.toLowerCase();
    }
    return left == right;
  }

  String? _commonParent(List<String> paths) {
    if (paths.isEmpty) return null;
    final parents = paths
        .map((value) => p.dirname(value))
        .toList(growable: false);
    final first = parents.first;
    for (final parent in parents.skip(1)) {
      if (!_samePathIgnoreCase(first, parent)) {
        return null;
      }
    }
    return first;
  }

  bool _isDesktopLikePath(String path) {
    if (defaultTargetPlatform != TargetPlatform.windows) {
      return false;
    }
    final candidates = <String>{};
    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.isNotEmpty) {
      candidates.add(p.join(userProfile, 'Desktop'));
    }
    final oneDrive = Platform.environment['OneDrive'];
    if (oneDrive != null && oneDrive.isNotEmpty) {
      candidates.add(p.join(oneDrive, 'Desktop'));
    }
    final publicProfile = Platform.environment['PUBLIC'];
    if (publicProfile != null && publicProfile.isNotEmpty) {
      candidates.add(p.join(publicProfile, 'Desktop'));
    }
    for (final candidate in candidates) {
      if (_samePathIgnoreCase(path, candidate)) {
        return true;
      }
    }
    return false;
  }

  List<String> _filterBySuggestedName(
    List<String> paths,
    String suggestedName,
  ) {
    final normalizedSuggested = suggestedName.trim().toLowerCase();
    if (normalizedSuggested.isEmpty) {
      return paths;
    }
    final matches = paths
        .where((value) {
          return p.basename(value).trim().toLowerCase() == normalizedSuggested;
        })
        .toList(growable: false);
    if (matches.length == 1) {
      return matches;
    }
    return paths;
  }

  List<String> _resolveAmbiguousDesktopDropPaths(List<String> paths) {
    if (paths.length <= 1) {
      return paths;
    }
    final commonParent = _commonParent(paths);
    if (commonParent == null || !_isDesktopLikePath(commonParent)) {
      return paths;
    }
    final directories = paths
        .where((value) => _isDirectoryPath(value))
        .toList(growable: false);
    if (directories.length == 1) {
      return directories;
    }
    return paths;
  }

  Future<List<String>> _resolveAmbiguousDropPaths(
    List<String> paths,
    Object reader,
  ) async {
    if (paths.length <= 1) {
      if (paths.isEmpty) {
        return paths;
      }
      final suggestedName = await _readSuggestedName(reader);
      if (suggestedName == null) {
        return paths;
      }
      final onlyPath = paths.first;
      if (_isDesktopLikePath(onlyPath) && _isDirectoryPath(onlyPath)) {
        final nested = p.join(onlyPath, suggestedName);
        if (_pathExists(nested)) {
          return [nested];
        }
      }
      return paths;
    }
    var filtered = paths;
    final suggestedName = await _readSuggestedName(reader);
    if (suggestedName != null) {
      filtered = _filterBySuggestedName(filtered, suggestedName);
    }
    filtered = _resolveAmbiguousDesktopDropPaths(filtered);
    return filtered;
  }

  String _normalizePathForCompare(String path) {
    var normalized = path.replaceAll('\\', '/');
    while (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      normalized = normalized.toLowerCase();
    }
    return normalized;
  }

  bool _isSameOrChildPath(String path, String parentPath) {
    final normalizedPath = _normalizePathForCompare(path);
    final normalizedParent = _normalizePathForCompare(parentPath);
    if (normalizedPath == normalizedParent) return true;
    if (normalizedParent.isEmpty) return false;
    return normalizedPath.startsWith('$normalizedParent/');
  }

  List<String> _compactDroppedPaths(List<String> paths) {
    final unique = paths.toSet().toList(growable: false)
      ..sort((a, b) => b.length.compareTo(a.length));
    final compacted = <String>[];
    for (final path in unique) {
      final parentAlreadyCoveredByChild = compacted.any((existing) {
        return _isSameOrChildPath(existing, path);
      });
      if (!parentAlreadyCoveredByChild) {
        compacted.add(path);
      }
    }
    return compacted..sort((a, b) => a.length.compareTo(b.length));
  }

  List<String> _splitNullSeparatedString(String content) {
    return content
        .split('\u0000')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  List<String> _parseWindowsDropPathsFromBytes(Uint8List bytes) {
    if (bytes.lengthInBytes < 20) {
      return const [];
    }
    final view = ByteData.sublistView(bytes);
    final listOffset = view.getUint32(0, Endian.little);
    if (listOffset <= 0 || listOffset >= bytes.lengthInBytes) {
      return const [];
    }
    final isWide = view.getUint32(16, Endian.little) != 0;
    if (isWide) {
      final start = bytes.offsetInBytes + listOffset;
      final length = (bytes.lengthInBytes - listOffset) ~/ 2;
      if (length <= 0) {
        return const [];
      }
      final units = bytes.buffer.asUint16List(start, length);
      final paths = <String>[];
      var cursor = 0;
      for (var i = 0; i < units.length; i += 1) {
        if (units[i] != 0) continue;
        if (cursor == i) {
          break;
        }
        final path = String.fromCharCodes(units.sublist(cursor, i)).trim();
        if (path.isNotEmpty) {
          paths.add(path);
        }
        cursor = i + 1;
      }
      return paths;
    }
    final raw = bytes.sublist(listOffset);
    final paths = <String>[];
    var cursor = 0;
    for (var i = 0; i < raw.length; i += 1) {
      if (raw[i] != 0) continue;
      if (cursor == i) {
        break;
      }
      final path = String.fromCharCodes(raw.sublist(cursor, i)).trim();
      if (path.isNotEmpty) {
        paths.add(path);
      }
      cursor = i + 1;
    }
    return paths;
  }

  List<String> _parseWindowsDropPaths(Object? data) {
    if (data == null) return const [];
    if (data is String) {
      return _splitNullSeparatedString(data);
    }
    if (data is Uint8List) {
      return _parseWindowsDropPathsFromBytes(data);
    }
    if (data is ByteData) {
      return _parseWindowsDropPathsFromBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    }
    if (data is List<int>) {
      return _parseWindowsDropPathsFromBytes(Uint8List.fromList(data));
    }
    return const [];
  }

  Future<List<String>> _extractDropItemPaths(DropItem item) async {
    if (item.localData == _remoteFileTreeDragLocalDataTag) {
      return const [];
    }
    final reader = item.dataReader;
    if (reader == null) {
      return const [];
    }
    final paths = <String>[];
    if (defaultTargetPlatform == TargetPlatform.windows) {
      try {
        final rawReader = reader.rawReader;
        if (rawReader != null) {
          final (future, _) = rawReader.getDataForFormat(_windowsCfHdropFormat);
          final data = await future;
          final rawWindowsPaths = _parseWindowsDropPaths(data);
          paths.addAll(rawWindowsPaths);
        }
      } catch (_) {
        // Ignore and fallback to file URI parsing.
      }
    }
    if (paths.isEmpty && item.canProvide(Formats.fileUri)) {
      try {
        final uri = await _readFileUri(reader);
        if (uri != null) {
          final filePath = uri.toFilePath(windows: Platform.isWindows);
          paths.add(filePath);
        }
      } catch (_) {
        // Ignore invalid URI payload.
      }
    }
    if (paths.isEmpty && item.canProvide(Formats.plainText)) {
      try {
        final plainText = await _readPlainText(reader);
        if (plainText != null && plainText.trim().isNotEmpty) {
          paths.addAll(_parsePlainTextDropPaths(plainText));
        }
      } catch (_) {
        // Ignore invalid plain text payload.
      }
    }
    return _resolveAmbiguousDropPaths(paths, reader);
  }

  void _updateDragState({required bool dragging, required bool forbidden}) {
    if (_dragging == dragging && _forbidden == forbidden) {
      return;
    }
    setState(() {
      _dragging = dragging;
      _forbidden = forbidden;
    });
  }

  DropOperation _onDropOver(DropOverEvent event) {
    final isInternalDrag = _containsInternalDragData(event.session.items);
    if (isInternalDrag) {
      _lastDropOverGlobalPosition = null;
      _updateDragState(dragging: false, forbidden: true);
      return DropOperation.forbidden;
    }
    _lastDropOverGlobalPosition = event.position.global;
    _updateDragState(dragging: true, forbidden: false);
    if (event.session.allowedOperations.contains(DropOperation.copy)) {
      return DropOperation.copy;
    }
    if (event.session.allowedOperations.contains(DropOperation.move)) {
      return DropOperation.move;
    }
    if (event.session.allowedOperations.contains(DropOperation.link)) {
      return DropOperation.link;
    }
    return DropOperation.copy;
  }

  Future<void> _onPerformDrop(PerformDropEvent event) async {
    _updateDragState(dragging: false, forbidden: false);
    if (_containsInternalDragData(event.session.items)) {
      return;
    }
    final rawPaths = <String>[];
    for (final item in event.session.items) {
      rawPaths.addAll(await _extractDropItemPaths(item));
    }
    final normalized = rawPaths
        .map(_normalizeDroppedPath)
        .where((path) => path.isNotEmpty && _pathExists(path))
        .toList(growable: false);
    final paths = _compactDroppedPaths(normalized);
    final dropPosition = _lastDropOverGlobalPosition ?? event.position.global;
    _lastDropOverGlobalPosition = null;
    if (paths.isNotEmpty) {
      widget.onFilesDropped(paths, dropPosition);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return DropRegion(
      formats: const [...Formats.standardFormats],
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: _onDropOver,
      onDropLeave: (_) {
        _lastDropOverGlobalPosition = null;
        _updateDragState(dragging: false, forbidden: false);
      },
      onDropEnded: (_) {
        _lastDropOverGlobalPosition = null;
        _updateDragState(dragging: false, forbidden: false);
      },
      onPerformDrop: _onPerformDrop,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: _forbidden
              ? const Color(0xFFFFE8E8)
              : (_dragging ? const Color(0xFFE8F0FF) : Colors.transparent),
        ),
        child: widget.child,
      ),
    );
  }
}




