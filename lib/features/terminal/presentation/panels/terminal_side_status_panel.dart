import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../shared/constants/app_string.dart';
import '../../../../shared/design_system/design_system.dart';
import '../../models/terminal_adaptive_throttle.dart';
import '../../models/terminal_session.dart';
import '../../models/terminal_tab.dart';
import '../../state/terminal_app_state.dart';
import '../common/terminal_formatters.dart';
import '../common/terminal_localization.dart';
import '../common/terminal_ui_palette.dart';
import 'terminal_sparkline.dart';

const _networkTiers = <double>[
  102400,
  512000,
  1048576,
  5242880,
  10485760,
  20971520,
  52428800,
  104857600,
  209715200,
  524288000,
  1073741824,
];

class TerminalSideStatusPanel extends StatefulWidget {
  const TerminalSideStatusPanel({
    super.key,
    required this.session,
    required this.appState,
  });

  final TerminalSession session;
  final TerminalAppState appState;

  @override
  State<TerminalSideStatusPanel> createState() =>
      _TerminalSideStatusPanelState();
}

class _TerminalSideStatusPanelState extends State<TerminalSideStatusPanel> {
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
    _throttleUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !widget.appState.restorationInProgress) {
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(TerminalSideStatusPanel oldWidget) {
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

  void _advanceRxNetTier() {
    final history = widget.session.netRxHistory;
    if (history.isEmpty) return;
    final maxVal = history.reduce((a, b) => a > b ? a : b);
    var target = _networkTiers.length - 1;
    for (var i = 0; i < _networkTiers.length; i++) {
      if (_networkTiers[i] >= maxVal) {
        target = i;
        break;
      }
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
      if (_networkTiers[i] >= maxVal) {
        target = i;
        break;
      }
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

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final appState = widget.appState;
    final cpuUsage = session.cpuUsage ?? 0;
    final memUsage = session.memUsage ?? 0;
    final rxText = formatRate(session.netRxRate);
    final txText = formatRate(session.netTxRate);

    final diagnostics = session.getAdaptiveThrottleDiagnostics();
    final levelName = diagnostics['currentLevel'] as String;
    final level = ThrottleLevel.values.byName(levelName);
    final showThrottle =
        appState.performanceSettings.adaptiveThrottleEnabled;

    _advanceRxNetTier();
    _advanceTxNetTier();
    final rxScale = _networkTiers[_rxNetTier];
    final txScale = _networkTiers[_txNetTier];

    final title = session.tab.title.isNotEmpty
        ? session.tab.title
        : session.profile.name;

    return Container(
      width: 150,
      decoration: const BoxDecoration(
        color: TerminalUiPalette.statusBarBg,
        border: Border(
          right: BorderSide(color: TerminalUiPalette.statusBarBorder, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Session title ──
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: TerminalUiPalette.statusBarValue,
            ),
          ),
          const SizedBox(height: 2),
          // ── Status badge ──
          _statusBadge(session.tab.status),
          _latencyRow(),
          if (appState.broadcastEnabled) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                l(appState, AppStrings.values.broadcast),
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          // ── CPU ──
          _chartSection(
            label: l(appState, AppStrings.values.cpu),
            value: formatPercent(cpuUsage.isNaN ? null : cpuUsage),
            chart: MonitorChart(
              history: session.cpuHistory,
              getColor: _barColor,
              height: 56,
            ),
          ),
          const SizedBox(height: 10),
          // ── MEM ──
          _chartSection(
            label: l(appState, AppStrings.values.mem),
            value: formatPercent(memUsage.isNaN ? null : memUsage),
            chart: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SizedBox(
                height: 8,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: Stack(
                    children: [
                      Container(color: TerminalUiPalette.statusBarBorderDim),
                      FractionallySizedBox(
                        widthFactor: memUsage.clamp(0.0, 1.0),
                        child: Container(color: _barColor(memUsage)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // ── DL ──
          _chartSection(
            label: l(appState, AppStrings.values.dl),
            value: rxText,
            chart: MonitorChart(
              history: session.netRxHistory.map((v) => (v / rxScale).clamp(0.0, 1.0)).toList(),
              getColor: (_) => const Color(0xFF4DA3FF),
              fixedColor: const Color(0xFF4DA3FF),
              height: 46,
            ),
          ),
          const SizedBox(height: 10),
          // ── UL ──
          _chartSection(
            label: l(appState, AppStrings.values.ul),
            value: txText,
            chart: MonitorChart(
              history: session.netTxHistory.map((v) => (v / txScale).clamp(0.0, 1.0)).toList(),
              getColor: (_) => const Color(0xFF33D6C5),
              fixedColor: const Color(0xFF33D6C5),
              height: 46,
            ),
          ),
          // ── Throttle ──
          if (showThrottle) _throttleRow(level, diagnostics),
          const SizedBox(height: 8),
          // ── Device info ──
          _deviceInfo(session),
        ],
      ),
    ),
  );
}

  Widget _statusBadge(TerminalStatus status) {
    final appState = widget.appState;
    final (Color color, String text) = switch (status) {
      TerminalStatus.connected => (
        const Color(0xFF22C55E),
        l(appState, AppStrings.values.connected),
      ),
      TerminalStatus.connecting => (
        const Color(0xFFF59E0B),
        l(appState, AppStrings.values.connecting),
      ),
      TerminalStatus.reconnecting => (
        const Color(0xFFFB923C),
        l(appState, AppStrings.values.reconnecting),
      ),
      TerminalStatus.disconnected => (
        const Color(0xFFEF4444),
        l(appState, AppStrings.values.disconnected),
      ),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _latencyRow() {
    final session = widget.session;
    final appState = widget.appState;
    final ms = session.terminalLatencyMs;
    if (ms == null) return const SizedBox.shrink();
    final color = ms < 100
        ? const Color(0xFF22C55E)
        : ms < 300
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Text(
            '${l(appState, AppStrings.values.latency)}  ',
            style: const TextStyle(
              fontSize: 9,
              color: TerminalUiPalette.statusBarLabel,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            '${ms}ms',
            style: TextStyle(
              fontSize: 9,
              color: color,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartSection({
    required String label,
    required String value,
    required Widget chart,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: _labelStyle),
            const Spacer(),
            Text(value, style: _valueStyle),
          ],
        ),
        const SizedBox(height: 4),
        chart,
      ],
    );
  }

  Widget _throttleRow(ThrottleLevel level, Map<String, dynamic> diagnostics) {
    final color = ThrottleLevelStyles.getColor(level);
    final icon = ThrottleLevelStyles.getIndicatorIcon(level);
    final flushMs = diagnostics['flushIntervalMs'];
    final bufferKB = diagnostics['bufferSizeKB'];

    final levelText = switch (level) {
      ThrottleLevel.normal =>
        l(widget.appState, AppStrings.values.throttleLevelNormal),
      ThrottleLevel.moderate =>
        l(widget.appState, AppStrings.values.throttleLevelModerate),
      ThrottleLevel.high =>
        l(widget.appState, AppStrings.values.throttleLevelHigh),
      ThrottleLevel.critical =>
        l(widget.appState, AppStrings.values.throttleLevelCritical),
    };

    final msText = l(widget.appState, AppStrings.values.millisecondsAbbreviation);
    final kbText = l(widget.appState, AppStrings.values.kilobytesAbbreviation);

    return Tooltip(
      message: '$levelText\n$flushMs$msText • $bufferKB$kbText',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
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

  Widget _deviceInfo(TerminalSession session) {
    final items = <(String, String?)>[
      (l(widget.appState, AppStrings.values.hostName), session.hostName),
      (l(widget.appState, AppStrings.values.deviceModel), session.deviceModel),
      (l(widget.appState, AppStrings.values.cpuCores), session.cpuCores),
      (l(widget.appState, AppStrings.values.totalMem), session.totalMem),
      (l(widget.appState, AppStrings.values.osInfo), session.osInfo),
      (l(widget.appState, AppStrings.values.kernelVersion), session.kernelVersion),
      (l(widget.appState, AppStrings.values.uptime), session.uptime),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 6),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: TerminalUiPalette.statusBarBorder, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (label, value) in items)
            if (value != null && value.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    Text(
                      '$label  ',
                      style: const TextStyle(
                        fontSize: 9,
                        color: TerminalUiPalette.statusBarLabel,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 9,
                          color: TerminalUiPalette.statusBarValue,
                          fontWeight: FontWeight.w400,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          if (items.every((e) => e.$2 == null || e.$2!.isEmpty))
            Text(
              session.profile.host,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9,
                color: TerminalUiPalette.statusBarLabel,
                fontWeight: FontWeight.w400,
                fontFamily: 'monospace',
              ),
            ),
        ],
      ),
    );
  }

  TextStyle get _labelStyle => const TextStyle(
        fontSize: 10,
        color: TerminalUiPalette.statusBarLabel,
        fontWeight: FontWeight.w500,
      );

  TextStyle get _valueStyle => const TextStyle(
        fontSize: 11,
        color: TerminalUiPalette.statusBarValue,
        fontWeight: FontWeight.w400,
        fontFamily: 'monospace',
      );
}
