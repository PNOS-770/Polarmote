import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../shared/constants/app_string.dart';
import '../../../../shared/design_system/design_system.dart';
import '../../models/terminal_adaptive_throttle.dart';
import '../../models/terminal_session.dart';
import '../../state/terminal_app_state.dart';
import '../common/terminal_formatters.dart';
import '../common/terminal_localization.dart';
import '../common/terminal_ui_palette.dart';

class TerminalStatusBar extends StatefulWidget {
  const TerminalStatusBar({
    super.key,
    required this.session,
    required this.appState,
  });

  final TerminalSession session;
  final TerminalAppState appState;

  @override
  State<TerminalStatusBar> createState() => _TerminalStatusBarState();
}

class _TerminalStatusBarState extends State<TerminalStatusBar> {
  DateTime? _lastMetricsAt;
  bool _lastBroadcast = false;
  Timer? _throttleUpdateTimer;

  @override
  void initState() {
    super.initState();
    widget.appState.addListener(_onChanged);
    // 定期检查限流级别变化（每秒）
    _throttleUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !widget.appState.restorationInProgress) {
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(TerminalStatusBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appState != widget.appState) {
      oldWidget.appState.removeListener(_onChanged);
      widget.appState.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.appState.removeListener(_onChanged);
    _throttleUpdateTimer?.cancel();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    final metricsAt = widget.session.metricsUpdatedAt;
    final bc = widget.appState.broadcastEnabled;
    if (metricsAt == _lastMetricsAt && bc == _lastBroadcast) return;
    _lastMetricsAt = metricsAt;
    _lastBroadcast = bc;
    setState(() {});
  }

  Color _barColor(double fraction) {
    if (fraction < 0.5) return AppColors.success;
    if (fraction < 0.8) return AppColors.warning;
    return AppColors.error;
  }

  Widget _miniBar(double fraction) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        width: 20,
        height: 8,
        child: Stack(
          children: [
            Container(color: TerminalUiPalette.statusBarBorder),
            FractionallySizedBox(
              widthFactor: fraction.clamp(0.0, 1.0),
              child: Container(color: _barColor(fraction)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = widget.appState;
    final session = widget.session;
    final cpuUsage = session.cpuUsage ?? 0;
    final memUsage = session.memUsage ?? 0;
    final memText = session.memUsedBytes != null && session.memTotalBytes != null
        ? '${formatBytes(session.memUsedBytes)}/${formatBytes(session.memTotalBytes)}'
        : '--/--';
    final rxText = formatRate(session.netRxRate);
    final txText = formatRate(session.netTxRate);
    
    // 获取限流状态
    final diagnostics = session.getAdaptiveThrottleDiagnostics();
    final levelName = diagnostics['currentLevel'] as String;
    final level = ThrottleLevel.values.byName(levelName);
    // TODO: 测试模式 - 始终显示限流状态，方便验证
    // 生产环境改为：final showThrottle = appState.performanceSettings.adaptiveThrottleEnabled && level != ThrottleLevel.normal;
    final showThrottle = appState.performanceSettings.adaptiveThrottleEnabled;

    return Container(
      height: 22,
      decoration: const BoxDecoration(
        color: TerminalUiPalette.statusBarBg,
        border: Border(
          top: BorderSide(color: TerminalUiPalette.statusBarBorder, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          if (appState.broadcastEnabled)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _badge(l(appState, AppStrings.values.broadcast), AppColors.error),
            ),
          _statCpu(appState, cpuUsage),
          const SizedBox(width: 8),
          _statMem(appState, memUsage, memText),
          const SizedBox(width: 8),
          _statNet(rxText, txText),
          if (showThrottle) ...[
            const SizedBox(width: 8),
            _statThrottle(appState, level, diagnostics),
          ],
        ],
      ),
    );
  }
  
  Widget _statThrottle(TerminalAppState appState, ThrottleLevel level, Map<String, dynamic> diagnostics) {
    final color = ThrottleLevelStyles.getColor(level);
    final icon = ThrottleLevelStyles.getIndicatorIcon(level);
    final flushMs = diagnostics['flushIntervalMs'];
    final bufferKB = diagnostics['bufferSizeKB'];
    
    final levelText = switch (level) {
      ThrottleLevel.normal => l(appState, AppStrings.values.throttleLevelNormal),
      ThrottleLevel.moderate => l(appState, AppStrings.values.throttleLevelModerate),
      ThrottleLevel.high => l(appState, AppStrings.values.throttleLevelHigh),
      ThrottleLevel.critical => l(appState, AppStrings.values.throttleLevelCritical),
    };
    
    return Tooltip(
      message: '$levelText\n${flushMs}ms • ${bufferKB}KB',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            levelText,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCpu(TerminalAppState appState, double fraction) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l(appState, AppStrings.values.cpu), style: _labelStyle),
        const SizedBox(width: 2),
        _miniBar(fraction),
        const SizedBox(width: 2),
        Text(
          formatPercent(fraction.isNaN ? null : fraction),
          style: _valueStyle,
        ),
      ],
    );
  }

  Widget _statMem(TerminalAppState appState, double fraction, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l(appState, AppStrings.values.mem), style: _labelStyle),
        const SizedBox(width: 2),
        _miniBar(fraction),
        const SizedBox(width: 2),
        Text(text, style: _valueStyle),
      ],
    );
  }

  Widget _statNet(String rx, String tx) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('\u2193$rx', style: _valueStyle),
        const SizedBox(width: 4),
        Text('\u2191$tx', style: _valueStyle),
      ],
    );
  }

  TextStyle get _labelStyle => const TextStyle(
    fontSize: 10,
    color: TerminalUiPalette.statusBarLabel,
    fontWeight: FontWeight.w500,
  );

  TextStyle get _valueStyle => const TextStyle(
    fontSize: 10,
    color: TerminalUiPalette.statusBarValue,
    fontWeight: FontWeight.w400,
    fontFamily: 'monospace',
  );
}

