import 'package:flutter/material.dart';

import '../containers/auto_safe.dart';
import '../containers/safe_container.dart';
import '../text/safe_text.dart';
import 'shell_models.dart';

class SafeDesktopShell extends StatelessWidget {
  const SafeDesktopShell({
    super.key,
    required this.navItems,
    required this.main,
    this.secondaryPane,
    this.footerNavItems = const <ShellNavItem>[],
    this.backgroundColor = const Color(0xFFF6F6F6),
    this.railWidth = 60,
    this.onRailPointerDown,
    this.railStyle = const SafeDesktopRailStyle(),
  });

  final List<ShellNavItem> navItems;
  final Widget main;
  final Widget? secondaryPane;
  final List<ShellNavItem> footerNavItems;
  final Color backgroundColor;
  final double railWidth;
  final VoidCallback? onRailPointerDown;
  final SafeDesktopRailStyle railStyle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: AutoSafe(
        child: Row(
          children: [
            Listener(
              onPointerDown: (_) => onRailPointerDown?.call(),
              behavior: HitTestBehavior.translucent,
              child: SafeContainer(
                width: railWidth,
                decoration: BoxDecoration(
                  color: railStyle.railBackgroundColor,
                  border: Border(
                    right: BorderSide(color: railStyle.railBorderColor),
                  ),
                ),
                child: Column(
                  children: [
                    SizedBox(height: railStyle.topPadding),
                    for (final item in navItems)
                      _DesktopRailButton(item: item, style: railStyle),
                    if (footerNavItems.isNotEmpty) ...[
                      const Spacer(),
                      for (final item in footerNavItems)
                        _DesktopRailButton(item: item, style: railStyle),
                      SizedBox(height: railStyle.bottomPadding),
                    ],
                  ],
                ),
              ),
            ),
            if (secondaryPane != null) secondaryPane!,
            Expanded(child: main),
          ],
        ),
      ),
    );
  }
}

class _DesktopRailButton extends StatelessWidget {
  const _DesktopRailButton({required this.item, required this.style});

  final ShellNavItem item;
  final SafeDesktopRailStyle style;

  @override
  Widget build(BuildContext context) {
    final color = item.selected ? style.selectedColor : style.unselectedColor;
    final icon =
        item.iconBuilder?.call(context, item.selected, color, style.iconSize) ??
        Icon(item.icon, size: style.iconSize, color: color);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: style.itemVerticalGap),
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(style.itemBorderRadius),
        child: SafeContainer(
          width: style.itemWidth,
          height: style.itemHeight,
          decoration: BoxDecoration(
            color: item.selected ? style.selectedBackgroundColor : null,
            borderRadius: BorderRadius.circular(style.itemBorderRadius),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (item.overlay != null)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(style.itemBorderRadius),
                    child: item.overlay!,
                  ),
                ),
              Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  icon,
                  const SizedBox(height: 3),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SafeText(
                        item.label,
                        style: TextStyle(
                          fontSize: style.labelFontSize,
                          color: color,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
