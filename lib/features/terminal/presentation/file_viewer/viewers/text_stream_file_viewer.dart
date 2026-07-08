import 'dart:io';
import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../../shared/constants/app_string.dart';
import '../../../../../shared/design_system/design_system.dart';
import '../../../../../shared/logging/Polarmote_log.dart';

typedef TextSaveCallback = Future<bool> Function(String content);

class TextStreamFileViewer extends StatefulWidget {
  const TextStreamFileViewer({
    required this.filePath,
    required this.truncated,
    required this.maxPreviewBytes,
    this.downloadProgressStream,
    this.onSave,
    this.initialScrollOffset = 0.0,
    this.onPersistScrollOffset,
    super.key,
  });

  final String filePath;
  final bool truncated;
  final int maxPreviewBytes;
  final Stream<dynamic>? downloadProgressStream;
  final TextSaveCallback? onSave;
  final double initialScrollOffset;
  final ValueChanged<double>? onPersistScrollOffset;

  @override
  State<TextStreamFileViewer> createState() => _TextStreamFileViewerState();
}

class _TextStreamFileViewerState extends State<TextStreamFileViewer> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _persistDebounce;
  Timer? _thumbFadeTimer;

  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String _baseline = '';
  String? _error;
  bool _scrollRestored = false;
  bool _thumbVisible = false;

  bool get _readOnly => widget.truncated || widget.onSave == null;

  String get _localeCode =>
      (Localizations.maybeLocaleOf(context)?.languageCode ?? 'en').toLowerCase();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleEditorChange);
    _scrollController.addListener(_handleScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _controller.removeListener(_handleEditorChange);
    _controller.dispose();
    _scrollController.removeListener(_handleScroll);
    if (widget.onPersistScrollOffset != null && _scrollController.hasClients) {
      widget.onPersistScrollOffset!(_scrollController.offset);
    }
    _persistDebounce?.cancel();
    _thumbFadeTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    _showThumbTemporarily();
    if (widget.onPersistScrollOffset == null) return;
    if (!_scrollController.hasClients) return;
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;
      widget.onPersistScrollOffset!(_scrollController.offset);
    });
  }

  void _showThumbTemporarily() {
    if (!_thumbVisible && mounted) {
      setState(() {
        _thumbVisible = true;
      });
    }
    _thumbFadeTimer?.cancel();
    _thumbFadeTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || !_thumbVisible) return;
      setState(() {
        _thumbVisible = false;
      });
    });
  }

  void _restoreScrollIfNeeded() {
    if (_scrollRestored) return;
    _scrollRestored = true;
    final target = widget.initialScrollOffset;
    if (!target.isFinite || target <= 0) return;

    void restoreWithRetry(int retriesLeft) {
      if (!mounted) return;
      if (!_scrollController.hasClients) {
        if (retriesLeft > 0) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => restoreWithRetry(retriesLeft - 1),
          );
        }
        return;
      }
      final max = _scrollController.position.maxScrollExtent;
      if (max <= 0 && retriesLeft > 0) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => restoreWithRetry(retriesLeft - 1),
        );
        return;
      }
      final clamped = target.clamp(0.0, max).toDouble();
      if (clamped <= 0) return;
      _scrollController.jumpTo(clamped);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      restoreWithRetry(6);
    });
  }

  Future<void> _loadInitial() async {
    try {
      final file = File(widget.filePath);
      if (!await file.exists()) {
        throw StateError(AppStrings.values.fileNotFound.en);
      }
      final bytes = await file.readAsBytes();
      final text = utf8.decode(bytes, allowMalformed: true);
      if (!mounted) {
        return;
      }
      _baseline = text;
      _controller.text = text;
      setState(() {
        _loading = false;
        _dirty = false;
      });
      _restoreScrollIfNeeded();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  void _handleEditorChange() {
    if (_loading) {
      return;
    }
    final dirty = _controller.text != _baseline;
    if (dirty == _dirty || !mounted) {
      return;
    }
    setState(() {
      _dirty = dirty;
    });
  }

  Future<void> _save() async {
    if (_saving || _readOnly || !_dirty) {
      return;
    }
    setState(() {
      _saving = true;
    });
    final content = _controller.text;
    try {
      final ok = await widget.onSave!(content);
      if (!mounted) {
        return;
      }
      if (!ok) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStrings.values.saveFailed.resolve(_localeCode))));
        setState(() {
          _saving = false;
        });
        return;
      }
      _baseline = content;
      try {
        await File(widget.filePath).writeAsString(content, flush: true);
      } catch (e) { PolarmoteLog.error('text_stream_file_viewer', '$e'); }
      setState(() {
        _saving = false;
        _dirty = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppStrings.values.saveFailedVar.resolve(_localeCode, params: {'error': '$error'}))));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: AppTextStyles.error),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.truncated)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Color(0xFFFFF8E1),
              borderRadius: AppRadius.radiusLG,
              border: Border.all(color: Color(0xFFFFECB3)),
            ),
            child: Text(
              AppStrings.values.previewTruncatedVar.resolve(_localeCode, params: {'size': '${widget.maxPreviewBytes ~/ 1024}'}),
              style: AppTextStyles.caption.copyWith(color: AppColors.warningDark),
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: RawScrollbar(
              controller: _scrollController,
              interactive: true,
              thumbVisibility: _thumbVisible,
              thickness: 10,
              radius: const Radius.circular(6),
              timeToFade: const Duration(seconds: 4),
              fadeDuration: const Duration(milliseconds: 180),
              thumbColor: const Color(0x99000000),
              child: TextField(
                controller: _controller,
                scrollController: _scrollController,
                readOnly: _readOnly,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                style: AppTextStyles.code.copyWith(fontSize: 13),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: AppRadius.radiusLG,
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: AppRadius.radiusLG,
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: AppRadius.radiusLG,
                    borderSide: const BorderSide(color: AppColors.primary),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ),
          ),
        ),
        Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.backgroundGrey,
            border: const Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Text(
                _readOnly
                    ? AppStrings.values.readOnly.resolve(_localeCode)
                    : (_dirty ? AppStrings.values.modifiedLabel.resolve(_localeCode) : (_saving ? AppStrings.values.savingLabel.resolve(_localeCode) : AppStrings.values.savedLabel.resolve(_localeCode))),
                style: AppTextStyles.caption,
              ),
              const Spacer(),
              SecondaryButton(
                onPressed: _readOnly || !_dirty || _saving ? null : _save,
                label: AppStrings.values.saveLabel.resolve(_localeCode),
                size: ButtonSize.small,
              ),
            ],
          ),
        ),
      ],
    );
  }
}



