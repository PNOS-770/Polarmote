import 'package:flutter/material.dart';

class OverflowOverlay extends StatelessWidget {
  const OverflowOverlay({super.key, required this.child, this.enabled = false});

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
            ),
          ),
        ),
      ],
    );
  }
}
