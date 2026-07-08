import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../shared/design_system/design_system.dart';
import '../../../../shared/constants/app_string.dart';
import '../../models/host_entry.dart';
import '../../state/terminal_app_state.dart';
import '../common/terminal_localization.dart';
import 'modal_panel_base.dart';
import '../../../../shared/logging/Polarmote_log.dart';

class LanScanResult {
  final String ip;
  final String? mac;
  String? hostname;
  bool connectable;

  LanScanResult({
    required this.ip,
    this.mac,
    this.hostname,
    this.connectable = false,
  });
}

class LanScanPanel extends StatefulWidget {
  const LanScanPanel({super.key});

  @override
  State<LanScanPanel> createState() => _LanScanPanelState();

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const LanScanPanel(),
    );
  }
}

class _LanScanPanelState extends State<LanScanPanel> {
  bool _scanning = false;
  List<LanScanResult> _results = [];
  final Set<String> _addedIps = {};
  Set<String> _localIps = {};

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _startScan(TerminalAppState appState) async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _results = [];
      _localIps = {};
    });

    try {
      _localIps = await _getLocalIps();

      final subnet = await _getLocalSubnet();
      if (subnet == null || !mounted) {
        setState(() => _scanning = false);
        return;
      }

      final results = <LanScanResult>[];
      final base = subnet.substring(0, subnet.lastIndexOf('.') + 1);

      for (var i = 1; i <= 254 && _scanning && mounted; i++) {
        final ip = '$base$i';
        if (_localIps.contains(ip)) continue;

        final isAlive = await _pingHost(ip);
        if (!_scanning || !mounted) break;

        if (isAlive) {
          String? hostname;
          try {
            final addr = await InternetAddress(ip).reverse();
            hostname = addr.host;
            if (hostname == ip) hostname = null;
          } catch (e) { PolarmoteLog.error('lan_scan_modal_panel', '$e'); }
          results.add(LanScanResult(ip: ip, hostname: hostname));
        }

        if (mounted) {
          setState(() => _results = List.from(results));
        }
      }

      if (_scanning && mounted) {
        await _checkConnectability(appState, results);
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<Set<String>> _getLocalIps() async {
    final ips = <String>{};
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 &&
              !addr.address.startsWith('127.')) {
            ips.add(addr.address);
          }
        }
      }
    } catch (e) { PolarmoteLog.error('lan_scan_modal_panel', '$e'); }
    return ips;
  }

  Future<String?> _getLocalSubnet() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 &&
              !addr.address.startsWith('127.')) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              return '${parts[0]}.${parts[1]}.${parts[2]}.';
            }
          }
        }
      }
    } catch (e) { PolarmoteLog.error('lan_scan_modal_panel', '$e'); }
    return null;
  }

  Future<bool> _pingHost(String ip) async {
    try {
      final result = await Process.run('ping', [
        '-n', '1',
        '-w', '200',
        ip,
      ], runInShell: true);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> _checkConnectability(
    TerminalAppState appState,
    List<LanScanResult> results,
  ) async {
    for (final result in results) {
      if (!mounted) break;
      try {
        final socket = await Socket.connect(
          result.ip,
          22,
          timeout: const Duration(seconds: 1),
        );
        socket.destroy();
        if (mounted) {
          setState(() => result.connectable = true);
        }
      } catch (e) { PolarmoteLog.error('lan_scan_modal_panel', '$e'); }
    }
  }

  void _addToSessionTree(TerminalAppState appState, LanScanResult result) {
    final entry = HostEntry(
      id: 'lan-${result.ip.replaceAll('.', '-')}',
      name: result.hostname ?? result.ip,
      host: result.ip,
      port: 22,
      username: 'root',
      group: 'LAN Scan',
      authType: AuthType.password,
    );
    appState.addHost(entry);
    setState(() => _addedIps.add(result.ip));
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<TerminalAppState>(context);
    return ModalPanelBase(
      title: l(appState, AppStrings.values.lanScanTitle),
      width: 700,
      height: 500,
      actions: [
        IconButton(
          icon: _scanning
              ? const Icon(Icons.stop)
              : const Icon(Icons.wifi_find),
          iconSize: 20,
          tooltip: l(appState, _scanning
              ? AppStrings.values.lanScanStop
              : AppStrings.values.lanScanStart),
          onPressed: _scanning
              ? () => setState(() => _scanning = false)
              : () => unawaited(_startScan(appState)),
        ),
      ],
      child: _buildContent(appState),
    );
  }

  Widget _buildContent(TerminalAppState appState) {
    if (_scanning && _results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PulseIndicator(),
            const SizedBox(height: AppSpacing.md),
            Text(
              l(appState, AppStrings.values.lanScanning),
              style: AppTextStyles.body,
            ),
          ],
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Text(
          l(appState, AppStrings.values.lanScanNoResults),
          style: AppTextStyles.secondary,
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm,
          ),
          child: Row(
            children: [
              Text(
                l(appState, AppStrings.values.lanScanResultCount,
                    params: {'count': '${_results.length}'}),
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              if (_scanning) ...[
                const SizedBox(width: AppSpacing.sm),
                const SizedBox(
                  width: 12, height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            itemCount: _results.length,
            itemBuilder: (context, index) {
              final result = _results[index];
              return _buildResultCard(appState, result);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildResultCard(TerminalAppState appState, LanScanResult result) {
    final added = _addedIps.contains(result.ip);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: result.connectable
                    ? AppColors.success
                    : AppColors.textTertiary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.hostname ?? result.ip,
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        '${l(appState, AppStrings.values.lanScanIp)}: ${result.ip}',
                        style: AppTextStyles.captionSmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (result.mac != null) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          '${l(appState, AppStrings.values.lanScanMac)}: ${result.mac}',
                          style: AppTextStyles.captionSmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Text(
              result.connectable
                  ? l(appState, AppStrings.values.lanScanConnectable)
                  : l(appState, AppStrings.values.lanScanNotConnectable),
              style: AppTextStyles.captionSmall.copyWith(
                color: result.connectable
                    ? AppColors.success
                    : AppColors.textTertiary,
              ),
            ),
            if (result.connectable)
              IconButton(
                iconSize: 16,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(
                  minWidth: 28, minHeight: 28,
                ),
                icon: Icon(
                  added ? Icons.check : Icons.add_circle_outline,
                  color: added
                      ? AppColors.success
                      : AppColors.textSecondary,
                ),
                tooltip: l(appState, AppStrings.values.lanScanAddToTree),
                onPressed: added
                    ? null
                    : () => _addToSessionTree(appState, result),
              ),
          ],
        ),
      ),
    );
  }
}



