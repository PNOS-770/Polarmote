import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../shared/constants/app_string.dart';
import '../../../../shared/design_system/design_system.dart';
import '../../models/terminal_session.dart';
import '../../models/transfer_task.dart';
import '../../state/terminal_app_state.dart';
import '../../state/terminal_app_state_models.dart';
import '../common/terminal_localization.dart';
import '../common/terminal_ui_palette.dart';

class TransferPanel extends StatelessWidget {
  const TransferPanel({required this.appState, this.isCompact = false});

  final TerminalAppState appState;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return Selector<TerminalAppState, int>(
      selector: (context, state) {
        var hash = state.sessions.length;
        for (final session in state.sessions) {
          hash = 31 * hash + session.id.hashCode;
          hash = 31 * hash + session.transferVersion;
        }
        return hash;
      },
      builder: (context, version, child) {
        final sessions = appState.sessions;
        if (sessions.isEmpty) {
          return Center(child: Text(l(appState, AppStrings.values.noSessions)));
        }
        return ListView.builder(
          padding: EdgeInsets.symmetric(
            vertical: 8,
            horizontal: isCompact ? 12 : 16,
          ),
          itemCount: sessions.length,
          itemBuilder: (context, index) {
            return _TransferSessionSection(
              appState: appState,
              session: sessions[index],
              isCompact: isCompact,
            );
          },
        );
      },
    );
  }
}

class _TransferSessionSection extends StatelessWidget {
  const _TransferSessionSection({
    required this.appState,
    required this.session,
    required this.isCompact,
  });

  final TerminalAppState appState;
  final TerminalSession session;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final summary = appState.transferSummaryForSession(session);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactLayout = isCompact || constraints.maxWidth < 420;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: BaseCard(
            padding: EdgeInsets.all(compactLayout ? 10 : 12),
            border: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                compactLayout
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.tab.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          _RuntimeStatusLine(
                            appState: appState,
                            summary: summary,
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: Text(
                              session.tab.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                if (!compactLayout) ...[
                  const SizedBox(height: 4),
                  _RuntimeStatusLine(appState: appState, summary: summary),
                ],
                if (summary.showPreparing) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          summary.preparingLabel ??
                              l(
                                appState,
                                AppStrings.values.calculatingTransfers,
                              ),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ],
                if (summary.uploadQueues.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _QueueGroup(
                    appState: appState,
                    session: session,
                    direction: TransferDirection.upload,
                    queues: summary.uploadQueues,
                    compactLayout: compactLayout,
                  ),
                ],
                if (summary.downloadQueues.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _QueueGroup(
                    appState: appState,
                    session: session,
                    direction: TransferDirection.download,
                    queues: summary.downloadQueues,
                    compactLayout: compactLayout,
                  ),
                ],
                if (summary.showEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    l(appState, AppStrings.values.noActiveTransfers),
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RuntimeStatusLine extends StatelessWidget {
  const _RuntimeStatusLine({required this.appState, required this.summary});

  final TerminalAppState appState;
  final SessionTransferSummary summary;

  @override
  Widget build(BuildContext context) {
    return Text(
      l(
        appState,
        AppStrings.values.transferRuntimeStatusVarVarVarVarVar,
        params: {
          'upload': '${summary.runningUploadJobs}',
          'download': '${summary.runningDownloadJobs}',
          'total': '${summary.runningTotalJobs}',
          'busy': '${summary.nativeBusySessions}',
          'sessions': '${summary.nativeTotalSessions}',
        },
      ),
      style: const TextStyle(
        fontSize: 10,
        color: TerminalUiPalette.textSecondary,
      ),
    );
  }
}

class _QueueGroup extends StatelessWidget {
  const _QueueGroup({
    required this.appState,
    required this.session,
    required this.direction,
    required this.queues,
    required this.compactLayout,
  });

  final TerminalAppState appState;
  final TerminalSession session;
  final TransferDirection direction;
  final List<TransferQueueSummary> queues;
  final bool compactLayout;

  @override
  Widget build(BuildContext context) {
    final title = l(
      appState,
      direction == TransferDirection.upload
          ? AppStrings.values.uploads
          : AppStrings.values.downloads,
    );
    final paused = appState.isTransferDirectionPaused(session, direction);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            AppTextButton(
              onPressed: () => appState.setTransferDirectionPaused(
                session,
                direction,
                !paused,
              ),
              label: paused
                  ? l(appState, AppStrings.values.resume)
                  : l(appState, AppStrings.values.pause),
              size: ButtonSize.small,
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < queues.length; i++) ...[
          _QueueRow(
            appState: appState,
            session: session,
            queue: queues[i],
            compactLayout: compactLayout,
          ),
          if (i != queues.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.appState,
    required this.session,
    required this.queue,
    required this.compactLayout,
  });

  final TerminalAppState appState;
  final TerminalSession session;
  final TransferQueueSummary queue;
  final bool compactLayout;

  @override
  Widget build(BuildContext context) {
    final isDownload = queue.direction == TransferDirection.download;
    final queueName = queue.name.trim().isEmpty ? queue.id : queue.name;
    final queuePaused = queue.paused;
    final completed = queue.total > 0 && queue.done >= queue.total;
    final statusText = queue.preparing
        ? (queue.preparingLabel ??
              l(appState, AppStrings.values.calculatingTransfers))
        : queuePaused
        ? l(appState, AppStrings.values.paused)
        : completed
        ? l(appState, AppStrings.values.done)
        : l(appState, AppStrings.values.transferring);
    final progressPercent = l(
      appState,
      AppStrings.values.percentVar,
      params: {
        'value': (queue.progress.clamp(0.0, 1.0) * 100).toStringAsFixed(1),
      },
    );
    final etaText = queue.etaSeconds == null
        ? null
        : l(
            appState,
            AppStrings.values.transferEtaVar,
            params: {'eta': _formatEta(appState, queue.etaSeconds!)},
          );
    final progressLine = queue.preparing
        ? l(
            appState,
            AppStrings.values.transferQueueStatusVarVar,
            params: {
              'done': '${queue.done}',
              'total': '${queue.total}',
              'status': statusText,
            },
          )
        : etaText == null
        ? l(
            appState,
            AppStrings.values.transferQueueStatusWithPercentVarVarVarVar,
            params: {
              'done': '${queue.done}',
              'total': '${queue.total}',
              'status': statusText,
              'percent': progressPercent,
            },
          )
        : l(
            appState,
            AppStrings.values.transferQueueStatusWithPercentEtaVarVarVarVarVar,
            params: {
              'done': '${queue.done}',
              'total': '${queue.total}',
              'status': statusText,
              'percent': progressPercent,
              'eta': etaText,
            },
          );
    return BaseCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      color: TerminalUiPalette.pageBackground,
      border: true,
      radius: 6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          compactLayout
              ? Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Icon(
                      isDownload ? Icons.cloud_download : Icons.cloud_upload,
                      size: 14,
                      color: Colors.blueGrey,
                    ),
                    Text(queueName, style: const TextStyle(fontSize: 11)),
                    if (queue.canCancel)
                      AppTextButton(
                        onPressed: () => queuePaused
                            ? appState.resumeTransferQueue(session, queue.id)
                            : appState.pauseTransferQueue(session, queue.id),
                        label: queuePaused
                            ? t(context, AppStrings.values.resume)
                            : t(context, AppStrings.values.pause),
                        size: ButtonSize.small,
                      ),
                    if (queue.canCancel)
                      AppTextButton(
                        onPressed: () =>
                            appState.cancelTransferQueue(session, queue.id),
                        label: t(context, AppStrings.values.cancel),
                        size: ButtonSize.small,
                      ),
                  ],
                )
              : Row(
                  children: [
                    Icon(
                      isDownload ? Icons.cloud_download : Icons.cloud_upload,
                      size: 14,
                      color: Colors.blueGrey,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        queueName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    if (queue.canCancel)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 14,
                        tooltip: queuePaused
                            ? t(context, AppStrings.values.resume)
                            : t(context, AppStrings.values.pause),
                        onPressed: () => queuePaused
                            ? appState.resumeTransferQueue(session, queue.id)
                            : appState.pauseTransferQueue(session, queue.id),
                        icon: Icon(
                          queuePaused ? Icons.play_arrow : Icons.pause,
                        ),
                      ),
                    if (queue.canCancel)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 14,
                        tooltip: t(context, AppStrings.values.cancel),
                        onPressed: () =>
                            appState.cancelTransferQueue(session, queue.id),
                        icon: const Icon(Icons.close),
                      ),
                  ],
                ),
          const SizedBox(height: 2),
          Text(
            progressLine,
            style: const TextStyle(
              fontSize: 10,
              color: TerminalUiPalette.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: queue.preparing ? null : queue.progress,
            minHeight: 4,
            backgroundColor: TerminalUiPalette.border,
            valueColor: const AlwaysStoppedAnimation(TerminalUiPalette.accent),
          ),
        ],
      ),
    );
  }
}

String _formatEta(TerminalAppState appState, int seconds) {
  if (seconds <= 0) {
    return l(appState, AppStrings.values.lessThanOneSecond);
  }
  if (seconds < 60) {
    return l(
      appState,
      AppStrings.values.secondsShortVar,
      params: {'seconds': '$seconds'},
    );
  }
  final minutes = seconds ~/ 60;
  final remains = seconds % 60;
  return l(
    appState,
    AppStrings.values.minutesSecondsVarVar,
    params: {'minutes': '$minutes', 'seconds': '$remains'},
  );
}

