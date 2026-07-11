import 'dart:async';

import 'package:flutter/foundation.dart';

import '../model/banner_data.dart';
import 'banner_queue.dart';

class BannerManager {
  BannerManager._();

  static final BannerManager instance = BannerManager._();

  final BannerQueue _queue = BannerQueue(maxVisible: 5);
  final ValueNotifier<List<BannerData>> banners =
      ValueNotifier<List<BannerData>>(const <BannerData>[]);
  final Map<String, Timer> _autoDismissTimers = <String, Timer>{};
  final Map<String, Duration> _remainingDurations = <String, Duration>{};
  final Map<String, DateTime> _timerStartedAt = <String, DateTime>{};

  static const Duration _defaultSuccessOrInfoDuration = Duration(seconds: 3);
  static const Duration _defaultWarningDuration = Duration(seconds: 4);
  static const Duration _defaultErrorDuration = Duration(seconds: 5);

  static void show(BannerData data) {
    instance._show(data);
  }

  static void update(
    String id,
    double progress, {
    BannerType? type,
    String? title,
    String? message,
  }) {
    instance._update(
      id,
      progress: progress,
      type: type,
      title: title,
      message: message,
    );
  }

  static void dismiss(String id) {
    instance._dismiss(id);
  }

  static void pauseTimer(String id) {
    instance._pauseTimer(id);
  }

  static void resumeTimer(String id) {
    instance._resumeTimer(id);
  }

  void _show(BannerData data) {
    _queue.push(data);
    _syncBanners();
    _scheduleAutoDismissIfNeeded(data.id);
  }

  void _update(
    String id, {
    required double progress,
    BannerType? type,
    String? title,
    String? message,
  }) {
    final normalized = progress.clamp(0, 1);
    final found = _queue.update(id, (current) {
      final nextType = type ?? current.type;
      final shouldAutoDismiss = nextType != BannerType.progress;
      return current.copyWith(
        type: nextType,
        title: title,
        message: message,
        progress: normalized.toDouble(),
        clearDuration: shouldAutoDismiss,
        duration: shouldAutoDismiss ? _defaultDurationFor(nextType) : null,
      );
    });
    if (!found) return;
    _syncBanners();
    _scheduleAutoDismissIfNeeded(id);
  }

  void _dismiss(String id) {
    _cancelTimer(id);
    final changed = _queue.remove(id);
    if (changed) {
      _syncBanners();
      _rescheduleVisibleTimers();
    }
  }

  void _syncBanners() {
    banners.value = _queue.active;
  }

  void _rescheduleVisibleTimers() {
    for (final banner in _queue.active) {
      _scheduleAutoDismissIfNeeded(banner.id);
    }
  }

  void _scheduleAutoDismissIfNeeded(String id) {
    final current = _queue.active.where((item) => item.id == id).firstOrNull;
    if (current == null) {
      _cancelTimer(id);
      return;
    }
    if (current.type == BannerType.progress) {
      _cancelTimer(id);
      return;
    }
    if (_autoDismissTimers.containsKey(id)) {
      return;
    }
    final duration =
        _remainingDurations[id] ??
        current.duration ??
        _defaultDurationFor(current.type);
    _remainingDurations[id] = duration;
    _timerStartedAt[id] = DateTime.now();
    _autoDismissTimers[id] = Timer(duration, () => _dismiss(id));
  }

  void _pauseTimer(String id) {
    final timer = _autoDismissTimers[id];
    if (timer == null) return;
    final startedAt = _timerStartedAt[id];
    final total = _remainingDurations[id];
    if (startedAt == null || total == null) {
      _cancelTimer(id);
      return;
    }
    final elapsed = DateTime.now().difference(startedAt);
    final left = total - elapsed;
    _remainingDurations[id] = left.isNegative ? Duration.zero : left;
    timer.cancel();
    _autoDismissTimers.remove(id);
    _timerStartedAt.remove(id);
  }

  void _resumeTimer(String id) {
    if (_autoDismissTimers.containsKey(id)) return;
    final remaining = _remainingDurations[id];
    if (remaining == null) return;
    if (remaining == Duration.zero) {
      _dismiss(id);
      return;
    }
    _timerStartedAt[id] = DateTime.now();
    _autoDismissTimers[id] = Timer(remaining, () => _dismiss(id));
  }

  void _cancelTimer(String id) {
    _autoDismissTimers.remove(id)?.cancel();
    _remainingDurations.remove(id);
    _timerStartedAt.remove(id);
  }

  Duration _defaultDurationFor(BannerType type) {
    return switch (type) {
      BannerType.success || BannerType.info => _defaultSuccessOrInfoDuration,
      BannerType.warning => _defaultWarningDuration,
      BannerType.error => _defaultErrorDuration,
      BannerType.progress => Duration.zero,
    };
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
