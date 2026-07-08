part of 'terminal_dialogs.dart';

class _SettingTextField extends StatelessWidget {
  const _SettingTextField({
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
    required this.onSubmit,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    final isMobile = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: TerminalUiPalette.textSecondary,
                    ),
                  ),
                ),
                TextField(
                  controller: controller,
                  keyboardType: keyboardType,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    hintText: hint,
                  ),
                  onSubmitted: onSubmit,
                ),
              ],
            )
          : Row(
              children: [
                SizedBox(
                  width: 100,
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: TerminalUiPalette.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: controller,
                    keyboardType: keyboardType,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      hintText: hint,
                    ),
                    onSubmitted: onSubmit,
                  ),
                ),
              ],
            ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _VisitedFileLoadProgress {
  const _VisitedFileLoadProgress({
    required this.downloadedBytes,
    required this.totalBytes,
  });

  final int downloadedBytes;
  final int? totalBytes;
}

class _VisitedFileLoadingDialog extends StatelessWidget {
  const _VisitedFileLoadingDialog({
    required this.appState,
    required this.fileName,
    required this.progress,
  });

  final TerminalAppState appState;
  final String fileName;
  final ValueListenable<_VisitedFileLoadProgress> progress;

  @override
  Widget build(BuildContext context) {
    final languageCode = appState.locale.languageCode;
    final loadingText = AppStrings.values.loadingFilePreview.resolve(
      languageCode,
    );
    return Dialog(
      backgroundColor: TerminalUiPalette.cardBackground,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: ValueListenableBuilder<_VisitedFileLoadProgress>(
          valueListenable: progress,
          builder: (context, value, _) {
            final totalBytes = value.totalBytes;
            final downloaded = value.downloadedBytes
                .clamp(0, totalBytes ?? value.downloadedBytes)
                .toInt();
            final percent = totalBytes != null && totalBytes > 0
                ? (downloaded / totalBytes).clamp(0.0, 1.0)
                : null;
            final progressLabel = totalBytes != null && totalBytes > 0
                ? '${formatBytes(downloaded)}/${formatBytes(totalBytes)}  ${(percent! * 100).toStringAsFixed(1)}%'
                : formatBytes(downloaded);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loadingText,
                  style: const TextStyle(
                    color: TerminalUiPalette.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: TerminalUiPalette.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percent,
                    minHeight: 6,
                    backgroundColor: TerminalUiPalette.border,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      TerminalUiPalette.accent,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  progressLabel,
                  style: const TextStyle(
                    color: TerminalUiPalette.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Widget icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? TerminalUiPalette.accent
        : TerminalUiPalette.border;
    final background = selected
        ? TerminalUiPalette.accentSelectedLight
        : TerminalUiPalette.cardBackground;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: selected
                    ? TerminalUiPalette.accent
                    : TerminalUiPalette.textPrimary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogField extends StatelessWidget {
  const _DialogField({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.obscureText = false,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        decoration: InputDecoration(
          labelText: label,
        ),
      ),
    );
  }
}

class _CategoryInfo {
  const _CategoryInfo({
    required this.title,
    required this.icon,
    required this.builder,
  });

  final String title;
  final IconData icon;
  final Widget Function() builder;
}

class _SettingSwitchRow extends StatelessWidget {
  const _SettingSwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 12))),
          Transform.scale(
            scale: 0.9,
            child: Switch(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingActionRow extends StatelessWidget {
  const _SettingActionRow({
    required this.title,
    required this.value,
    this.onMoreTapDown,
  });

  final String title;
  final String value;
  final void Function(TapDownDetails details)? onMoreTapDown;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: TextStyle(fontSize: 10.5, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
          if (onMoreTapDown != null)
            CompactMoreMenuButton(
              tooltip: t(context, AppStrings.values.more),
              onTapDown: onMoreTapDown!,
              icon: Icons.more_horiz,
              iconSize: 18,
              padding: 1,
            ),
        ],
      ),
    );
  }
}

class _ShortcutCaptureDialog extends StatefulWidget {
  const _ShortcutCaptureDialog({
    required this.title,
    required this.currentKeys,
  });

  final String title;
  final String currentKeys;

  @override
  State<_ShortcutCaptureDialog> createState() => _ShortcutCaptureDialogState();
}

class _ShortcutCaptureDialogState extends State<_ShortcutCaptureDialog> {
  String _captured = '';
  bool _listening = true;

  String _captureHint(BuildContext ctx) =>
      t(ctx, AppStrings.values.pressNewShortcut);

  String _captureLabel(BuildContext ctx, AppText text) => t(ctx, text);

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!_listening) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_captured.isNotEmpty) {
        Navigator.pop(context, _captured);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete) {
      setState(() => _captured = '');
      return KeyEventResult.handled;
    }
    final isModifier = key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight;
    if (!isModifier) {
      final parts = <String>[];
      final kb = HardwareKeyboard.instance;
      if (kb.isControlPressed) parts.add('Ctrl');
      if (kb.isAltPressed) parts.add('Alt');
      if (kb.isShiftPressed) parts.add('Shift');
      if (kb.isMetaPressed) parts.add('Meta');
      parts.add(shortcutKeyName(key) ?? '');
      setState(() {
        _captured = parts.join('+');
        _listening = false;
      });
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) setState(() => _listening = true);
      });
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.radiusDialog,
      ),
      title: Text(widget.title, style: AppTextStyles.h4),
      content: Focus(
        autofocus: true,
        onKeyEvent: _handleKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _captured.isEmpty
                  ? _captureHint(context)
                  : _captured,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _captured.isEmpty
                    ? Colors.grey
                    : TerminalUiPalette.accent,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_captureLabel(context, AppStrings.values.currentLabel)}: ${widget.currentKeys}',
              style: const TextStyle(
                fontSize: 11,
                color: TerminalUiPalette.textSecondary,
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.all(AppSpacing.lg),
      actions: [
        if (_captured.isNotEmpty)
          AppTextButton(
            onPressed: () => Navigator.pop(context, ''),
            label: t(context, AppStrings.values.resetToDefault),
            size: ButtonSize.small,
          ),
        SecondaryButton(
          onPressed: () => Navigator.pop(context),
          label: t(context, AppStrings.values.cancel),
          size: ButtonSize.small,
        ),
        if (_captured.isNotEmpty) ...[
          const SizedBox(width: AppSpacing.sm),
          PrimaryButton(
            onPressed: () => Navigator.pop(context, _captured),
            label: t(context, AppStrings.values.save),
            size: ButtonSize.small,
          ),
        ],
      ],
    );
  }
}

