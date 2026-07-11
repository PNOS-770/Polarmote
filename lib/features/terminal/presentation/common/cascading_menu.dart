import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../shared/design_system/design_system.dart';

class MenuCategoryData {
  final String id;
  final IconData icon;
  final String label;
  final List<MenuItemData> items;
  const MenuCategoryData(this.id, this.icon, this.label, this.items);
}

class MenuItemData {
  final String id;
  final IconData icon;
  final String label;
  final String? shortcut;
  const MenuItemData(this.id, this.icon, this.label, {this.shortcut});
}

class CascadingMenuOverlay extends StatefulWidget {
  const CascadingMenuOverlay({
    super.key,
    required this.categories,
    required this.anchorDx,
    required this.anchorDy,
    required this.onDismiss,
    required this.onCommand,
  });

  final List<MenuCategoryData> categories;
  final double anchorDx;
  final double anchorDy;
  final VoidCallback onDismiss;
  final ValueChanged<String> onCommand;

  static void show(
    BuildContext context,
    List<MenuCategoryData> categories,
    ValueChanged<String> onCommand, {
    double left = 4,
    double top = 40,
  }) {
    final overlay = Overlay.of(context);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => CascadingMenuOverlay(
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
  State<CascadingMenuOverlay> createState() => _CascadingMenuOverlayState();
}

class _CascadingMenuOverlayState extends State<CascadingMenuOverlay> {
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

  List<MenuItemData> get _hoveredItems {
    final cat = widget.categories
        .where((c) => c.id == _hoveredCategory)
        .firstOrNull;
    return cat?.items ?? [];
  }

  Widget _buildCategoryItem(MenuCategoryData cat) {
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

  Widget _buildItemRow(MenuItemData item) {
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
