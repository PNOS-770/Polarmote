import 'package:flutter/material.dart';

import '../containers/safe_container.dart';
import '../foundation/overflow_guard.dart';
import '../foundation/overflow_guard_row.dart';

@immutable
class SafeActionBarItem {
  const SafeActionBarItem({required this.child, required this.estimatedWidth});

  final Widget child;
  final double estimatedWidth;
}

class SafeActionBar extends StatelessWidget {
  const SafeActionBar({
    super.key,
    required this.items,
    this.height = 56,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
    this.backgroundColor = Colors.white,
    this.borderColor = const Color(0xFFE0E0E0),
    this.spacing = 8,
    this.safety = 4,
  });

  final List<SafeActionBarItem> items;
  final double height;
  final EdgeInsets padding;
  final Color backgroundColor;
  final Color borderColor;
  final double spacing;
  final double safety;

  @override
  Widget build(BuildContext context) {
    return SafeContainer(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: OverflowGuard(
        child: OverflowGuardRow(
          spacing: spacing,
          safety: safety,
          items: [
            for (final item in items)
              OverflowGuardItem(
                child: item.child,
                estimatedWidth: item.estimatedWidth,
              ),
          ],
        ),
      ),
    );
  }
}
