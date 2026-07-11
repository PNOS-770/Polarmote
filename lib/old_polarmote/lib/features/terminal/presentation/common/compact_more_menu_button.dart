import 'package:flutter/material.dart';

class CompactMoreMenuButton extends StatelessWidget {
  const CompactMoreMenuButton({
    super.key,
    required this.tooltip,
    required this.onTapDown,
    this.icon = Icons.more_horiz,
    this.iconSize = 17,
    this.padding = 4,
    this.iconColor,
  });

  final String tooltip;
  final void Function(TapDownDetails details) onTapDown;
  final IconData icon;
  final double iconSize;
  final double padding;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTapDown: onTapDown,
        onSecondaryTapDown: onTapDown,
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: Icon(
            icon,
            size: iconSize,
            color: iconColor ?? Colors.grey[600],
          ),
        ),
      ),
    );
  }
}
