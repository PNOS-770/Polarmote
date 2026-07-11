import 'package:flutter/widgets.dart';

enum SafePaneDividerAlignment { start, center, end }

typedef SafeDesktopRevealButtonBuilder =
    Widget Function(BuildContext context, VoidCallback onPressed);
typedef ShellNavIconBuilder =
    Widget Function(
      BuildContext context,
      bool selected,
      Color color,
      double size,
    );

@immutable
class ShellNavItem {
  const ShellNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.iconBuilder,
    this.overlay,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ShellNavIconBuilder? iconBuilder;
  final Widget? overlay;
}

@immutable
class SafeDesktopRailStyle {
  const SafeDesktopRailStyle({
    this.railBackgroundColor = const Color(0xFFFFFFFF),
    this.railBorderColor = const Color(0xFFE0E0E0),
    this.selectedColor = const Color(0xFF1976D2),
    this.unselectedColor = const Color(0xFF616161),
    this.selectedBackgroundColor = const Color(0x1A1976D2),
    this.itemWidth = 48,
    this.itemHeight = 46,
    this.itemBorderRadius = 10,
    this.iconSize = 16,
    this.labelFontSize = 9,
    this.itemVerticalGap = 4,
    this.topPadding = 12,
    this.bottomPadding = 12,
  });

  final Color railBackgroundColor;
  final Color railBorderColor;
  final Color selectedColor;
  final Color unselectedColor;
  final Color selectedBackgroundColor;
  final double itemWidth;
  final double itemHeight;
  final double itemBorderRadius;
  final double iconSize;
  final double labelFontSize;
  final double itemVerticalGap;
  final double topPadding;
  final double bottomPadding;
}

@immutable
class SafeMobileShellStyle {
  const SafeMobileShellStyle({
    this.selectedColor = const Color(0xFF1976D2),
    this.unselectedColor = const Color(0xFF616161),
    this.showDivider = true,
  });

  final Color selectedColor;
  final Color unselectedColor;
  final bool showDivider;
}

@immutable
class SafeResizablePaneStyle {
  const SafeResizablePaneStyle({
    this.dividerHitWidth = 10,
    this.dividerLineWidth = 1,
    this.dividerHoverLineWidth = 4,
    this.dividerLineAlignment = SafePaneDividerAlignment.center,
    this.showDividerLine = false,
    this.dividerColor = const Color(0xFFE0E0E0),
    this.dividerHoverColor = const Color(0xFFBDBDBD),
    this.handleDotColor = const Color(0xFFBDBDBD),
    this.handleDotHoverColor = const Color(0xFF8C8C8C),
    this.showHandle = false,
    this.handleWidth = 16,
    this.handleHeight = 28,
    this.handleDotSize = 4,
    this.handleDotGap = 4,
    this.animationDuration = const Duration(milliseconds: 120),
  });

  final double dividerHitWidth;
  final double dividerLineWidth;
  final double dividerHoverLineWidth;
  final SafePaneDividerAlignment dividerLineAlignment;
  final bool showDividerLine;
  final Color dividerColor;
  final Color dividerHoverColor;
  final Color handleDotColor;
  final Color handleDotHoverColor;
  final bool showHandle;
  final double handleWidth;
  final double handleHeight;
  final double handleDotSize;
  final double handleDotGap;
  final Duration animationDuration;
}

@immutable
class SafeDesktopPaneLayoutConfig {
  const SafeDesktopPaneLayoutConfig({
    this.initialPaneWidth = 320,
    this.mainInitialWidth,
    this.paneMinWidth = 300,
    this.paneMaxWidth = double.infinity,
    this.mainMinWidth = 150,
    this.collapseSnapWidth = 0,
    this.edgeSnapWidth = 64,
    this.revealToken,
    this.paneStyle = const SafeResizablePaneStyle(),
    this.mainBackgroundColor = const Color(0xFFFFFFFF),
    this.mainEdgeLineColor,
    this.showRevealButton = true,
    this.revealButtonBuilder,
    this.animationDuration,
    this.dragOverlayColor = const Color(0x60BDBDBD),
  });

  final double initialPaneWidth;
  final double? mainInitialWidth;
  final double paneMinWidth;
  final double paneMaxWidth;
  final double mainMinWidth;
  final double collapseSnapWidth;
  final double edgeSnapWidth;
  final Object? revealToken;
  final SafeResizablePaneStyle paneStyle;
  final Color mainBackgroundColor;
  final Color? mainEdgeLineColor;
  final bool showRevealButton;
  final SafeDesktopRevealButtonBuilder? revealButtonBuilder;
  final Duration? animationDuration;
  final Color dragOverlayColor;
}
