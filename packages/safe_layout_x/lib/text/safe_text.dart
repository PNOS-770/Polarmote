import 'package:flutter/widgets.dart';

class SafeText extends StatelessWidget {
  const SafeText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.softWrap = false,
  });

  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow overflow;
  final bool? softWrap;

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      softWrap: softWrap,
    );
  }
}
