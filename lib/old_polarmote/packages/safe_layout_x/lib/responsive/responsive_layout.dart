import 'package:flutter/widgets.dart';

import 'layout_breakpoints.dart';

typedef ResponsiveBuilder = Widget Function(BuildContext context);

class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({
    super.key,
    required this.compact,
    required this.normal,
    this.wide,
  });

  final ResponsiveBuilder compact;
  final ResponsiveBuilder normal;
  final ResponsiveBuilder? wide;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < LayoutBreakpoints.compactWidth) {
      return compact(context);
    }
    if (width > 1400 && wide != null) {
      return wide!(context);
    }
    return normal(context);
  }
}
