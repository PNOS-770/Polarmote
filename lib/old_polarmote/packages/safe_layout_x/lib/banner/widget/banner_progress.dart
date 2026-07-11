import 'package:flutter/material.dart';

import '../theme/banner_theme.dart';

class BannerProgress extends StatelessWidget {
  const BannerProgress({super.key, required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0, 1).toDouble();
    final theme = BannerTheme.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        minHeight: 6,
        value: clamped,
        backgroundColor: theme.progressBackground,
        color: primary,
      ),
    );
  }
}
