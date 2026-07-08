import 'package:flutter/material.dart';

@immutable
class OverflowGuardItem {
  const OverflowGuardItem({required this.child, required this.estimatedWidth});

  final Widget child;
  final double estimatedWidth;
}

class OverflowGuardRow extends StatelessWidget {
  const OverflowGuardRow({
    super.key,
    required this.items,
    this.spacing = 8,
    this.safety = 4,
    this.mainAxisAlignment = MainAxisAlignment.start,
  });

  final List<OverflowGuardItem> items;
  final double spacing;
  final double safety;
  final MainAxisAlignment mainAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final visible = <Widget>[];
        var used = 0.0;
        for (final item in items) {
          final need = visible.isEmpty
              ? item.estimatedWidth
              : spacing + item.estimatedWidth;
          if (used + need + safety > constraints.maxWidth) {
            break;
          }
          if (visible.isNotEmpty) {
            visible.add(SizedBox(width: spacing));
            used += spacing;
          }
          visible.add(item.child);
          used += item.estimatedWidth;
        }
        return Row(mainAxisAlignment: mainAxisAlignment, children: visible);
      },
    );
  }
}

double estimateIconLabelButtonWidth(
  BuildContext context,
  String label, {
  TextStyle? textStyle,
  double horizontalPadding = 12,
  double iconWidth = 16,
  double iconLabelSpacing = 8,
  double minWidth = 64,
}) {
  final style =
      textStyle ??
      Theme.of(context).textTheme.labelLarge ??
      const TextStyle(fontSize: 14, fontWeight: FontWeight.w500);
  final painter = TextPainter(
    text: TextSpan(text: label, style: style),
    maxLines: 1,
    textDirection: Directionality.of(context),
  )..layout();
  final width =
      horizontalPadding +
      iconWidth +
      iconLabelSpacing +
      painter.width +
      horizontalPadding;
  return width < minWidth ? minWidth : width;
}
