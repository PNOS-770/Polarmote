import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

import '../../../../../shared/constants/app_string.dart';
import '../../../../../shared/design_system/design_system.dart';
import '../../../state/terminal_app_state_models.dart';

class AudioFileViewer extends StatefulWidget {
  const AudioFileViewer({
    required this.filePath,
    this.downloadProgressStream,
    super.key,
  });

  final String filePath;
  final Stream<InternalViewerDownloadProgress>? downloadProgressStream;

  @override
  State<AudioFileViewer> createState() => _AudioFileViewerState();
}

class _AudioFileViewerState extends State<AudioFileViewer> {
  static const Duration _retryDelay = Duration(milliseconds: 500);
  static const int _minInitialBufferBytes = 256 * 1024;

  late final Player _player = Player();
  StreamSubscription<InternalViewerDownloadProgress>? _downloadProgressSub;
  StreamSubscription<Duration>? _playerBufferSub;
  StreamSubscription<Duration>? _playerDurationSub;
  Timer? _retryTimer;

  String? _error;
  bool _opening = false;
  bool _opened = false;
  bool _pendingOpen = true;
  bool _downloadDone = true;
  int _downloadDoneOpenAttempts = 0;
  int _downloadedBytes = 0;
  int? _downloadTotalBytes;
  Duration _bufferPosition = Duration.zero;
  Duration _mediaDuration = Duration.zero;

  String get _localeCode =>
      (Localizations.maybeLocaleOf(context)?.languageCode ?? 'en').toLowerCase();

  @override
  void initState() {
    super.initState();
    _bindPlayerProgress();
    _bindDownloadProgress();
    _scheduleRetry(delay: Duration.zero);
  }

  @override
  void dispose() {
    _downloadProgressSub?.cancel();
    _playerBufferSub?.cancel();
    _playerDurationSub?.cancel();
    _retryTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  void _bindPlayerProgress() {
    _playerBufferSub = _player.stream.buffer.listen((value) {
      _bufferPosition = value;
      if (mounted) {
        setState(() {});
      }
    });
    _playerDurationSub = _player.stream.duration.listen((value) {
      _mediaDuration = value;
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _bindDownloadProgress() {
    final stream = widget.downloadProgressStream;
    if (stream == null) {
      return;
    }
    _downloadDone = false;
    _downloadProgressSub = stream.listen(
      (event) {
        final justCompleted = !_downloadDone && event.done;
        _downloadedBytes = event.downloadedBytes;
        _downloadTotalBytes = event.totalBytes;
        _downloadDone = event.done;
        final eventError = (event.error ?? '').trim();
        if (eventError.isNotEmpty) {
          _error = eventError;
          _downloadDone = true;
        }
        if (justCompleted) {
          _downloadDoneOpenAttempts = 0;
          if (!_opened) {
            _pendingOpen = true;
            _scheduleRetry(delay: Duration.zero);
          }
        } else if (!_opened && _canAttemptOpenNow()) {
          _pendingOpen = true;
          _scheduleRetry(delay: Duration.zero);
        }
        if (mounted) {
          setState(() {});
        }
      },
      onError: (Object error) {
        _error = '$error';
        _downloadDone = true;
        if (mounted) {
          setState(() {});
        }
      },
      onDone: () {
        _downloadDone = true;
        if (!_opened) {
          _pendingOpen = true;
          _scheduleRetry(delay: Duration.zero);
        }
        if (mounted) {
          setState(() {});
        }
      },
    );
  }

  bool _canAttemptOpenNow() {
    if (widget.downloadProgressStream == null) {
      return true;
    }
    if (_downloadDone) {
      return true;
    }
    return _downloadedBytes >= _requiredBufferBytes();
  }

  int _requiredBufferBytes() {
    final total = _downloadTotalBytes;
    if (total == null || total <= 0) {
      return _minInitialBufferBytes;
    }
    final byRatio = (total * 0.02).round();
    return byRatio.clamp(64 * 1024, _minInitialBufferBytes).toInt();
  }

  Future<void> _tryOpen() async {
    if (!mounted || _opening || !_pendingOpen) {
      return;
    }
    if (_opened) {
      _pendingOpen = false;
      return;
    }
    if (!_canAttemptOpenNow()) {
      if (!_downloadDone) {
        _scheduleRetry();
      }
      return;
    }
    _pendingOpen = false;
    if (widget.downloadProgressStream != null && _error != null) {
      _error = null;
    }

    final file = File(widget.filePath);
    if (!await file.exists()) {
      if (widget.downloadProgressStream != null && !_downloadDone) {
        _pendingOpen = true;
        _scheduleRetry();
      } else {
        _error ??= AppStrings.values.fileNotFound.resolve(_localeCode);
      }
      if (mounted) {
        setState(() {});
      }
      return;
    }

    _opening = true;
    if (mounted) {
      setState(() {});
    }
    try {
      await _openWithFallback();
      if (!mounted) {
        return;
      }
      _opened = true;
      _error = null;
      _downloadDoneOpenAttempts = 0;
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (widget.downloadProgressStream == null) {
        _error = '$error';
      } else if (!_downloadDone) {
        _pendingOpen = true;
        _scheduleRetry();
      } else {
        _downloadDoneOpenAttempts += 1;
        if (_downloadDoneOpenAttempts <= 6) {
          _pendingOpen = true;
          _scheduleRetry();
        } else {
          _error = '$error';
        }
      }
    } finally {
      _opening = false;
      if (mounted) {
        setState(() {});
      }
      if (_pendingOpen) {
        _scheduleRetry(delay: Duration.zero);
      }
    }
  }

  Future<void> _openWithFallback() async {
    final uriPath = Uri.file(
      widget.filePath,
      windows: Platform.isWindows,
    ).toString();
    final sources = <String>{widget.filePath, uriPath};
    Object? lastError;
    for (final source in sources) {
      try {
        final timeout = _downloadDone
            ? const Duration(seconds: 10)
            : const Duration(seconds: 4);
        await _player.open(Media(source), play: true).timeout(timeout);
        return;
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError ?? StateError('Unable to open audio source.');
  }

  void _scheduleRetry({Duration? delay}) {
    if (_retryTimer?.isActive ?? false) {
      return;
    }
    _retryTimer = Timer(delay ?? _retryDelay, () {
      _retryTimer = null;
      unawaited(_tryOpen());
    });
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '${bytes}B';
    }
    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)}KB';
    }
    final mb = kb / 1024;
    if (mb < 1024) {
      return '${mb.toStringAsFixed(1)}MB';
    }
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)}GB';
  }

  String _progressText() {
    final total = _downloadTotalBytes;
    if (total != null && total > 0) {
      return '${_formatBytes(_downloadedBytes)}/${_formatBytes(total)}';
    }
    return _formatBytes(_downloadedBytes);
  }

  String _formatDuration(Duration value) {
    final totalSeconds = value.inSeconds.clamp(0, 99 * 3600 + 59 * 60 + 59);
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$mm:$ss';
    }
    return '$mm:$ss';
  }

  String _playableProgressText() {
    final durationMs = _mediaDuration.inMilliseconds;
    if (durationMs <= 0) {
      return AppStrings.values.playablePreparing.resolve(_localeCode);
    }
    final playableMs = _bufferPosition.inMilliseconds.clamp(0, durationMs);
    final ratio = (playableMs / durationMs).clamp(0.0, 1.0);
    return AppStrings.values.playableProgressVar.resolve(_localeCode, params: {
      'position': _formatDuration(Duration(milliseconds: playableMs)),
      'duration': _formatDuration(_mediaDuration),
      'percent': '${(ratio * 100).toStringAsFixed(1)}%',
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = p.basename(widget.filePath);
    final hasRemoteProgress = widget.downloadProgressStream != null;
    if (_error != null) {
      return Center(
        child: Text(AppStrings.values.failedToLoadAudioVar.resolve(_localeCode, params: {'error': _error!})),
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.audiotrack_rounded, size: 44),
                const SizedBox(height: 10),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.h5,
                ),
                if (hasRemoteProgress) ...[
                  const SizedBox(height: 8),
                  Text(
                    _playableProgressText(),
                    style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _downloadDone
                        ? AppStrings.values.downloadedProgressCompleteVar.resolve(_localeCode, params: {'progress': _progressText()})
                        : AppStrings.values.downloadedProgressVar.resolve(_localeCode, params: {'progress': _progressText()}),
                    style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                  ),
                ],
                if (_opening || !_opened) ...[
                  const SizedBox(height: 8),
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  children: [
                    SecondaryButton(
                      onPressed: _opened ? () => _player.play() : null,
                      label: AppStrings.values.play.resolve(_localeCode),
                    ),
                    SecondaryButton(
                      onPressed: _opened ? () => _player.pause() : null,
                      label: AppStrings.values.pauseAudio.resolve(_localeCode),
                    ),
                    SecondaryButton(
                      onPressed: _opened ? () => _player.stop() : null,
                      label: AppStrings.values.stopAudio.resolve(_localeCode),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

