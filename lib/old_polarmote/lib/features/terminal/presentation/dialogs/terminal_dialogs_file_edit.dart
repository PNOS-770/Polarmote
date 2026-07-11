part of 'terminal_dialogs.dart';

class _FileEditDialog extends StatefulWidget {
  const _FileEditDialog({
    required this.appState,
    required this.session,
    required this.node,
  });

  final TerminalAppState appState;
  final TerminalSession session;
  final FileNode node;

  @override
  State<_FileEditDialog> createState() => _FileEditDialogState();
}

class _FileEditDialogState extends State<_FileEditDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _loadFailed = false;
  String _initialText = '';
  bool _hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    unawaited(_loadContent());
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_loading) return;
    final changed = _controller.text != _initialText;
    if (_hasUnsavedChanges == changed) return;
    setState(() {
      _hasUnsavedChanges = changed;
    });
  }

  Future<void> _loadContent() async {
    final text = await widget.appState.loadEditableFileText(
      widget.session,
      widget.node,
    );
    if (!mounted) return;
    if (text == null) {
      setState(() {
        _loadFailed = true;
        _loading = false;
      });
      return;
    }
    _controller.text = text;
    _initialText = text;
    setState(() {
      _loading = false;
      _hasUnsavedChanges = false;
    });
  }

  Future<bool> _saveContent() async {
    if (_saving || _loading || _loadFailed) return false;
    setState(() {
      _saving = true;
    });
    final ok = await widget.appState.saveEditableFileText(
      widget.session,
      widget.node,
      _controller.text,
    );
    if (!mounted) return false;
    setState(() {
      _saving = false;
    });
    if (ok) {
      _initialText = _controller.text;
      if (_hasUnsavedChanges) {
        setState(() {
          _hasUnsavedChanges = false;
        });
      }
      return true;
    }
    return false;
  }

  Future<_UnsavedCloseAction> _showUnsavedCloseDialog() async {
    final action = await showDialog<_UnsavedCloseAction>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.cardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.radiusDialog,
          ),
          title: Text(
            t(context, AppStrings.values.confirm),
            style: AppTextStyles.h4,
          ),
          content: Text(t(context, AppStrings.values.unsavedChangesPrompt)),
          actionsPadding: const EdgeInsets.all(AppSpacing.lg),
          actions: [
            AppTextButton(
              onPressed: () =>
                  Navigator.pop(context, _UnsavedCloseAction.cancel),
              label: t(context, AppStrings.values.cancel),
              size: ButtonSize.small,
            ),
            AppTextButton(
              onPressed: () =>
                  Navigator.pop(context, _UnsavedCloseAction.discard),
              label: t(context, AppStrings.values.discard),
              size: ButtonSize.small,
            ),
            PrimaryButton(
              onPressed: () => Navigator.pop(context, _UnsavedCloseAction.save),
              label: t(context, AppStrings.values.save),
              size: ButtonSize.medium,
            ),
          ],
        );
      },
    );
    return action ?? _UnsavedCloseAction.cancel;
  }

  Future<bool> _confirmClose() async {
    if (_saving) return false;
    if (!_hasUnsavedChanges) return true;
    final action = await _showUnsavedCloseDialog();
    if (!mounted) return false;
    switch (action) {
      case _UnsavedCloseAction.cancel:
        return false;
      case _UnsavedCloseAction.discard:
        return true;
      case _UnsavedCloseAction.save:
        return await _saveContent();
    }
  }

  Future<void> _handleClosePressed() async {
    final shouldClose = await _confirmClose();
    if (!mounted || !shouldClose) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldClose = await _confirmClose();
        if (!mounted || !shouldClose) return;
        Navigator.of(this.context).pop();
      },
      child: AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.radiusDialog,
        ),
        title: Text(
          '${t(context, AppStrings.values.edit)} 路 ${widget.node.name}${_hasUnsavedChanges ? " *" : ""}',
          style: AppTextStyles.h4,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        content: SizedBox(
          width: 860,
          height: 560,
          child: _loading
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(height: 12),
                      Text(t(context, AppStrings.values.loading)),
                    ],
                  ),
                )
              : _loadFailed
              ? Center(child: Text(t(context, AppStrings.values.failed)))
              : BaseCard(
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
          AppTextButton(
            onPressed: () => unawaited(
              widget.appState.openRemoteFileWithSystem(
                widget.session,
                widget.node,
              ),
            ),
            label: t(context, AppStrings.values.openInSystem),
            size: ButtonSize.small,
          ),
          AppTextButton(
            onPressed: _saving ? null : _handleClosePressed,
            label: t(context, AppStrings.values.close),
            size: ButtonSize.small,
          ),
          PrimaryButton(
            onPressed: _saving || _loading || _loadFailed
                ? null
                : () => unawaited(_saveContent()),
            label: t(context, AppStrings.values.save),
            loading: _saving,
            size: ButtonSize.medium,
          ),
        ],
      ),
    );
  }
}
