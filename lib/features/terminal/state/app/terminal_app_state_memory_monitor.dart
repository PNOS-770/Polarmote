part of '../terminal_app_state.dart';

/// 智能内存管理扩展
extension TerminalAppStateMemoryMonitor on TerminalAppState {
  /// 启动内存监控
  void startMemoryMonitoring() {
    if (!smartMemoryManagement) return;
    
    _memoryMonitorTimer?.cancel();
    _memoryMonitorTimer = Timer.periodic(
      const Duration(seconds: 30), // 每 30 秒检查一次
      (_) => _checkMemoryUsage(),
    );
  }
  
  /// 停止内存监控
  void stopMemoryMonitoring() {
    _memoryMonitorTimer?.cancel();
    _memoryMonitorTimer = null;
  }
  
  /// 检查内存使用情况
  void _checkMemoryUsage() {
    if (!smartMemoryManagement) return;
    
    // 获取当前活跃终端数量
    final activeTerminals = sessions.where((s) => 
      s.tab.status == TerminalStatus.connected ||
      s.tab.status == TerminalStatus.connecting
    ).length;
    
    if (activeTerminals == 0) return;
    
    // 估算当前内存使用
    final estimatedMB = estimatedMemoryPerTerminal * activeTerminals;
    
    // 如果内存占用过高（超过 100MB），自动降低 buffer 大小
    if (estimatedMB > 100 && memoryMode != MemoryMode.low) {
      _reduceMemoryUsage();
    }
    // 如果内存占用恢复正常且之前降级过，恢复设置
    else if (estimatedMB < 50 && _originalMemoryMode != null) {
      _restoreMemoryMode();
    }
  }
  
  /// 降低内存使用
  void _reduceMemoryUsage() {
    final now = DateTime.now();
    
    // 避免频繁提示（5 分钟内只提示一次）
    if (_lastMemoryWarning != null && 
        now.difference(_lastMemoryWarning!) < const Duration(minutes: 5)) {
      return;
    }
    
    _lastMemoryWarning = now;
    
    // 保存原始设置
    if (_originalMemoryMode == null) {
      _originalMemoryMode = memoryMode;
    }
    
    // 根据当前模式降级
    final newMode = switch (memoryMode) {
      MemoryMode.high => MemoryMode.medium,
      MemoryMode.medium => MemoryMode.low,
      MemoryMode.custom => customTerminalBufferSize > 5000 
        ? MemoryMode.medium 
        : MemoryMode.low,
      MemoryMode.low => MemoryMode.low, // 已经最低
    };
    
    if (newMode != memoryMode) {
      memoryMode = newMode;
      notifyState();
      
      addStructuredLog(
        category: TerminalLogCategory.startup,
        message: 'Smart memory management: Reduced buffer size to conserve memory',
        level: TerminalLogLevel.warn,
      );
      
      PolarmoteLog.info(
        'memory_monitor',
        'Automatically reduced memory mode to $newMode (estimated usage: ${(estimatedMemoryPerTerminal * sessions.length).toStringAsFixed(1)} MB)',
      );
    }
  }
  
  /// 恢复内存模式
  void _restoreMemoryMode() {
    if (_originalMemoryMode == null) return;
    
    memoryMode = _originalMemoryMode!;
    _originalMemoryMode = null;
    notifyState();
    
    addStructuredLog(
      category: TerminalLogCategory.startup,
      message: 'Smart memory management: Restored original buffer size',
      level: TerminalLogLevel.info,
    );
    
    PolarmoteLog.info(
      'memory_monitor',
      'Restored memory mode to $memoryMode',
    );
  }
  
  /// 清理内存监控
  void disposeMemoryMonitor() {
    stopMemoryMonitoring();
    _originalMemoryMode = null;
    _lastMemoryWarning = null;
  }
}

