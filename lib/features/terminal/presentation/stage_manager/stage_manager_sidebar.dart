import 'dart:async';

import 'package:flutter/material.dart';
import '../../state/terminal_app_state.dart';
import '../../models/terminal_session.dart';
import '../../models/terminal_tab.dart';
import '../../../../shared/design_system/design_system.dart';
import '../../../../shared/constants/app_string.dart';
import '../common/terminal_localization.dart';
import '../common/session_thumbnail.dart';
import '../common/stage_background.dart';
import '../common/stage_context_menu.dart';
import '../common/stage_background_picker.dart';
import '../common/command_executor.dart';

String t(BuildContext context, AppText text) =>
    text.resolveLocale(Localizations.localeOf(context));

class StageManagerSidebar extends StatelessWidget {
  const StageManagerSidebar({
    super.key,
    required this.appState,
    required this.onStageClick,
    required this.onStageShiftClick,
  });

  final TerminalAppState appState;
  final void Function(String stageId) onStageClick;
  final void Function(String stageId) onStageShiftClick;

  @override
  Widget build(BuildContext context) {
    if (!appState.stageManagerEnabled) {
      return const SizedBox.shrink();
    }

    final sidebarWidth = (MediaQuery.of(context).size.width * 0.18).clamp(180.0, 280.0);

    return Container(
      width: sidebarWidth,
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        border: Border(right: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(child: _buildStageList(context)),
          _buildFooter(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 4, right: 4, top: 2, bottom: 2),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('stage_menu_btn'),
            iconSize: 20,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: Icon(Icons.menu, color: AppColors.textSecondary),
            onPressed: () => _showTwoPaneMenu(context),
            tooltip: t(context, AppStrings.values.commandBarMore),
          ),
          IconButton(
            iconSize: 18,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: Icon(Icons.chevron_left, color: AppColors.textSecondary),
            onPressed: () {
              appState.toggleStageManager();
            },
            tooltip: t(context, AppStrings.values.collapseSidebar),
          ),
          const Spacer(),
          IconButton(
            iconSize: 18,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: Icon(Icons.add, color: AppColors.textSecondary),
            onPressed: () => _showCreateStageDialog(context),
            tooltip: t(context, AppStrings.values.newStage),
          ),
        ],
      ),
    );
  }

  // ─── Command Menu ──────────────────────────────────────────

  void _showTwoPaneMenu(BuildContext context) {
    String? shortcut(String id) {
      final idx = appState.shortcutBindings.indexWhere((s) => s.id == id);
      if (idx < 0) return null;
      final keys = appState.shortcutBindings[idx].effectiveKeys;
      return keys.isEmpty ? null : keys;
    }

    final categories = [
      _MenuCategoryData(
        'sessions',
        Icons.terminal,
        t(context, AppStrings.values.commandBarSessions),
        [
          _MenuItemData(
            'new_session',
            Icons.add,
            t(context, AppStrings.values.commandBarNewSession),
            shortcut: shortcut('newSession'),
          ),
          _MenuItemData(
            'quick_connect',
            Icons.flash_on,
            t(context, AppStrings.values.commandBarQuickConnect),
            shortcut: shortcut('quickConnect'),
          ),
          _MenuItemData(
            'close_workspace',
            Icons.close,
            t(context, AppStrings.values.commandBarCloseCurrentWorkspace),
            shortcut: shortcut('closeSession'),
          ),
          _MenuItemData(
            'close_all',
            Icons.highlight_off,
            t(context, AppStrings.values.commandBarCloseAllSessions),
            shortcut: shortcut('closeAllSessions'),
          ),
        ],
      ),
      _MenuCategoryData(
        'scripts',
        Icons.code,
        t(context, AppStrings.values.commandBarScripts),
        [
          _MenuItemData(
            'new_script',
            Icons.add,
            t(context, AppStrings.values.commandBarNewScript),
            shortcut: shortcut('newScript'),
          ),
          _MenuItemData(
            'script_list',
            Icons.list,
            t(context, AppStrings.values.commandBarScriptList),
            shortcut: shortcut('scriptList'),
          ),
          _MenuItemData(
            'script_monitor',
            Icons.monitor_heart,
            t(context, AppStrings.values.commandBarScriptMonitor),
            shortcut: shortcut('scriptMonitor'),
          ),
        ],
      ),
      _MenuCategoryData(
        'files',
        Icons.folder,
        t(context, AppStrings.values.commandBarTransfer),
        [
          _MenuItemData(
            'sftp_browser',
            Icons.folder_open,
            t(context, AppStrings.values.commandBarSftpBrowser),
            shortcut: shortcut('sftpBrowser'),
          ),
          _MenuItemData(
            'transfer_manager',
            Icons.compare_arrows,
            t(context, AppStrings.values.commandBarTransferManager),
            shortcut: shortcut('transferManager'),
          ),
        ],
      ),
      _MenuCategoryData(
        'tools',
        Icons.build,
        t(context, AppStrings.values.commandBarTools),
        [
          _MenuItemData(
            'port_forwarding',
            Icons.route,
            t(context, AppStrings.values.settingsPortForwarding),
            shortcut: shortcut('portForwarding'),
          ),
          _MenuItemData(
            'lan_scan',
            Icons.wifi_find,
            t(context, AppStrings.values.lanScan),
            shortcut: shortcut('lanScan'),
          ),
        ],
      ),
      _MenuCategoryData(
        'settings',
        Icons.settings,
        t(context, AppStrings.values.commandBarSettings),
        [
          _MenuItemData(
            'open_settings',
            Icons.settings,
            t(context, AppStrings.values.commandBarSettings),
            shortcut: shortcut('openSettings'),
          ),
        ],
      ),
    ];

    _showCascadingMenu(context, categories);
  }

  void _showCascadingMenu(
    BuildContext context,
    List<_MenuCategoryData> categories,
  ) {
    _CascadingMenuOverlay.show(context, categories, (cmd) {
      executeTerminalCommand(context, appState, cmd);
    });
  }

  // ─── Stage List ────────────────────────────────────────────────────

  Widget _buildStageList(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      itemCount: appState.terminalStages.length,
      itemBuilder: (context, index) {
        final stage = appState.terminalStages[index];
        return Padding(
          key: ValueKey('stage_${stage.id}_thumb_v${appState.thumbnailBackgroundVersion}'),
          padding: const EdgeInsets.only(bottom: 12),
          child: RepaintBoundary(child: _buildStageThumbnail(context, stage)),
        );
      },
    );
  }

  Widget _buildStageThumbnail(BuildContext context, TerminalStage stage) {
    final isActive = stage.id == appState.activeTerminalStageId;
    TerminalSession? session;
    for (final sid in stage.sessionIds) {
      final idx = appState.sessions.indexWhere((s) => s.id == sid);
      if (idx >= 0) {
        session = appState.sessions[idx];
        break;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: AnimatedScale(
        scale: isActive ? 1.03 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: isActive ? AppColors.grey300 : Colors.transparent,
              width: isActive ? 2 : 0,
            ),
            boxShadow: [
              if (isActive)
                ...AppShadows.customGlow(AppColors.grey300, opacity: 0.4, blur: 10, spread: 2)
              else
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg - (isActive ? 2 : 0)),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onStageClick(stage.id),
                onSecondaryTapDown: (details) =>
                    _showStageContextMenu(context, stage, details),
                child: Stack(
                  children: [
                    _buildThumbnailContent(stage, session),
                    if (isActive)
                      Positioned(
                        left: 0, top: 0, bottom: 0,
                        child: Container(
                          width: 5,
                          decoration: BoxDecoration(
                            color: AppColors.grey200,
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(AppRadius.lg - 2),
                              bottomLeft: Radius.circular(AppRadius.lg - 2),
                            ),
                          ),
                        ),
                      ),
                    if (isActive)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.grey100.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(AppRadius.lg - 2),
                          ),
                        ),
                      ),
                    if (!isActive)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(AppRadius.lg - 2),
                          ),
                        ),
                      ),
                    _buildGlassmorphism(),
                    _buildStageInfo(context, stage, session, isActive),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnailContent(TerminalStage stage, TerminalSession? session) {
    final bgPath = appState.showThumbnailBackground
        ? backgroundImagePathForStage(appState, stage)
        : null;

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: AppColors.terminalTreeBackground,
        child: Stack(
          children: [
            if (bgPath != null) buildStageBackgroundImage(bgPath),
            if (session == null)
              _buildEmptyThumbnail()
            else
              _buildSessionThumbnail(session, bgPath: bgPath),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyThumbnail() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.link_off, color: AppColors.terminalTreeMuted, size: 28),
          const SizedBox(height: 6),
          Text(
            l(appState, AppStrings.values.disconnected),
            style: AppTextStyles.captionSmall.copyWith(
              color: AppColors.terminalTreeMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionThumbnail(TerminalSession session, {String? bgPath}) {
    return SessionThumbnail(
      session: session,
      fontFamily:
          session.profile.fontFamily ?? appState.globalAppearance.fontFamily,
      backgroundOpacity: bgPath != null
          ? 1 - appState.terminalBackgroundOpacity
          : 1.0,
    );
  }

  Widget _buildGlassmorphism() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.05),
              Colors.white.withValues(alpha: 0.02),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStageInfo(
    BuildContext context,
    TerminalStage stage,
    TerminalSession? session,
    bool isActive,
  ) {
    final bool isConnected =
        session != null && session.tab.status == TerminalStatus.connected;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)],
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                stage.name,
                style: AppTextStyles.bodySmall.copyWith(
                  fontSize: 13,
                  color: Colors.white,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                  shadows: [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.8),
                      blurRadius: 4,
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (session != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: isConnected ? AppColors.success : AppColors.border,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                ),
                child: Icon(Icons.circle, size: 8, color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final count = appState.terminalStages.length;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            t(
              context,
              AppStrings.values.stageCountVar,
            ).replaceAll('{count}', '$count'),
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateStageDialog(BuildContext context) async {
    final name = await showInputDialog(
      context,
      title: t(context, AppStrings.values.createStageTitle),
      hint: t(context, AppStrings.values.enterStageName),
      initialValue: 'Stage ${appState.terminalStages.length + 1}',
      confirmText: t(context, AppStrings.values.create),
      cancelText: t(context, AppStrings.values.cancel),
    );
    if (name != null && name.trim().isNotEmpty) {
      appState.createTerminalStage(name.trim());
    }
  }

  void _showStageContextMenu(
    BuildContext context,
    TerminalStage stage,
    TapDownDetails details,
  ) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      details.globalPosition & const Size(1, 1),
      Offset.zero & overlay.size,
    );

    showStageCardContextMenu(
      context: context,
      appState: appState,
      stage: stage,
      position: position,
      includeBackground: true,
      onBackgroundTap: () => showStageBackgroundPicker(context, appState, stage),
      selectBackgroundLabel: t(context, AppStrings.values.selectBackground),
      renameLabel: t(context, AppStrings.values.renameStage),
      renameTitle: l(appState, AppStrings.values.renameStageTitle),
      renameConfirm: l(appState, AppStrings.values.rename),
      renameCancel: l(appState, AppStrings.values.cancel),
      closeSessionLabel: l(appState, AppStrings.values.commandBarCloseSession),
      deleteLabel: t(context, AppStrings.values.deleteStage),
      deleteTitle: l(appState, AppStrings.values.deleteStage),
      deleteMessage: l(appState, AppStrings.values.deleteVar),
      deleteConfirm: l(appState, AppStrings.values.delete),
      deleteCancel: l(appState, AppStrings.values.cancel),
    );
  }

}

// ─── Cascading Command Menu ─────────────────────────────────────────

class _MenuCategoryData {
  final String id;
  final IconData icon;
  final String label;
  final List<_MenuItemData> items;
  const _MenuCategoryData(this.id, this.icon, this.label, this.items);
}

class _MenuItemData {
  final String id;
  final IconData icon;
  final String label;
  final String? shortcut;
  const _MenuItemData(this.id, this.icon, this.label, {this.shortcut});
}

/// Shows a cascading two-level popup menu anchored near the sidebar header.
/// Uses OverlayEntry with positioning relative to the Overlay's Stack.
class _CascadingMenuOverlay extends StatefulWidget {
  const _CascadingMenuOverlay({
    required this.categories,
    required this.anchorDx,
    required this.anchorDy,
    required this.onDismiss,
    required this.onCommand,
  });

  final List<_MenuCategoryData> categories;
  final double anchorDx;
  final double anchorDy;
  final VoidCallback onDismiss;
  final ValueChanged<String> onCommand;

  /// Show the cascading menu. Anchors at (anchorDx, anchorDy) relative to
  /// the Overlay's Stack origin (typically screen top-left).
  static void show(
    BuildContext context,
    List<_MenuCategoryData> categories,
    ValueChanged<String> onCommand,
  ) {
    final overlay = Overlay.of(context);
    // Default anchor: a few pixels from top-left of the overlay
    const double left = 4;
    const double top = 40;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _CascadingMenuOverlay(
        categories: categories,
        anchorDx: left,
        anchorDy: top,
        onDismiss: () => entry.remove(),
        onCommand: (cmd) {
          entry.remove();
          onCommand(cmd);
        },
      ),
    );
    overlay.insert(entry);
  }

  @override
  State<_CascadingMenuOverlay> createState() => _CascadingMenuOverlayState();
}

class _CascadingMenuOverlayState extends State<_CascadingMenuOverlay> {
  String? _hoveredCategory;
  Timer? _exitTimer;

  static const double _level1Width = 120;
  static const double _level2Width = 220;
  static const double _itemHeight = 34;

  int get _hoveredIndex {
    if (_hoveredCategory == null) return -1;
    return widget.categories.indexWhere((c) => c.id == _hoveredCategory);
  }

  void _onCategoryEnter(String id) {
    _exitTimer?.cancel();
    if (_hoveredCategory != id) setState(() => _hoveredCategory = id);
  }

  void _onCategoryExit() {
    _exitTimer?.cancel();
    _exitTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _hoveredCategory = null);
    });
  }

  void _onLevel2Enter() => _exitTimer?.cancel();

  void _onLevel2Exit() {
    _exitTimer?.cancel();
    _exitTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _hoveredCategory = null);
    });
  }

  @override
  void dispose() {
    _exitTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: widget.onDismiss,
          child: Container(color: Colors.transparent),
        ),
        // Level 1 menu
        Positioned(
          left: widget.anchorDx,
          top: widget.anchorDy,
          child: Material(
            type: MaterialType.card,
            color: AppColors.cardBackground,
            elevation: 12,
            shadowColor: Colors.black.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              side: BorderSide(color: AppColors.border.withValues(alpha: 0.6)),
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: _level1Width,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final cat in widget.categories) _buildCategoryItem(cat),
                ],
              ),
            ),
          ),
        ),
        // Level 2 menu – shown to the right of hovered category
        if (_hoveredCategory != null && _hoveredIndex >= 0)
          Positioned(
            left: widget.anchorDx + _level1Width + 4,
            top: widget.anchorDy + (_hoveredIndex * _itemHeight),
            child: MouseRegion(
              onEnter: (_) => _onLevel2Enter(),
              onExit: (_) => _onLevel2Exit(),
              child: Material(
                type: MaterialType.card,
                color: AppColors.cardBackground,
                elevation: 12,
                shadowColor: Colors.black.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  side: BorderSide(
                    color: AppColors.border.withValues(alpha: 0.6),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  width: _level2Width,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final item in _hoveredItems) _buildItemRow(item),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<_MenuItemData> get _hoveredItems {
    final cat = widget.categories
        .where((c) => c.id == _hoveredCategory)
        .firstOrNull;
    return cat?.items ?? [];
  }

  Widget _buildCategoryItem(_MenuCategoryData cat) {
    final isHovered = _hoveredCategory == cat.id;
    return MouseRegion(
      onEnter: (_) => _onCategoryEnter(cat.id),
      onExit: (_) => _onCategoryExit(),
      child: InkWell(
        onTap: () => _onCategoryEnter(cat.id),
        child: Container(
          height: _itemHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          color: isHovered
              ? AppColors.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          child: Row(
            children: [
              Icon(
                cat.icon,
                size: 16,
                color: isHovered ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  cat.label,
                  style: AppTextStyles.caption.copyWith(
                    color: isHovered
                        ? AppColors.primary
                        : AppColors.textPrimary,
                    fontWeight: isHovered ? FontWeight.w600 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemRow(_MenuItemData item) {
    return InkWell(
      onTap: () => widget.onCommand(item.id),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Icon(item.icon, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.label,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (item.shortcut != null) ...[
              const SizedBox(width: 8),
              Text(
                item.shortcut!,
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: Colors.grey.shade400,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}



