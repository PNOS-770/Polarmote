import 'package:flutter/material.dart';

import '../model/banner_data.dart';

@immutable
class BannerThemeData {
  const BannerThemeData({
    required this.backgroundColor,
    required this.titleStyle,
    required this.messageStyle,
    required this.borderRadius,
    required this.shadow,
    required this.progressBackground,
    required this.successBackground,
    required this.errorBackground,
    required this.warningBackground,
    required this.infoBackground,
  });

  final Color backgroundColor;
  final TextStyle titleStyle;
  final TextStyle messageStyle;
  final BorderRadius borderRadius;
  final BoxShadow shadow;
  final Color progressBackground;
  final Color successBackground;
  final Color errorBackground;
  final Color warningBackground;
  final Color infoBackground;

  Color accentColor(BannerType type, BuildContext context) {
    return switch (type) {
      BannerType.success => const Color(0xFF2F7A53),
      BannerType.error => const Color(0xFFB04444),
      BannerType.warning => const Color(0xFFB7791F),
      BannerType.info => const Color(0xFF2F647D),
      BannerType.progress => const Color(0xFF0F766E),
    };
  }

  Color backgroundFor(BannerType type) {
    return switch (type) {
      BannerType.success => successBackground,
      BannerType.error => errorBackground,
      BannerType.warning => warningBackground,
      BannerType.info => infoBackground,
      BannerType.progress => progressBackground,
    };
  }

  static BannerThemeData fallback(BuildContext context) {
    final theme = Theme.of(context);
    return BannerThemeData(
      backgroundColor: const Color(0xFFFBFCFC),
      titleStyle:
          theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: const Color(0xFF223238),
          ) ??
          const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF223238),
          ),
      messageStyle:
          theme.textTheme.bodySmall?.copyWith(color: const Color(0xFF5E727A)) ??
          const TextStyle(fontSize: 12, color: Color(0xFF5E727A)),
      borderRadius: BorderRadius.circular(12),
      shadow: const BoxShadow(
        color: Color(0x14000000),
        blurRadius: 16,
        offset: Offset(0, 6),
      ),
      progressBackground: const Color(0xFFEDF6F5),
      successBackground: const Color(0xFFEEF8F2),
      errorBackground: const Color(0xFFFDEEEE),
      warningBackground: const Color(0xFFFFF7E8),
      infoBackground: const Color(0xFFEEF5F8),
    );
  }
}

class BannerTheme extends InheritedWidget {
  const BannerTheme({super.key, required super.child, required this.data});

  final BannerThemeData data;

  static BannerThemeData of(BuildContext context) {
    final inherited = context.dependOnInheritedWidgetOfExactType<BannerTheme>();
    return inherited?.data ?? BannerThemeData.fallback(context);
  }

  @override
  bool updateShouldNotify(covariant BannerTheme oldWidget) {
    return oldWidget.data != data;
  }
}
