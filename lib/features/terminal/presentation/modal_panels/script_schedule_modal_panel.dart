import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../shared/design_system/design_system.dart';
import '../../../../shared/constants/app_string.dart';
import '../../../../shared/utils/cron_expression.dart';
import '../../models/script_schedule_entry.dart';
import '../../models/script_entry.dart';
import '../../models/host_entry.dart';
import '../../state/terminal_app_state.dart';
import '../common/terminal_localization.dart';
import 'modal_panel_base.dart';

class ScriptScheduleModalPanel extends StatelessWidget {
  const ScriptScheduleModalPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<TerminalAppState>(context);

    return ModalPanelBase(
      title: l(appState, AppStrings.values.scriptSchedule),
      width: 800,
      height: 600,
      actions: [
        IconButton(
          icon: const Icon(Icons.add),
          iconSize: 20,
          tooltip: l(appState, AppStrings.values.add),
          onPressed: () => _showScheduleEditor(context, appState),
        ),
      ],
      child: _buildScheduleList(context, appState),
    );
  }

  Widget _buildScheduleList(BuildContext context, TerminalAppState appState) {
    if (appState.scriptSchedules.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.schedule, size: 64, color: AppColors.textTertiary),
            const SizedBox(height: AppSpacing.md),
            Text(
              l(appState, AppStrings.values.noData),
              style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: l(appState, AppStrings.values.add),
              onPressed: () => _showScheduleEditor(context, appState),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: appState.scriptSchedules.length,
      itemBuilder: (context, index) {
        final schedule = appState.scriptSchedules[index];
        final script = _findScript(appState, schedule.scriptId);
        final scriptName = script?.name ?? schedule.scriptId;
        final nextTrigger = appState.scriptScheduleNextTriggerTime(schedule);

        return Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            scriptName,
                            style: AppTextStyles.bodySmall,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: schedule.enabled
                                  ? AppColors.success.withValues(alpha: 0.15)
                                  : AppColors.grey300,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              schedule.enabled
                                  ? l(appState, AppStrings.values.enabled)
                                  : 'Disabled',
                              style: AppTextStyles.caption.copyWith(
                                color: schedule.enabled
                                    ? AppColors.success
                                    : AppColors.textSecondary,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        schedule.cronExpression,
                        style: AppTextStyles.code.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${schedule.hostIds.length} host(s) · ${schedule.localShellTypes.length} shell(s)',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                      if (nextTrigger != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            l(appState, AppStrings.values.scriptScheduleNextTriggerVar, params: {
                              'time': _formatDateTime(nextTrigger.toLocal()),
                            }),
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.primary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    schedule.enabled ? Icons.pause : Icons.play_arrow,
                    size: 18,
                  ),
                  tooltip: schedule.enabled ? 'Disable' : 'Enable',
                  onPressed: () {
                    final updated = schedule.copyWith(
                      enabled: !schedule.enabled,
                      updatedAt: DateTime.now(),
                    );
                    appState.upsertScriptScheduleEntry(updated);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  tooltip: l(appState, AppStrings.values.edit),
                  onPressed: () => _showScheduleEditor(
                    context,
                    appState,
                    existing: schedule,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 18),
                  tooltip: 'Delete',
                  onPressed: () => _confirmDelete(context, appState, schedule),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  ScriptEntry? _findScript(TerminalAppState appState, String scriptId) {
    for (final script in appState.scripts) {
      if (script.id == scriptId) return script;
    }
    return null;
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} '
        '${_pad(dt.hour)}:${_pad(dt.minute)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  Future<void> _showScheduleEditor(
    BuildContext context,
    TerminalAppState appState, {
    ScriptScheduleEntry? existing,
  }) async {
    final isEditing = existing != null;
    final id = existing?.id ?? 'script-schedule-${DateTime.now().microsecondsSinceEpoch}';
    var scriptId = existing?.scriptId ?? '';
    var cronExpression = existing?.cronExpression ?? '* * * * *';
    var enabled = existing?.enabled ?? true;
    var hostIds = existing?.hostIds ?? <String>[];
    var localShellTypes = existing?.localShellTypes ?? <LocalShellType>[];
    var failurePolicy = existing?.failurePolicy ?? ScriptFailurePolicy.continueOnFailure;
    var retryPerHost = existing?.retryPerHost ?? 1;
    var silentExecution = existing?.silentExecution ?? true;
    var timezoneOffsetMinutes = existing?.timezoneOffsetMinutes ??
        DateTime.now().timeZoneOffset.inMinutes;
    var missedRunPolicy =
        existing?.missedRunPolicy ?? ScriptScheduleMissedRunPolicy.skip;
    var cronValid = true;
    var scriptError = '';

    final now = DateTime.now();

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final scripts = appState.scripts.toList(growable: false);

            return AlertDialog(
              backgroundColor: AppColors.cardBackground,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.radiusDialog,
              ),
              titlePadding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                0,
              ),
              contentPadding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                0,
              ),
              actionsPadding: const EdgeInsets.all(AppSpacing.lg),
              title: Text(
                isEditing
                    ? l(appState, AppStrings.values.scriptScheduleVar, params: {
                        'name': _findScript(appState, scriptId)?.name ?? scriptId,
                      })
                    : l(appState, AppStrings.values.scriptSchedule),
                style: AppTextStyles.h4,
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (scripts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: Text(
                            l(appState, AppStrings.values.scriptScheduleRequiresLastRun),
                            style: AppTextStyles.body
                                .copyWith(color: AppColors.warning),
                          ),
                        ),
                      AppDropdownButtonFormField<String>(
                        value: scriptId.isEmpty ? null : scriptId,
                        label: l(appState, AppStrings.values.scriptLabel),
                        items: [
                          for (final script in scripts)
                            DropdownMenuItem(
                              value: script.id,
                              child: Text(script.name),
                            ),
                        ],
                        onChanged: scripts.isEmpty
                            ? null
                            : (value) {
                                setState(() {
                                  scriptId = value ?? '';
                                  scriptError = '';
                                });
                              },
                      ),
                      if (scriptError.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            scriptError,
                            style: AppTextStyles.error,
                          ),
                        ),
                      const SizedBox(height: AppSpacing.md),
                      AppTextField(
                        label: l(appState, AppStrings.values.cronExpression),
                        hint: l(appState, AppStrings.values.scriptScheduleHint),
                        controller: TextEditingController(text: cronExpression),
                        onChanged: (value) {
                          setState(() {
                            cronExpression = value;
                            cronValid = CronExpression.isValid(value.trim());
                          });
                        },
                        errorText: cronValid
                            ? null
                            : l(appState, AppStrings.values.invalidCronExpression),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        l(appState, AppStrings.values.scriptTriggerHostScope),
                        style: AppTextStyles.label,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      _buildHostSelector(
                        appState,
                        hostIds,
                        (selected) {
                          setState(() => hostIds = selected);
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Local Shell Types',
                        style: AppTextStyles.label,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      _buildLocalShellSelector(
                        appState,
                        localShellTypes,
                        (selected) {
                          setState(() => localShellTypes = selected);
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppDropdownButtonFormField<ScriptFailurePolicy>(
                        value: failurePolicy,
                        label: 'Failure Policy',
                        items: [
                          for (final policy in ScriptFailurePolicy.values)
                            DropdownMenuItem(
                              value: policy,
                              child: Text(_scriptFailurePolicyLabel(appState, policy)),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => failurePolicy = value);
                          }
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              label: 'Retry Per Host',
                              controller: TextEditingController(
                                text: retryPerHost.toString(),
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (value) {
                                final parsed = int.tryParse(value);
                                if (parsed != null) {
                                  setState(
                                    () => retryPerHost = parsed.clamp(1, 6),
                                  );
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: AppTextField(
                              label: l(appState, AppStrings.values.scriptScheduleTimezone),
                              controller: TextEditingController(
                                text: timezoneOffsetMinutes.toString(),
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (value) {
                                final parsed = int.tryParse(value);
                                if (parsed != null) {
                                  setState(
                                    () => timezoneOffsetMinutes = parsed.clamp(
                                      -12 * 60,
                                      14 * 60,
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppDropdownButtonFormField<ScriptScheduleMissedRunPolicy>(
                        value: missedRunPolicy,
                        label: l(appState, AppStrings.values.scriptScheduleMissedRunPolicy),
                        items: [
                          DropdownMenuItem(
                            value: ScriptScheduleMissedRunPolicy.skip,
                            child: Text(
                              l(appState, AppStrings.values.scriptScheduleMissedRunSkip),
                            ),
                          ),
                          DropdownMenuItem(
                            value: ScriptScheduleMissedRunPolicy.catchUpOnce,
                            child: Text(
                              l(appState, AppStrings.values.scriptScheduleMissedRunCatchUpOnce),
                            ),
                          ),
                          DropdownMenuItem(
                            value: ScriptScheduleMissedRunPolicy.catchUpAll,
                            child: Text(
                              l(appState, AppStrings.values.scriptScheduleMissedRunCatchUpAll),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => missedRunPolicy = value);
                          }
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          const Icon(Icons.volume_off, size: 16),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            l(appState, AppStrings.values.scriptTriggerSilentExecution),
                            style: AppTextStyles.body,
                          ),
                          const Spacer(),
                          Switch(
                            value: silentExecution,
                            onChanged: (value) {
                              setState(() => silentExecution = value);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          const Icon(Icons.toggle_on, size: 16),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            l(appState, AppStrings.values.enabled),
                            style: AppTextStyles.body,
                          ),
                          const Spacer(),
                          Switch(
                            value: enabled,
                            onChanged: (value) {
                              setState(() => enabled = value);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                AppTextButton(
                  onPressed: () => Navigator.pop(context),
                  label: l(appState, AppStrings.values.cancel),
                  size: ButtonSize.small,
                ),
                PrimaryButton(
                  label: isEditing
                      ? l(appState, AppStrings.values.save)
                      : l(appState, AppStrings.values.create),
                  onPressed: () {
                    if (scriptId.isEmpty) {
                      setState(() {
                        scriptError = 'Please select a script';
                      });
                      return;
                    }
                    if (!CronExpression.isValid(cronExpression.trim())) {
                      setState(() {
                        cronValid = false;
                      });
                      return;
                    }
                    final entry = ScriptScheduleEntry(
                      id: id,
                      scriptId: scriptId,
                      cronExpression: cronExpression.trim(),
                      enabled: enabled,
                      hostIds: hostIds,
                      localShellTypes: localShellTypes,
                      failurePolicy: failurePolicy,
                      retryPerHost: retryPerHost,
                      silentExecution: silentExecution,
                      timezoneOffsetMinutes: timezoneOffsetMinutes,
                      missedRunPolicy: missedRunPolicy,
                      createdAt: existing?.createdAt ?? now,
                      updatedAt: now,
                      lastTriggeredAt: existing?.lastTriggeredAt,
                      lastEvaluatedAt: existing?.lastEvaluatedAt,
                    );
                    appState.upsertScriptScheduleEntry(entry);
                    Navigator.pop(context);
                  },
                  size: ButtonSize.small,
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildHostSelector(
    TerminalAppState appState,
    List<String> selectedHostIds,
    ValueChanged<List<String>> onChanged,
  ) {
    final hosts = appState.hosts.toList(growable: false);
    if (hosts.isEmpty) {
      return Text(
        'No hosts available',
        style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 120),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: AppRadius.radiusInput,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final host in hosts)
              CheckboxListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                title: Text(
                  host.name,
                  style: AppTextStyles.bodySmall,
                ),
                subtitle: Text(
                  '${host.host}:${host.port}',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
                value: selectedHostIds.contains(host.id),
                onChanged: (checked) {
                  final updated = List<String>.from(selectedHostIds);
                  if (checked == true) {
                    updated.add(host.id);
                  } else {
                    updated.remove(host.id);
                  }
                  onChanged(updated);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalShellSelector(
    TerminalAppState appState,
    List<LocalShellType> selectedTypes,
    ValueChanged<List<LocalShellType>> onChanged,
  ) {
    const options = LocalShellType.values;

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final type in options)
          FilterChip(
            label: Text(
              _localShellLabel(appState, type),
              style: AppTextStyles.caption,
            ),
            selected: selectedTypes.contains(type),
            onSelected: (checked) {
              final updated = List<LocalShellType>.from(selectedTypes);
              if (checked) {
                updated.add(type);
              } else {
                updated.remove(type);
              }
              onChanged(updated);
            },
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }

  String _localShellLabel(TerminalAppState appState, LocalShellType type) {
    return switch (type) {
      LocalShellType.systemDefault =>
        l(appState, AppStrings.values.localShellSystemDefault),
      LocalShellType.powershell =>
        l(appState, AppStrings.values.localShellPowerShell),
      LocalShellType.powershellAdmin =>
        l(appState, AppStrings.values.localShellPowerShellAdmin),
      LocalShellType.commandPrompt =>
        l(appState, AppStrings.values.localShellCommandPrompt),
      LocalShellType.wsl => l(appState, AppStrings.values.localShellWsl),
      LocalShellType.bash => l(appState, AppStrings.values.localShellBash),
    };
  }

  String _scriptFailurePolicyLabel(
    TerminalAppState appState,
    ScriptFailurePolicy policy,
  ) {
    return switch (policy) {
      ScriptFailurePolicy.continueOnFailure =>
        l(appState, AppStrings.values.scriptFailurePolicyContinue),
      ScriptFailurePolicy.stopOnFailure =>
        l(appState, AppStrings.values.scriptFailurePolicyStop),
      ScriptFailurePolicy.retryHost =>
        l(appState, AppStrings.values.scriptFailurePolicyRetryHost),
    };
  }

  Future<void> _confirmDelete(
    BuildContext context,
    TerminalAppState appState,
    ScriptScheduleEntry schedule,
  ) async {
    final scriptName =
        _findScript(appState, schedule.scriptId)?.name ?? schedule.scriptId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.radiusDialog),
        title: Text('Delete Schedule', style: AppTextStyles.h4),
        content: Text(
          'Delete schedule "${schedule.cronExpression}" for "$scriptName"?',
          style: AppTextStyles.body,
        ),
        actions: [
          AppTextButton(
            onPressed: () => Navigator.pop(context, false),
            label: l(appState, AppStrings.values.cancel),
            size: ButtonSize.small,
          ),
          PrimaryButton(
            label: l(appState, AppStrings.values.confirm),
            onPressed: () => Navigator.pop(context, true),
            size: ButtonSize.small,
          ),
        ],
      ),
    );
    if (confirmed == true) {
      appState.removeScriptScheduleEntry(schedule.id);
    }
  }

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (context) => const ScriptScheduleModalPanel(),
    );
  }
}

