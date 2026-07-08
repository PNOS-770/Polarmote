import 'package:flutter/material.dart';

import '../containers/safe_container.dart';

class SafeStatusBar extends StatelessWidget {
  const SafeStatusBar({
    super.key,
    required this.text,
    this.height = 28,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
    this.backgroundColor = Colors.white,
    this.borderColor = const Color(0xFFE0E0E0),
    this.style = const TextStyle(fontSize: 12),
    this.textAlign = TextAlign.left,
  });

  final String text;
  final double height;
  final EdgeInsets padding;
  final Color backgroundColor;
  final Color borderColor;
  final TextStyle style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return SafeContainer(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: style,
              textAlign: textAlign,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
