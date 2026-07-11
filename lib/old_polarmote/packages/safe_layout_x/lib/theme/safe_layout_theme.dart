import 'package:flutter/widgets.dart';

@immutable
class SafeLayoutThemeData {
  const SafeLayoutThemeData({
    this.panelPadding = const EdgeInsets.all(12),
    this.dockSpacing = 8,
    this.tooltipDelay = const Duration(milliseconds: 500),
    this.minimumPanelSize = const Size(240, 160),
  });

  final EdgeInsets panelPadding;
  final double dockSpacing;
  final Duration tooltipDelay;
  final Size minimumPanelSize;
}

class SafeLayoutTheme extends InheritedWidget {
  const SafeLayoutTheme({super.key, required this.data, required super.child});

  final SafeLayoutThemeData data;

  static SafeLayoutThemeData of(BuildContext context) {
    final theme = context.dependOnInheritedWidgetOfExactType<SafeLayoutTheme>();
    return theme?.data ?? const SafeLayoutThemeData();
  }

  @override
  bool updateShouldNotify(SafeLayoutTheme oldWidget) {
    return oldWidget.data != data;
  }
}
