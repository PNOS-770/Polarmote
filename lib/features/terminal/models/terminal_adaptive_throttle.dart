import '../../../shared/logging/Polarmote_log.dart';

/// 自适应限流器 - 根据系统压力动态调整终端输出刷新策略
class TerminalAdaptiveThrottle {
  TerminalAdaptiveThrottle({
    this.sessionId,
    this.initialFlushInterval = const Duration(milliseconds: 16),
    this.minFlushInterval = const Duration(milliseconds: 8),
    this.maxFlushInterval = const Duration(milliseconds: 100),
    this.initialBufferSize = 64 * 1024,
    this.minBufferSize = 16 * 1024,
    this.maxBufferSize = 256 * 1024,
    this.onLevelChanged,
    bool? enabled,
  }) : _enabled = enabled ?? true;

  // 会话ID（用于日志）
  final String? sessionId;

  // 刷新间隔范围（毫秒）
  final Duration initialFlushInterval;
  final Duration minFlushInterval;
  final Duration maxFlushInterval;

  // 缓冲区大小范围（字节）
  final int initialBufferSize;
  final int minBufferSize;
  final int maxBufferSize;

  // 级别变化回调
  final void Function(ThrottleLevel oldLevel, ThrottleLevel newLevel, String reason)? onLevelChanged;

  bool _enabled;
  bool _logChanges = true;

  /// 启用/禁用限流器
  // ignore: unnecessary_getters_setters
  bool get enabled => _enabled;
  // ignore: unnecessary_getters_setters
  set enabled(bool value) => _enabled = value;

  Duration _currentFlushInterval = const Duration(milliseconds: 16);
  int _currentBufferSize = 64 * 1024;
  ThrottleLevel _currentLevel = ThrottleLevel.normal;

  // ── 实时压力指标（使用指数移动平均 α=0.3） ──

  /// 终端处理耗时指数移动平均（ms），α=0.3
  double _smoothProcessingMs = 0;
  bool _hasProcessingSample = false;

  /// 缓冲压力指数移动平均（pendingBytes / maxBufferSize）
  double _smoothBufferPressure = 0;

  /// 上一个 5 秒窗口的丢包率和吞吐量，用于平滑降级
  int _droppedBytesInWindow = 0;
  int _totalBytesInWindow = 0;
  DateTime _windowStart = DateTime.now();
  static const Duration _monitorWindow = Duration(seconds: 5);

  /// 上次降级时间，防止频繁降级抖动
  DateTime? _lastDowngradeAt;
  static const Duration _downgradeCooldown = Duration(seconds: 2);

  /// flush 缓冲为空的连续次数（用于空闲降级）
  int _idleTickCount = 0;
  static const int _idleTickThreshold = 15;

  // 降级历史
  final List<_ThrottleEvent> _history = [];
  static const int _maxHistorySize = 20;

  Duration get currentFlushInterval => _currentFlushInterval;
  int get currentBufferSize => _currentBufferSize;
  ThrottleLevel get currentLevel => _currentLevel;

  // ── 实时压力反馈接口 ──

  /// 记录终端处理耗时（每次 _writeToTerminal 后调用）
  void recordProcessingTime(Duration elapsed) {
    if (!_enabled) return;
    final ms = elapsed.inMicroseconds / 1000;
    if (!_hasProcessingSample) {
      _smoothProcessingMs = ms;
      _hasProcessingSample = true;
    } else {
      _smoothProcessingMs += (ms - _smoothProcessingMs) * 0.3;
    }

    // 处理耗时超标 → 立即升级（不等待窗口）
    if (_smoothProcessingMs > 16 && _currentLevel == ThrottleLevel.normal) {
      _reactiveUpgrade(ThrottleLevel.moderate, 'Processing time ${_smoothProcessingMs.toStringAsFixed(1)}ms > 16ms');
    } else if (_smoothProcessingMs > 33) {
      _reactiveUpgrade(ThrottleLevel.high, 'Processing time ${_smoothProcessingMs.toStringAsFixed(1)}ms > 33ms');
    } else if (_smoothProcessingMs > 66) {
      _reactiveUpgrade(ThrottleLevel.critical, 'Processing time ${_smoothProcessingMs.toStringAsFixed(1)}ms > 66ms');
    }

    // 处理耗时上升 → 升级（已在上方处理），但不用耗时下降来做降级
    // 降级只由 recordIdleTick（缓冲为空）触发，避免连续输出时误降
  }

  /// 记录 flush 时缓冲为空（没有数据流入时由定时器周期性调用）
  void recordIdleTick() {
    if (!_enabled) return;
    if (_currentLevel == ThrottleLevel.normal) return;
    _idleTickCount++;
    if (_idleTickCount >= _idleTickThreshold) {
      _reactiveDowngrade('No data for $_idleTickThreshold flush ticks');
      _idleTickCount = 0;
    }
  }

  /// 记录缓冲压力（每次 _bufferOutput 后调用）
  void recordPendingBuffer(int pendingBytes) {
    if (!_enabled) return;
    final rawPressure = pendingBytes / maxBufferSize;
    if (rawPressure > _smoothBufferPressure) {
      // 快速上升：直接跟随
      _smoothBufferPressure = rawPressure;
    } else {
      // 慢速下降：平滑
      _smoothBufferPressure += (rawPressure - _smoothBufferPressure) * 0.3;
    }

    if (pendingBytes > 0) {
      _idleTickCount = 0;
    }

    if (_smoothBufferPressure > 2.0 && _currentLevel.index <= ThrottleLevel.moderate.index) {
      _reactiveUpgrade(ThrottleLevel.high, 'Buffer pressure ${_smoothBufferPressure.toStringAsFixed(1)}x > 2x');
    } else if (_smoothBufferPressure > 4.0) {
      _reactiveUpgrade(ThrottleLevel.critical, 'Buffer pressure ${_smoothBufferPressure.toStringAsFixed(1)}x > 4x');
    }
  }

  /// 立即升级（不降级）
  void _reactiveUpgrade(ThrottleLevel target, String reason) {
    if (target.index <= _currentLevel.index) return;
    final oldLevel = _currentLevel;
    _applyThrottleLevel(target);
    _recordEvent(_ThrottleEvent(
      timestamp: DateTime.now(),
      oldLevel: oldLevel,
      newLevel: target,
      dropRate: _droppedBytesInWindow / (_totalBytesInWindow > 0 ? _totalBytesInWindow : 1),
      throughputKBps: _totalBytesInWindow / 1024 / _monitorWindow.inSeconds,
      reason: reason,
    ));
    if (_logChanges) {
      final sessionPrefix = sessionId != null ? '[$sessionId] ' : '';
      PolarmoteLog.warn('terminal_throttle',
          '${sessionPrefix}Reactive upgrade: ${oldLevel.name} → ${target.name} | $reason | '
          'flush=${_currentFlushInterval.inMilliseconds}ms, buffer=${(_currentBufferSize / 1024).toStringAsFixed(0)}KB');
    }
    onLevelChanged?.call(oldLevel, target, reason);
  }

  /// 逐步降级（每次降一级，2 秒冷却防止抖动）
  void _reactiveDowngrade(String reason) {
    if (_lastDowngradeAt != null &&
        DateTime.now().difference(_lastDowngradeAt!) < _downgradeCooldown) {
      return;
    }
    if (_currentLevel == ThrottleLevel.normal) return;

    final oldLevel = _currentLevel;
    final target = ThrottleLevel.values[_currentLevel.index - 1];
    _applyThrottleLevel(target);
    _lastDowngradeAt = DateTime.now();

    // 降级到 moderate 时重置 5 秒窗口，防止残留的高吞吐统计再次触发升级
    if (target == ThrottleLevel.moderate) {
      _resetWindow();
    }
    _recordEvent(_ThrottleEvent(
      timestamp: DateTime.now(),
      oldLevel: oldLevel,
      newLevel: target,
      dropRate: _droppedBytesInWindow / (_totalBytesInWindow > 0 ? _totalBytesInWindow : 1),
      throughputKBps: _totalBytesInWindow / 1024 / _monitorWindow.inSeconds,
      reason: reason,
    ));

    if (_logChanges) {
      final sessionPrefix = sessionId != null ? '[$sessionId] ' : '';
      PolarmoteLog.info('terminal_throttle',
          '${sessionPrefix}Reactive downgrade: ${oldLevel.name} → ${target.name} | $reason | '
          'flush=${_currentFlushInterval.inMilliseconds}ms, buffer=${(_currentBufferSize / 1024).toStringAsFixed(0)}KB');
    }
    onLevelChanged?.call(oldLevel, target, reason);
  }

  /// 记录输出事件（原有接口，降级和恢复走这里）
  void recordOutput({
    required int bytesWritten,
    required int bytesDropped,
    required int bufferSize,
  }) {
    if (!_enabled) return;
    if (bytesWritten > 0) {
      _idleTickCount = 0; // 有数据写入，重置 idle 计数
    }
    _droppedBytesInWindow += bytesDropped;
    _totalBytesInWindow += bytesWritten + bytesDropped;
    final elapsed = DateTime.now().difference(_windowStart);
    if (elapsed >= _monitorWindow) {
      _evaluateAndAdjust();
      _resetWindow();
    }
  }

  /// 手动触发评估
  void evaluate() {
    if (!_enabled) return;
    _evaluateAndAdjust();
  }

  void _resetWindow() {
    _droppedBytesInWindow = 0;
    _totalBytesInWindow = 0;
    _windowStart = DateTime.now();
  }

  void _evaluateAndAdjust() {
    if (_totalBytesInWindow == 0 && _currentLevel == ThrottleLevel.normal) return;

    final dropRate = _totalBytesInWindow > 0
        ? _droppedBytesInWindow / _totalBytesInWindow
        : 0.0;
    final throughputKBps = _totalBytesInWindow / 1024 / _monitorWindow.inSeconds;

    final oldLevel = _currentLevel;
    ThrottleLevel newLevel = _currentLevel;

    if (dropRate > 0.1) {
      newLevel = ThrottleLevel.critical;
    } else if (dropRate > 0.05 || throughputKBps > 500) {
      newLevel = ThrottleLevel.high;
    } else if (dropRate > 0.01 || throughputKBps > 200) {
      newLevel = ThrottleLevel.moderate;
    } else if (dropRate < 0.001 && throughputKBps < 50) {
      newLevel = ThrottleLevel.normal;
    }

    if (newLevel != oldLevel) {
      final reason = _determineReason(dropRate, throughputKBps);
      _applyThrottleLevel(newLevel);
      _recordEvent(_ThrottleEvent(
        timestamp: DateTime.now(),
        oldLevel: oldLevel,
        newLevel: newLevel,
        dropRate: dropRate,
        throughputKBps: throughputKBps,
        reason: reason,
      ));

      final sessionPrefix = sessionId != null ? '[$sessionId] ' : '';
      final logLevel = newLevel.index > oldLevel.index ? 'warn' : 'info';
      final logMessage = '${sessionPrefix}Adaptive throttle: ${oldLevel.name} → ${newLevel.name} | $reason | '
          'flush=${_currentFlushInterval.inMilliseconds}ms, buffer=${(_currentBufferSize / 1024).toStringAsFixed(0)}KB';

      if (logLevel == 'warn') {
        PolarmoteLog.warn('terminal_throttle', logMessage);
      } else {
        PolarmoteLog.info('terminal_throttle', logMessage);
      }
      onLevelChanged?.call(oldLevel, newLevel, reason);
    }
  }

  void _applyThrottleLevel(ThrottleLevel level) {
    _currentLevel = level;

    switch (level) {
      case ThrottleLevel.normal:
        _currentFlushInterval = initialFlushInterval; // 16ms (60fps)
        _currentBufferSize = initialBufferSize; // 64KB
      case ThrottleLevel.moderate:
        _currentFlushInterval = const Duration(milliseconds: 33); // 30fps
        _currentBufferSize = (initialBufferSize * 1.5).toInt(); // 96KB
      case ThrottleLevel.high:
        _currentFlushInterval = const Duration(milliseconds: 50); // 20fps
        _currentBufferSize = maxBufferSize ~/ 2; // 128KB
      case ThrottleLevel.critical:
        _currentFlushInterval = maxFlushInterval; // 100ms (10fps)
        _currentBufferSize = maxBufferSize; // 256KB
    }

    _currentFlushInterval = Duration(
      milliseconds: _currentFlushInterval.inMilliseconds
          .clamp(minFlushInterval.inMilliseconds, maxFlushInterval.inMilliseconds),
    );
    _currentBufferSize = _currentBufferSize.clamp(minBufferSize, maxBufferSize);
  }

  String _determineReason(double dropRate, double throughputKBps) {
    if (dropRate > 0.1) return 'High drop rate: ${(dropRate * 100).toStringAsFixed(1)}%';
    if (throughputKBps > 500) return 'High throughput: ${throughputKBps.toStringAsFixed(0)} KB/s';
    if (dropRate > 0.05) return 'Moderate drop rate: ${(dropRate * 100).toStringAsFixed(1)}%';
    if (throughputKBps > 200) return 'Moderate throughput: ${throughputKBps.toStringAsFixed(0)} KB/s';
    return 'Recovered';
  }

  void _recordEvent(_ThrottleEvent event) {
    _history.add(event);
    if (_history.length > _maxHistorySize) {
      _history.removeAt(0);
    }
  }

  Map<String, dynamic> getDiagnostics() {
    return {
      'currentLevel': _currentLevel.name,
      'flushIntervalMs': _currentFlushInterval.inMilliseconds,
      'bufferSizeKB': (_currentBufferSize / 1024).toStringAsFixed(1),
      'smoothProcessingMs': double.parse(_smoothProcessingMs.toStringAsFixed(2)),
      'smoothBufferPressure': double.parse((_smoothBufferPressure * 100).toStringAsFixed(1)),
      'recentEvents': _history.map((e) => {
        'time': e.timestamp.toIso8601String(),
        'transition': '${e.oldLevel.name} → ${e.newLevel.name}',
        'reason': e.reason,
      }).toList(),
    };
  }

  void reset() {
    if (!_enabled) return;
    _currentFlushInterval = initialFlushInterval;
    _currentBufferSize = initialBufferSize;
    _currentLevel = ThrottleLevel.normal;
    _smoothProcessingMs = 0;
    _hasProcessingSample = false;
    _smoothBufferPressure = 0;
    _resetWindow();
    _history.clear();
  }
}

enum ThrottleLevel {
  normal,
  moderate,
  high,
  critical,
}

class _ThrottleEvent {
  _ThrottleEvent({
    required this.timestamp,
    required this.oldLevel,
    required this.newLevel,
    required this.dropRate,
    required this.throughputKBps,
    required this.reason,
  });

  final DateTime timestamp;
  final ThrottleLevel oldLevel;
  final ThrottleLevel newLevel;
  final double dropRate;
  final double throughputKBps;
  final String reason;
}

