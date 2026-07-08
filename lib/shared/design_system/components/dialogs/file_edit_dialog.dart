import 'dart:async';

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../buttons/app_buttons.dart';
import '../cards/base_card.dart';

class AppFileEditDialog extends StatefulWidget {
  const AppFileEditDialog({
    super.key,
    required this.title,
    required this.initialContent,
    required this.onSave,
    this.onOpenInSystem,
    this.saveLabel = 'Save',
    this.closeLabel = 'Close',
    this.cancelLabel = 'Cancel',
    this.discardLabel = 'Discard',
    this.openInSystemLabel = 'Open in system',
    this.confirmCloseLabel = 'You have unsaved changes. Save before closing?',
    this.unsavedMarker = ' *',
    this.failedLabel = 'Failed to load',
  });

  final String title;
  final String initialContent;
  final Future<bool> Function(String content) onSave;
  final VoidCallback? onOpenInSystem;
  final String saveLabel;
  final String closeLabel;
  final String cancelLabel;
  final String discardLabel;
  final String openInSystemLabel;
  final String confirmCloseLabel;
  final String unsavedMarker;
  final String failedLabel;

  @override
  State<AppFileEditDialog> createState() => _AppFileEditDialogState();
}

class _AppFileEditDialogState extends State<AppFileEditDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _saving = false;
  String _initialText = '';
  bool _hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
    _initialText = widget.initialContent;
    _controller.text = widget.initialContent;
    _controller.addListener(() {
      final changed = _controller.text != _initialText;
      if (_hasUnsavedChanges != changed) {
        setState(() => _hasUnsavedChanges = changed);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<bool> _saveContent() async {
    if (_saving) return false;
    setState(() => _saving = true);
    final ok = await widget.onSave(_controller.text);
    if (!mounted) return false;
    setState(() => _saving = false);
    if (ok) {
      _initialText = _controller.text;
      if (_hasUnsavedChanges) setState(() => _hasUnsavedChanges = false);
    }
    return ok;
  }

  Future<bool> _confirmClose() async {
    if (_saving) return false;
    if (!_hasUnsavedChanges) return true;
    final action = await showDialog<_UnsavedAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.radiusDialog),
        title: Text('Unsaved Changes', style: AppTextStyles.h4),
        content: Text(widget.confirmCloseLabel),
        actionsPadding: const EdgeInsets.all(AppSpacing.lg),
        actions: [
          AppTextButton(
            onPressed: () => Navigator.pop(ctx, _UnsavedAction.cancel),
            label: widget.cancelLabel,
            size: ButtonSize.small,
          ),
          AppTextButton(
            onPressed: () => Navigator.pop(ctx, _UnsavedAction.discard),
            label: widget.discardLabel,
            size: ButtonSize.small,
          ),
          PrimaryButton(
            onPressed: () => Navigator.pop(ctx, _UnsavedAction.save),
            label: widget.saveLabel,
            size: ButtonSize.medium,
          ),
        ],
      ),
    );
    if (!mounted) return false;
    switch (action) {
      case _UnsavedAction.cancel:
        return false;
      case _UnsavedAction.discard:
        return true;
      case _UnsavedAction.save:
        return await _saveContent();
      case null:
        return false;
    }
  }

  Future<void> _handleClosePressed() async {
    if (_saving) return;
    if (_hasUnsavedChanges) {
      final shouldClose = await _confirmClose();
      if (!mounted || !shouldClose) return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_saving) return;
        if (_hasUnsavedChanges) {
          final shouldClose = await _confirmClose();
          if (!mounted || !shouldClose) return;
        }
        Navigator.of(this.context).pop();
      },
      child: AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.radiusDialog),
        title: Text(
          '${widget.title}${_hasUnsavedChanges ? widget.unsavedMarker : ''}',
          style: AppTextStyles.h4,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        content: SizedBox(
          width: 860,
          height: 560,
          child: BaseCard(
            border: true,
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: _controller,
              expands: true,
              minLines: null,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.35,
              ),
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
              ),
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.all(AppSpacing.lg),
        actions: [
          if (widget.onOpenInSystem != null)
            AppTextButton(
              onPressed: widget.onOpenInSystem,
              label: widget.openInSystemLabel,
              size: ButtonSize.small,
            ),
          AppTextButton(
            onPressed: _saving ? null : _handleClosePressed,
            label: widget.closeLabel,
            size: ButtonSize.small,
          ),
          PrimaryButton(
            onPressed: _saving ? null : () => unawaited(_saveContent()),
            label: widget.saveLabel,
            loading: _saving,
            size: ButtonSize.medium,
          ),
        ],
      ),
    );
  }
}

enum _UnsavedAction { cancel, discard, save }

