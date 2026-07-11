import 'package:flutter/material.dart';

import '../model/banner_data.dart';
import '../theme/banner_theme.dart';

class BannerIcon extends StatelessWidget {
  const BannerIcon({super.key, required this.type});

  final BannerType type;

  @override
  Widget build(BuildContext context) {
    final theme = BannerTheme.of(context);
    final color = theme.accentColor(type, context);
    final icon = switch (type) {
      BannerType.success => Icons.check_circle,
      BannerType.error => Icons.error,
      BannerType.warning => Icons.warning,
      BannerType.info => Icons.info,
      BannerType.progress => Icons.sync,
    };
    return Icon(icon, size: 18, color: color);
  }
}
