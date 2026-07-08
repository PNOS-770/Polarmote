import 'package:flutter/material.dart';

class MeasuredText extends StatelessWidget {
  const MeasuredText(
    this.data, {
    super.key,
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.softWrap = false,
    this.tooltipWhenOverflow = true,
  });

  final String data;
  final TextStyle? style;
  final int maxLines;
  final TextOverflow overflow;
  final bool softWrap;
  final bool tooltipWhenOverflow;

  bool _isOverflowing(BuildContext context, BoxConstraints constraints) {
    final painter = TextPainter(
      text: TextSpan(text: data, style: style),
      maxLines: maxLines,
      textDirection: Directionality.of(context),
    )..layout(maxWidth: constraints.maxWidth);
    return painter.didExceedMaxLines;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final text = Text(
          data,
          style: style,
          maxLines: maxLines,
          overflow: overflow,
          softWrap: softWrap,
        );
        if (!tooltipWhenOverflow) return text;
        if (!_isOverflowing(context, constraints)) return text;
        return Tooltip(message: data, child: text);
      },
    );
  }
}
