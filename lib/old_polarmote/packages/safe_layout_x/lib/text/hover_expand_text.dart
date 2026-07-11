import 'package:flutter/widgets.dart';

import 'measured_text.dart';

class HoverExpandText extends StatelessWidget {
  const HoverExpandText(
    this.data, {
    super.key,
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
  });

  final String data;
  final TextStyle? style;
  final int maxLines;
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    return MeasuredText(
      data,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      tooltipWhenOverflow: true,
    );
  }
}
