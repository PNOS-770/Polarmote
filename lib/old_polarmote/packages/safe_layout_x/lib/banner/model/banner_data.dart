import 'package:flutter/foundation.dart';

enum BannerType { success, error, warning, info, progress }

@immutable
class BannerData {
  const BannerData({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    this.progress,
    this.duration,
    this.onTap,
  });

  final String id;
  final BannerType type;
  final String title;
  final String message;
  final double? progress;
  final Duration? duration;
  final VoidCallback? onTap;

  BannerData copyWith({
    BannerType? type,
    String? title,
    String? message,
    double? progress,
    bool clearProgress = false,
    Duration? duration,
    bool clearDuration = false,
    VoidCallback? onTap,
  }) {
    return BannerData(
      id: id,
      type: type ?? this.type,
      title: title ?? this.title,
      message: message ?? this.message,
      progress: clearProgress ? null : (progress ?? this.progress),
      duration: clearDuration ? null : (duration ?? this.duration),
      onTap: onTap ?? this.onTap,
    );
  }
}
