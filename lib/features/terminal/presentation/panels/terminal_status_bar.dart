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

const _networkTiers = <double>[
  102400,       // 100 KB/s
  512000,       // 500 KB/s
  1048576,      // 1 MB/s
  5242880,      // 5 MB/s
  10485760,     // 10 MB/s
  20971520,     // 20 MB/s
  52428800,     // 50 MB/s
  104857600,    // 100 MB/s
  209715200,    // 200 MB/s
  524288000,    // 500 MB/s
  1073741824,   // 1 GB/s
];

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

  int _rxNetTier = 0;
  int _txNetTier = 0;
  DateTime? _rxDowngradeAt;
  DateTime? _txDowngradeAt;

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
    final showThrottle = appState.performanceSettings.adaptiveThrottleEnabled && level != ThrottleLevel.normal;

    return Container(
      height: 22,
      decoration: const BoxDecoration(
        color: TerminalUiPalette.statusBarBg,
        border: Border(
          top: BorderSide(color: TerminalUiPalette.statusBarBorder, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 500;
        if (wide) {
          return Row(
            children: [
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    session.tab.title.isNotEmpty ? session.tab.title : session.profile.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: TerminalUiPalette.statusBarLabel, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              Container(width: 1, height: 12, color: TerminalUiPalette.statusBarBorder),
              const SizedBox(width: 4),
              if (appState.broadcastEnabled)
                _badge(l(appState, AppStrings.values.broadcast), AppColors.error),
              Expanded(flex: 1, child: _statCpuWide(appState, cpuUsage)),
              Expanded(flex: 1, child: _statMemWide(appState, memUsage, memText)),
              Expanded(flex: 3, child: _statNetWide(appState, rxText, txText)),
              if (showThrottle)
                _statThrottle(appState, level, diagnostics),
            ],
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  session.tab.title.isNotEmpty ? session.tab.title : session.profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: TerminalUiPalette.statusBarLabel, fontWeight: FontWeight.w500),
                ),
              ),
              Container(width: 1, height: 12, color: TerminalUiPalette.statusBarBorder),
              const SizedBox(width: 4),
              if (appState.broadcastEnabled)
                _badge(l(appState, AppStrings.values.broadcast), AppColors.error),
              _statCpuNarrow(appState, cpuUsage),
              _statMemNarrow(appState, memUsage, memText),
              _statNetNarrow(appState, rxText, txText),
              if (showThrottle) _statThrottle(appState, level, diagnostics),
            ],
          ),
        );
      }),
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
    
    final msText = l(appState, AppStrings.values.millisecondsAbbreviation);
    final kbText = l(appState, AppStrings.values.kilobytesAbbreviation);
    return Tooltip(
      message: '$levelText\n$flushMs$msText • $bufferKB$kbText',
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

  Widget _statCpuNarrow(TerminalAppState appState, double fraction) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l(appState, AppStrings.values.cpu), style: _labelStyle),
          const SizedBox(width: 2),
          SizedBox(width: 48, child: _miniBar(fraction)),
          const SizedBox(width: 2),
          Text(
            formatPercent(fraction.isNaN ? null : fraction),
            style: _valueStyle,
          ),
        ],
      ),
    );
  }

  Widget _statCpuWide(TerminalAppState appState, double fraction) {
    return Row(
      children: [
        Text(l(appState, AppStrings.values.cpu), style: _labelStyle),
        const SizedBox(width: 2),
        Expanded(child: _miniBar(fraction)),
        const SizedBox(width: 2),
        Text(
          formatPercent(fraction.isNaN ? null : fraction),
          style: _valueStyle,
        ),
      ],
    );
  }

  Widget _statMemNarrow(TerminalAppState appState, double fraction, String text) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l(appState, AppStrings.values.mem), style: _labelStyle),
          const SizedBox(width: 2),
          SizedBox(width: 48, child: _miniBar(fraction)),
          const SizedBox(width: 2),
          Text(text, style: _valueStyle),
        ],
      ),
    );
  }

  Widget _statMemWide(TerminalAppState appState, double fraction, String text) {
    return Row(
      children: [
        Text(l(appState, AppStrings.values.mem), style: _labelStyle),
        const SizedBox(width: 2),
        Expanded(child: _miniBar(fraction)),
        const SizedBox(width: 2),
        Text(text, style: _valueStyle),
      ],
    );
  }

  void _advanceRxNetTier() {
    final history = widget.session.netRxHistory;
    if (history.isEmpty) return;
    final maxVal = history.reduce((a, b) => a > b ? a : b);
    var target = _networkTiers.length - 1;
    for (var i = 0; i < _networkTiers.length; i++) {
      if (_networkTiers[i] >= maxVal) { target = i; break; }
    }
    if (target > _rxNetTier) {
      _rxNetTier = target;
      _rxDowngradeAt = null;
    } else if (target < _rxNetTier) {
      final threshold = _networkTiers[_rxNetTier] * 0.3;
      if (maxVal < threshold) {
        final now = DateTime.now();
        _rxDowngradeAt ??= now;
        if (now.difference(_rxDowngradeAt!).inSeconds >= 60) {
          _rxNetTier = target;
          _rxDowngradeAt = null;
        }
      } else {
        _rxDowngradeAt = null;
      }
    }
  }

  void _advanceTxNetTier() {
    final history = widget.session.netTxHistory;
    if (history.isEmpty) return;
    final maxVal = history.reduce((a, b) => a > b ? a : b);
    var target = _networkTiers.length - 1;
    for (var i = 0; i < _networkTiers.length; i++) {
      if (_networkTiers[i] >= maxVal) { target = i; break; }
    }
    if (target > _txNetTier) {
      _txNetTier = target;
      _txDowngradeAt = null;
    } else if (target < _txNetTier) {
      final threshold = _networkTiers[_txNetTier] * 0.3;
      if (maxVal < threshold) {
        final now = DateTime.now();
        _txDowngradeAt ??= now;
        if (now.difference(_txDowngradeAt!).inSeconds >= 60) {
          _txNetTier = target;
          _txDowngradeAt = null;
        }
      } else {
        _txDowngradeAt = null;
      }
    }
  }

  Widget _miniBar(double fraction) {
    return SizedBox(
      height: 8,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Stack(
          children: [
            Container(color: TerminalUiPalette.statusBarBorderDim),
            FractionallySizedBox(
              widthFactor: fraction.clamp(0.0, 1.0),
              child: Container(color: _barColor(fraction)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statNetNarrow(TerminalAppState appState, String rx, String tx) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l(appState, AppStrings.values.dl), style: _labelStyle),
        const SizedBox(width: 2),
        Text(rx, style: _valueStyle),
        const SizedBox(width: 6),
        Text(l(appState, AppStrings.values.ul), style: _labelStyle),
        const SizedBox(width: 2),
        Text(tx, style: _valueStyle),
      ],
    );
  }

  Widget _statNetWide(TerminalAppState appState, String rx, String tx) {
    final rxHistory = widget.session.netRxHistory;
    final txHistory = widget.session.netTxHistory;
    _advanceRxNetTier();
    _advanceTxNetTier();
    final rxScale = _networkTiers[_rxNetTier];
    final txScale = _networkTiers[_txNetTier];
    final rxFraction = rxHistory.isEmpty || rxScale <= 0
        ? 0.0
        : (rxHistory.last / rxScale).clamp(0.0, 1.0);
    final txFraction = txHistory.isEmpty || txScale <= 0
        ? 0.0
        : (txHistory.last / txScale).clamp(0.0, 1.0);
    return Row(
      children: [
        Text(l(appState, AppStrings.values.dl), style: _labelStyle),
        const SizedBox(width: 2),
        Expanded(child: _miniBar(rxFraction)),
        const SizedBox(width: 2),
        Text(rx, style: _valueStyle),
        const SizedBox(width: 4),
        Text(l(appState, AppStrings.values.ul), style: _labelStyle),
        const SizedBox(width: 2),
        Expanded(child: _miniBar(txFraction)),
        const SizedBox(width: 2),
        Text(tx, style: _valueStyle),
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



