import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../shared/design_system/design_system.dart';
import '../../../../shared/constants/app_string.dart';
import '../../state/terminal_app_state.dart';
import '../common/terminal_localization.dart';
import 'modal_panel_base.dart';

/// 脚本管理模态面板
class ScriptModalPanel extends StatelessWidget {
  const ScriptModalPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<TerminalAppState>(context);

    return ModalPanelBase(
      title: l(appState, AppStrings.values.scripts),
      width: 800,
      height: 600,
      actions: [
        IconButton(
          icon: const Icon(Icons.add),
          iconSize: 20,
          tooltip: 'New Script',
          onPressed: () {
            // TODO: Open new script dialog
          },
        ),
      ],
      child: _buildScriptList(context, appState),
    );
  }

  Widget _buildScriptList(BuildContext context, TerminalAppState appState) {
    if (appState.scripts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.code,
              size: 64,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No scripts available',
              style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: 'Create Script',
              onPressed: () {
                // TODO: Open new script dialog
              },
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: appState.scripts.length,
      itemBuilder: (context, index) {
        final script = appState.scripts[index];
        final subtitle = script.commands.isNotEmpty
            ? script.commands.first
            : 'No commands';

        return Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: ListTile(
            leading: Icon(
              Icons.code,
              color: AppColors.primary,
            ),
            title: Text(
              script.name,
              style: AppTextStyles.bodySmall,
            ),
            subtitle: Text(
              subtitle,
              style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.play_arrow, size: 18),
                  tooltip: 'Run Script',
                  onPressed: () {
                    // TODO: Run script
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  tooltip: 'Edit Script',
                  onPressed: () {
                    // TODO: Edit script
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 显示脚本面板
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (context) => const ScriptModalPanel(),
    );
  }
}

