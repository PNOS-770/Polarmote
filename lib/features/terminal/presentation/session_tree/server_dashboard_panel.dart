import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:safe_layout_x/safe_layout_x.dart';

import '../../../../shared/constants/app_string.dart';
import '../../../../shared/design_system/design_system.dart';
import '../../models/host_entry.dart';
import '../../models/terminal_session.dart';
import '../../models/terminal_tab.dart';
import '../../state/terminal_app_state.dart';
import '../../../../services/server_metrics.dart';
import '../../../../services/server_monitor_service.dart';
import '../common/compact_more_menu_button.dart';
import '../common/terminal_formatters.dart';
import '../common/terminal_localization.dart';
import '../common/terminal_ui_palette.dart';
import '../dialogs/terminal_dialogs.dart';

enum _HostAction { edit, delete, pinToggle }

class ServerDashboardPanel extends StatefulWidget {
  const ServerDashboardPanel({super.key});

  @override
  State<ServerDashboardPanel> createState() => _ServerDashboardPanelState();
}

class _ServerDashboardPanelState extends State<ServerDashboardPanel> {
  final _monitor = ServerMonitorService.instance;
  late final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final appState = context.read<TerminalAppState>();
    _searchController.text = appState.sessionQuery;
    _searchController.addListener(() {
      context.read<TerminalAppState>().setSessionQuery(_searchController.text);
    });
    _monitor.start(appState);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<HostEntry> _sortHosts(TerminalAppState appState, List<HostEntry> hosts) {
    final sortedList = hosts.toList();
    sortedList.sort((a, b) {
      final aStatus = appState.hostSessionStatus(a.id);
      final bStatus = appState.hostSessionStatus(b.id);
      final aOnline = aStatus == TerminalStatus.connected ? 1 : 0;
      final bOnline = bStatus == TerminalStatus.connected ? 1 : 0;
      if (aOnline != bOnline) return bOnline - aOnline;
      return 0;
    });
    return sortedList;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<TerminalAppState>();
    if (_searchController.text != appState.sessionQuery) {
      _searchController.value = _searchController.value.copyWith(
        text: appState.sessionQuery,
        selection: TextSelection.collapsed(offset: appState.sessionQuery.length),
        composing: TextRange.empty,
      );
    }

    final visibleHosts = appState.visibleHosts();
    final sortedHosts = _sortHosts(appState, visibleHosts);

    return Column(
      children: [
        _buildToolbar(appState),
        Expanded(
          child: sortedHosts.isEmpty
              ? Center(child: Text(l(appState, AppStrings.values.noMatchingSessions), style: const TextStyle(color: TerminalUiPalette.textSecondary)))
              : ListView.builder(
                  padding: const EdgeInsets.all(6),
                  itemCount: sortedHosts.length,
                  itemBuilder: (context, index) {
                    final host = sortedHosts[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _ServerCard(
                        key: ValueKey('host-${host.id}'),
                        appState: appState,
                        host: host,
                        status: appState.hostSessionStatus(host.id),
                        metrics: _monitor.history(host.id),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildToolbar(TerminalAppState appState) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: const BoxDecoration(
        color: TerminalUiPalette.cardBackground,
        border: Border(bottom: BorderSide(color: TerminalUiPalette.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: AppSearchBar(
              controller: _searchController,
              hint: l(appState, AppStrings.values.searchServers),
              onChanged: (value) => appState.setSessionQuery(value),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SecondaryButton(
            onPressed: () => showHostDialog(context, appState),
            icon: Icons.add,
            label: l(appState, AppStrings.values.newSession),
            size: ButtonSize.small,
          ),
          const SizedBox(width: AppSpacing.xs),
          SecondaryButton(
            onPressed: () => showQuickConnectDialog(context, appState),
            icon: Icons.flash_on,
            label: l(appState, AppStrings.values.quickConnect),
            size: ButtonSize.small,
          ),
        ],
      ),
    );
  }
}

class _ServerCard extends StatefulWidget {
  const _ServerCard({
    super.key,
    required this.appState,
    required this.host,
    required this.status,
    required this.metrics,
  });

  final TerminalAppState appState;
  final HostEntry host;
  final TerminalStatus? status;
  final List<ServerMetricsSnapshot> metrics;

  @override
  State<_ServerCard> createState() => _ServerCardState();
}

class _ServerCardState extends State<_ServerCard> {
  bool _expanded = false;

  TerminalAppState get appState => widget.appState;
  HostEntry get host => widget.host;
  TerminalStatus? get status => widget.status;
  List<ServerMetricsSnapshot> get metrics => widget.metrics;
  TerminalSession? get _session {
    try {
      return appState.sessions.firstWhere((s) => s.profile.id == host.id);
    } catch (_) {
      return null;
    }
  }

  bool get _isOnline => status == TerminalStatus.connected;

  String get _typeLabel => switch (host.connectionType) {
    ConnectionType.ssh => l(appState, AppStrings.values.connectionSsh),
    ConnectionType.serial => l(appState, AppStrings.values.connectionSerial),
    ConnectionType.telnet => l(appState, AppStrings.values.connectionTelnet),
    ConnectionType.local => l(appState, AppStrings.values.connectionLocal),
  };

  @override
  Widget build(BuildContext context) {
    final latest = metrics.isNotEmpty ? metrics.last : null;
    final isPinned = appState.isHostPinned(host.id);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        child: BaseCard(
          padding: EdgeInsets.zero,
          border: true,
          shadow: true,
          radius: AppRadius.lg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, isPinned),
              if (_expanded && _isOnline && latest != null) _buildMetrics(latest, _session),
              if (_expanded && !_isOnline) _buildOffline(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isPinned) {
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      onSecondaryTapDown: (d) => _showMenu(context, d.globalPosition),
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          gradient: _isOnline
              ? LinearGradient(
                  colors: [
                    AppColors.success.withValues(alpha: 0.05),
                    AppColors.cardBackground,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          border: const Border(bottom: BorderSide(color: AppColors.border, width: 1)),
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
        child: Row(
          children: [
            Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: TerminalUiPalette.textSecondary,
            ),
            const SizedBox(width: 6),
            if (_isOnline)
              const SquareBreathIndicator(
                color: AppColors.success,
                lightColor: AppColors.successSoft,
                squareSize: 4,
                spacing: 2,
                breathIntensity: 0.8,
              )
            else
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: TerminalUiPalette.textSecondary),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    host.name,
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: _isOnline ? AppColors.textPrimary : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _isOnline ? AppColors.success.withValues(alpha: 0.1) : AppColors.grey200,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _isOnline ? AppColors.success.withValues(alpha: 0.3) : AppColors.grey300,
                  width: 1,
                ),
              ),
              child: Text(
                _typeLabel,
                style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: _isOnline ? AppColors.success : AppColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (isPinned) const Icon(Icons.star, size: 14, color: TerminalUiPalette.warning),
            const SizedBox(width: 4),
            CompactMoreMenuButton(
              tooltip: l(appState, AppStrings.values.more),
              padding: 2,
              iconSize: 16,
              onTapDown: (d) => _showMenu(context, d.globalPosition),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetrics(ServerMetricsSnapshot latest, TerminalSession? session) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cpuSection(latest),
          const Divider(height: 24),
          _memorySection(latest),
          const Divider(height: 24),
          _diskSection(latest),
          if (session != null && (session.netTxHistory.length > 1 || session.netRxHistory.length > 1)) ...[
            const Divider(height: 24),
            _netSection(session),
          ],
          const Divider(height: 24),
          _cpuDistribution(latest),
        ],
      ),
    );
  }

  Widget _cpuSection(ServerMetricsSnapshot latest) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(l(appState, AppStrings.values.cpuUsage), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('${latest.cpuUsage.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFEF4444))),
          ],
        ),
        const SizedBox(height: 8),
        if (metrics.length >= 2) _lineChart(metrics, (m) => m.cpuUsage, const Color(0xFFEF4444)),
      ],
    );
  }

  Widget _memorySection(ServerMetricsSnapshot latest) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(l(appState, AppStrings.values.memoryUsage), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('${latest.memoryUsage.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF10B981))),
          ],
        ),
        const SizedBox(height: 8),
        if (metrics.length >= 2) _lineChart(metrics, (m) => m.memoryUsage, const Color(0xFF10B981)),
      ],
    );
  }

  Widget _diskSection(ServerMetricsSnapshot latest) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(l(appState, AppStrings.values.diskUsage), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('${latest.diskUsage.round()}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFF59E0B))),
          ],
        ),
        const SizedBox(height: 8),
        _diskBar('/', latest.diskUsage, const Color(0xFFF59E0B)),
      ],
    );
  }

  Widget _netSection(TerminalSession session) {
    final txRate = session.netTxRate ?? 0;
    final rxRate = session.netRxRate ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.arrow_upward, size: 12, color: Color(0xFF3B82F6)),
            const SizedBox(width: 4),
            Text(l(appState, AppStrings.values.upload), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(formatRate(txRate), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF3B82F6))),
          ],
        ),
        const SizedBox(height: 4),
        if (session.netTxHistory.length >= 2)
          _miniLineChart(session.netTxHistory, const Color(0xFF3B82F6)),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.arrow_downward, size: 12, color: Color(0xFF22C55E)),
            const SizedBox(width: 4),
            Text(l(appState, AppStrings.values.download), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(formatRate(rxRate), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF22C55E))),
          ],
        ),
        const SizedBox(height: 4),
        if (session.netRxHistory.length >= 2)
          _miniLineChart(session.netRxHistory, const Color(0xFF22C55E)),
      ],
    );
  }

  Widget _miniLineChart(List<double> data, Color color) {
    final maxVal = data.reduce((a, b) => a > b ? a : b).clamp(1, double.infinity);
    return SizedBox(
      height: 40,
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minY: 0,
          maxY: maxVal * 1.2,
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF1F2937),
              getTooltipItems: (touchedSpots) => touchedSpots.map((s) =>
                LineTooltipItem(formatRate(s.y), const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white)),
              ).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(data.length, (i) => FlSpot(i.toDouble(), data[i])),
              isCurved: true,
              color: color,
              barWidth: 1.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.1)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cpuDistribution(ServerMetricsSnapshot latest) {
    final user = latest.cpuUsage * 0.6;
    final system = latest.cpuUsage * 0.3;
    final idle = 100 - latest.cpuUsage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l(appState, AppStrings.values.cpuLoadDistribution), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Row(
          children: [
            SizedBox(
              width: 120,
              height: 120,
              child: PieChart(
                PieChartData(
                  sections: [
                    PieChartSectionData(
                      value: user,
                      color: const Color(0xFF3B82F6),
                      title: '${user.round()}%',
                      radius: 45,
                      titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    PieChartSectionData(
                      value: system,
                      color: const Color(0xFFEF4444),
                      title: '${system.round()}%',
                      radius: 45,
                      titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    PieChartSectionData(
                      value: idle,
                      color: const Color(0xFFE5E7EB),
                      title: '${idle.round()}%',
                      radius: 45,
                      titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: TerminalUiPalette.textSecondary),
                    ),
                  ],
                  sectionsSpace: 2,
                  centerSpaceRadius: 25,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _legend(l(appState, AppStrings.values.cpuUser), const Color(0xFF3B82F6)),
                  const SizedBox(height: 6),
                  _legend(l(appState, AppStrings.values.cpuSystem), const Color(0xFFEF4444)),
                  const SizedBox(height: 6),
                  _legend(l(appState, AppStrings.values.cpuIdle), const Color(0xFFE5E7EB)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _legend(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }

  Widget _lineChart(List<ServerMetricsSnapshot> data, double Function(ServerMetricsSnapshot) getValue, Color color) {
    return SizedBox(
      height: 120,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            horizontalInterval: 25,
            verticalInterval: data.length > 10 ? (data.length / 6).ceilToDouble() : 5,
            getDrawingHorizontalLine: (v) => FlLine(color: TerminalUiPalette.border, strokeWidth: 1),
            getDrawingVerticalLine: (v) => FlLine(color: TerminalUiPalette.border.withValues(alpha: 0.3), strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: 25,
                getTitlesWidget: (v, _) => Text('${v.toInt()}%', style: const TextStyle(fontSize: 9, color: TerminalUiPalette.textSecondary)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 20,
                interval: data.length > 10 ? (data.length / 4).ceilToDouble() : 5,
                getTitlesWidget: (v, _) {
                  final index = v.toInt();
                  if (index < 0 || index >= data.length) return const SizedBox.shrink();
                  final timestamp = data[index].timestamp;
                  return Text('${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 8, color: TerminalUiPalette.textSecondary));
                },
              ),
            ),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minY: 0,
          maxY: 100,
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF1F2937),
              getTooltipItems: (touchedSpots) => touchedSpots.map((s) =>
                LineTooltipItem('${s.y.toStringAsFixed(1)}%', const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white)),
              ).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(data.length, (i) => FlSpot(i.toDouble(), getValue(data[i]))),
              isCurved: true,
              color: color,
              barWidth: 2,
              dotData: FlDotData(show: data.length <= 20),
              belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.1)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _diskBar(String label, double percent, Color color) {
    return Row(
      children: [
        SizedBox(width: 40, child: Text(label, style: const TextStyle(fontSize: 10))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 12,
              backgroundColor: TerminalUiPalette.border,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('${percent.round()}%', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }

  Widget _buildOffline() {
    final lastSeen = host.lastConnected;
    final lastSeenStr = lastSeen == null
        ? l(appState, AppStrings.values.never)
        : (() {
            final diff = DateTime.now().difference(lastSeen);
            if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
            if (diff.inHours < 24) return '${diff.inHours}h ago';
            return '${diff.inDays}d ago';
          })();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, size: 14, color: TerminalUiPalette.textSecondary),
              const SizedBox(width: 6),
              Text('${l(appState, AppStrings.values.offline)} · ${l(appState, AppStrings.values.lastSeen)}: $lastSeenStr', style: const TextStyle(fontSize: 11, color: TerminalUiPalette.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showMenu(BuildContext context, Offset position) async {
    final action = await showCompactMenu<_HostAction>(
      context: context,
      position: position,
      items: [
        compactMenuItem(value: _HostAction.edit, label: l(appState, AppStrings.values.edit)),
        compactMenuItem(value: _HostAction.pinToggle, label: l(appState, appState.isHostPinned(host.id) ? AppStrings.values.unpin : AppStrings.values.pin)),
        compactMenuItem(value: _HostAction.delete, label: l(appState, AppStrings.values.delete)),
      ],
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _HostAction.edit: showHostDialog(context, appState, host: host);
      case _HostAction.delete: confirmDeleteHost(context, appState, host);
      case _HostAction.pinToggle: appState.toggleHostPinned(host.id);
    }
  }
}

