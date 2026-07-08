import 'package:flutter/material.dart';
import '../../../../shared/design_system/design_system.dart';
import '../../../../shared/constants/app_string.dart';
import '../../state/terminal_app_state.dart';
import '../common/terminal_localization.dart';
import '../common/menu_models.dart';
import '../common/command_executor.dart';

void showMobileMoreMenu(BuildContext context, TerminalAppState appState) {
  final shortcut = <String, String?>{};
  String? s(String id) {
    final idx = appState.shortcutBindings.indexWhere((b) => b.id == id);
    if (idx < 0) return null;
    final keys = appState.shortcutBindings[idx].effectiveKeys;
    return keys.isEmpty ? null : keys;
  }
  for (final id in [
    'newSession', 'quickConnect', 'closeSession', 'closeAllSessions',
    'newScript', 'scriptList', 'scriptMonitor',
    'sftpBrowser', 'transferManager',
    'portForwarding', 'lanScan', 'openSettings',
  ]) {
    shortcut[id] = s(id);
  }

  final categories = [
    MenuCategory('sessions', Icons.terminal,
        l(appState, AppStrings.values.commandBarSessions), [
      MenuItem('new_session', Icons.add,
          l(appState, AppStrings.values.commandBarNewSession)),
      MenuItem('quick_connect', Icons.flash_on,
          l(appState, AppStrings.values.commandBarQuickConnect)),
      MenuItem('close_workspace', Icons.close,
          l(appState, AppStrings.values.commandBarCloseCurrentWorkspace)),
      MenuItem('close_all', Icons.highlight_off,
          l(appState, AppStrings.values.commandBarCloseAllSessions)),
    ]),
    MenuCategory('scripts', Icons.code,
        l(appState, AppStrings.values.commandBarScripts), [
      MenuItem('new_script', Icons.add,
          l(appState, AppStrings.values.commandBarNewScript)),
      MenuItem('script_list', Icons.list,
          l(appState, AppStrings.values.commandBarScriptList)),
      MenuItem('script_monitor', Icons.monitor_heart,
          l(appState, AppStrings.values.commandBarScriptMonitor)),
    ]),
    MenuCategory('files', Icons.folder,
        l(appState, AppStrings.values.commandBarSftpBrowser), [
      MenuItem('sftp_browser', Icons.folder_open,
          l(appState, AppStrings.values.commandBarSftpBrowser)),
      MenuItem('transfer_manager', Icons.compare_arrows,
          l(appState, AppStrings.values.commandBarTransferManager)),
    ]),
    MenuCategory('tools', Icons.build,
        l(appState, AppStrings.values.commandBarTools), [
      MenuItem('port_forwarding', Icons.route,
          l(appState, AppStrings.values.commandBarPortForward)),
      MenuItem('lan_scan', Icons.wifi_find,
          l(appState, AppStrings.values.lanScan)),
    ]),
    MenuCategory('settings', Icons.settings,
        l(appState, AppStrings.values.commandBarSettings), [
      MenuItem('open_settings', Icons.settings,
          l(appState, AppStrings.values.commandBarSettings)),
    ]),
  ];

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final maxHeight = MediaQuery.of(ctx).size.height * 0.7;
      return Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(16),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.grey300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Text(
                    l(appState, AppStrings.values.commandBarMore),
                    style: AppTextStyles.h5,
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 16),
                shrinkWrap: true,
                children: [
                  for (final cat in categories) ...[
                    _CategoryHeader(cat: cat),
                    for (final item in cat.items)
                      _MenuItemRow(
                        item: item,
                        shortcut: shortcut[item.id],
                        onTap: () {
                          Navigator.of(ctx).pop();
                          executeTerminalCommand(context, appState, item.id);
                        },
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _CategoryHeader extends StatelessWidget {
  final MenuCategory cat;
  const _CategoryHeader({required this.cat});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Icon(cat.icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Text(
            cat.label,
            style: AppTextStyles.label,
          ),
        ],
      ),
    );
  }
}

class _MenuItemRow extends StatelessWidget {
  final MenuItem item;
  final String? shortcut;
  final VoidCallback onTap;

  const _MenuItemRow({
    required this.item,
    required this.shortcut,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.borderLight, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Icon(item.icon, size: 18, color: AppColors.textPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.label,
                  style: AppTextStyles.body,
                ),
              ),
              if (shortcut != null)
                Text(
                  shortcut!,
                  style: AppTextStyles.code.copyWith(fontSize: 11),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

