import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../containers/safe_container.dart';

@immutable
class SafeTabItem {
  const SafeTabItem({
    required this.id,
    required this.title,
    required this.active,
    this.statusColor,
    this.onTap,
    this.onDoubleTap,
    this.onClose,
  });

  final String id;
  final String title;
  final bool active;
  final Color? statusColor;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onClose;
}

class SafeTabBar extends StatefulWidget {
  const SafeTabBar({
    super.key,
    required this.items,
    this.height = 34,
    this.baseItemWidth = 220,
    this.minItemWidth = 90,
    this.backgroundColor = const Color(0xFFFFFFFF),
    this.borderColor = const Color(0xFFE0E0E0),
    this.activeBorderColor = const Color(0xFF4D7CFE),
    this.activeTabColor,
    this.inactiveTabColor,
    this.hoverTabColor,
    this.textStyle,
    this.inactiveTextStyle,
    this.closeIconColor,
    this.showCloseOnHover = true,
    this.onAdd,
    this.onEmptyDoubleTap,
  });

  final List<SafeTabItem> items;
  final double height;
  final double baseItemWidth;
  final double minItemWidth;
  final Color backgroundColor;
  final Color borderColor;
  final Color activeBorderColor;
  final Color? activeTabColor;
  final Color? inactiveTabColor;
  final Color? hoverTabColor;
  final TextStyle? textStyle;
  final TextStyle? inactiveTextStyle;
  final Color? closeIconColor;
  final bool showCloseOnHover;
  final VoidCallback? onAdd;
  final VoidCallback? onEmptyDoubleTap;

  @override
  State<SafeTabBar> createState() => _SafeTabBarState();
}

class _SafeTabBarState extends State<SafeTabBar> {
  int? _hoveredIndex;
  int? _lastEmptyTapMs;
  Offset? _lastEmptyTapPos;

  void _setHovered(int index, bool hovered) {
    if (hovered) {
      if (_hoveredIndex == index) return;
      setState(() => _hoveredIndex = index);
      return;
    }
    if (_hoveredIndex == index) {
      setState(() => _hoveredIndex = null);
    }
  }

  void _handleEmptyAreaTap({
    required PointerDownEvent event,
    required double tabsTotalWidth,
    required double availableWidth,
  }) {
    if (widget.onEmptyDoubleTap == null) return;
    if (event.kind == PointerDeviceKind.mouse &&
        (event.buttons & kPrimaryMouseButton) == 0) {
      return;
    }

    final dx = event.localPosition.dx;
    final isEmptyArea = dx > tabsTotalWidth && dx < availableWidth;
    if (!isEmptyArea) {
      _lastEmptyTapMs = null;
      _lastEmptyTapPos = null;
      return;
    }

    final nowMs = event.timeStamp.inMilliseconds;
    final lastMs = _lastEmptyTapMs;
    final lastPos = _lastEmptyTapPos;
    if (lastMs != null &&
        nowMs - lastMs <= 300 &&
        lastPos != null &&
        (event.localPosition - lastPos).distance <= 6) {
      _lastEmptyTapMs = null;
      _lastEmptyTapPos = null;
      widget.onEmptyDoubleTap?.call();
      return;
    }

    _lastEmptyTapMs = nowMs;
    _lastEmptyTapPos = event.localPosition;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final addButtonSize = widget.onAdd == null ? 0.0 : (widget.height - 10);
        final addButtonGap = widget.onAdd == null ? 0.0 : 8.0;
        final available =
            (constraints.maxWidth - 16 - addButtonSize - addButtonGap)
                .clamp(0, double.infinity)
                .toDouble();
        final hasItems = widget.items.isNotEmpty;
        final count = hasItems ? widget.items.length : 1;
        const gap = 6.0;
        final availableForTabs =
            (available - gap * (count - 1)).clamp(0.0, double.infinity);
        final tabWidth =
            (availableForTabs / count).clamp(widget.minItemWidth, widget.baseItemWidth);
        final tabsTotalWidth = hasItems
            ? (widget.items.length * tabWidth + gap * (widget.items.length - 1))
            : 0.0;
        final isDark = widget.backgroundColor.computeLuminance() < 0.5;
        final resolvedActive = widget.activeTabColor ??
            _shiftLightnessForLightBg(
              widget.backgroundColor,
              isDark,
              lightFallback: const Color(0xFFE2E2E2),
              darkShift: 0.12,
              lightShift: -0.18,
            );
        final resolvedInactive = widget.inactiveTabColor ??
            _shiftLightnessForLightBg(
              widget.backgroundColor,
              isDark,
              lightFallback: const Color(0xFFF1F1F1),
              darkShift: 0.06,
              lightShift: -0.12,
            );
        final baseText = isDark
            ? const Color(0xFFE7E7E7)
            : const Color(0xFF1E1E1E);
        final resolvedTextStyle =
            (widget.textStyle ?? const TextStyle(fontSize: 12)).copyWith(
          color: baseText,
          fontWeight: FontWeight.w500,
        );
        final resolvedInactiveTextStyle =
            (widget.inactiveTextStyle ?? const TextStyle(fontSize: 12)).copyWith(
          color: baseText.withValues(alpha: 0.78),
          fontWeight: FontWeight.w500,
        );
        final resolvedCloseColor =
            widget.closeIconColor ?? baseText.withValues(alpha: 0.7);
        final dividerColor = isDark
            ? _shiftLightness(widget.backgroundColor, 0.18).withValues(alpha: 0.95)
            : const Color(0xFFBDBDBD);
        final resolvedAddColor = _shiftLightness(widget.backgroundColor, 0.1);
        final resolvedAddHover = _shiftLightness(widget.backgroundColor, 0.16);
        final resolvedAddBorder = _shiftLightness(widget.backgroundColor, 0.2);

        return SafeContainer(
          height: widget.height,
          decoration: BoxDecoration(
            color: widget.backgroundColor,
            border: Border(bottom: BorderSide(color: widget.borderColor)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) {
                    if (tabsTotalWidth >= available) return;
                    _handleEmptyAreaTap(
                      event: event,
                      tabsTotalWidth: tabsTotalWidth,
                      availableWidth: available,
                    );
                  },
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int i = 0; i < widget.items.length; i++) ...[
                          if (i > 0)
                            _TabDividerGap(
                              width: gap,
                              height: widget.height,
                              color: dividerColor,
                            ),
                          _SafeTabChip(
                            width: tabWidth,
                            height: widget.height,
                            item: widget.items[i],
                            activeTabColor: resolvedActive,
                            inactiveTabColor: resolvedInactive,
                            textStyle: resolvedTextStyle,
                            inactiveTextStyle: resolvedInactiveTextStyle,
                            closeIconColor: resolvedCloseColor,
                            showCloseOnHover: widget.showCloseOnHover,
                            isHovered: _hoveredIndex == i,
                            onHoverChanged: (hovered) =>
                                _setHovered(i, hovered),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (widget.onAdd != null)
                Padding(
                  padding: EdgeInsets.only(left: addButtonGap),
                  child: _AddTabButton(
                    size: addButtonSize,
                    color: resolvedAddColor,
                    hoverColor: resolvedAddHover,
                    borderColor: resolvedAddBorder,
                    iconColor: baseText.withValues(alpha: 0.9),
                    onPressed: widget.onAdd,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

}

class _SafeTabChip extends StatelessWidget {
  const _SafeTabChip({
    required this.width,
    required this.height,
    required this.item,
    required this.activeTabColor,
    required this.inactiveTabColor,
    required this.textStyle,
    required this.inactiveTextStyle,
    required this.closeIconColor,
    required this.showCloseOnHover,
    required this.isHovered,
    required this.onHoverChanged,
  });

  final double width;
  final double height;
  final SafeTabItem item;
  final Color activeTabColor;
  final Color inactiveTabColor;
  final TextStyle textStyle;
  final TextStyle inactiveTextStyle;
  final Color closeIconColor;
  final bool showCloseOnHover;
  final bool isHovered;
  final ValueChanged<bool> onHoverChanged;

  @override
  Widget build(BuildContext context) {
    final isActive = item.active;
    final showClose =
        item.onClose != null && (!showCloseOnHover || isActive || isHovered);
    final background = isActive ? activeTabColor : inactiveTabColor;
    final radius = isActive ? 9.0 : 0.0;
    final inset = isActive ? 0.0 : 0.0;
    final textStyle = isActive ? this.textStyle : inactiveTextStyle;
    return MouseRegion(
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      cursor: SystemMouseCursors.click,
      child: Listener(
        onPointerDown: (event) {
          if (event.kind == PointerDeviceKind.mouse &&
              event.buttons == kMiddleMouseButton) {
            item.onClose?.call();
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: (_) => item.onTap?.call(),
          onDoubleTap: item.onDoubleTap,
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  left: inset,
                  right: inset,
                  top: inset,
                  bottom: inset,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                    transform: isActive
                        ? Matrix4.translationValues(0, -1, 0)
                        : null,
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: BorderRadius.circular(radius),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  child: Row(
                    children: [
                      if (item.statusColor != null)
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: item.statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      if (item.statusColor != null) const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.title,
                          style: textStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (item.onClose != null)
                        AnimatedOpacity(
                          opacity: showClose ? 1 : 0,
                          duration: const Duration(milliseconds: 120),
                          curve: Curves.easeOut,
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: item.onClose,
                            child: Icon(
                              Icons.close_rounded,
                              size: 14,
                              color: closeIconColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (isActive)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 2,
                    child: ColoredBox(color: background),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabDividerGap extends StatelessWidget {
  const _TabDividerGap({
    required this.width,
    required this.height,
    required this.color,
  });

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Center(
        child: Container(
          width: 1,
          height: 22,
          color: color,
        ),
      ),
    );
  }
}

Color _shiftLightness(Color color, double amount) {
  final hsl = HSLColor.fromColor(color);
  final lightness = (hsl.lightness + amount).clamp(0.0, 1.0);
  return hsl.withLightness(lightness).toColor();
}

Color _shiftLightnessForLightBg(
  Color color,
  bool isDark, {
  required Color lightFallback,
  required double darkShift,
  required double lightShift,
}) {
  if (isDark) return _shiftLightness(color, darkShift);
  final hsl = HSLColor.fromColor(color);
  if (hsl.lightness >= 0.92) return lightFallback;
  return _shiftLightness(color, lightShift);
}

class _AddTabButton extends StatefulWidget {
  const _AddTabButton({
    required this.size,
    required this.color,
    required this.hoverColor,
    required this.borderColor,
    required this.iconColor,
    required this.onPressed,
  });

  final double size;
  final Color color;
  final Color hoverColor;
  final Color borderColor;
  final Color iconColor;
  final VoidCallback? onPressed;

  @override
  State<_AddTabButton> createState() => _AddTabButtonState();
}

class _AddTabButtonState extends State<_AddTabButton> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final background = _hovered ? widget.hoverColor : widget.color;
    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: widget.borderColor),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            Icons.add_rounded,
            size: 16,
            color: widget.iconColor,
          ),
        ),
      ),
    );
  }
}
