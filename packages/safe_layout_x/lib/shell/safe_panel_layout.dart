import 'package:flutter/widgets.dart';

class SafePanelLayout extends StatelessWidget {
  const SafePanelLayout({
    super.key,
    this.top,
    this.tabBar,
    required this.body,
    this.bottom,
  });

  final Widget? top;
  final Widget? tabBar;
  final Widget body;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (top != null) top!,
        if (tabBar != null) tabBar!,
        Expanded(child: body),
        if (bottom != null) bottom!,
      ],
    );
  }
}
