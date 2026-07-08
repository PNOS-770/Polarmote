import 'dart:io';

import 'package:flutter/material.dart';
import '../../../../shared/design_system/design_system.dart';
import '../../../../shared/constants/app_string.dart';
import '../../state/terminal_app_state.dart';
import 'terminal_localization.dart';

Future<void> showStageBackgroundPicker(
  BuildContext context,
  TerminalAppState appState,
  TerminalStage stage,
) async {
  final images = appState.terminalBackgroundImages;
  final currentBgId = stage.backgroundImageId;

  if (!context.mounted) return;
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(l(appState, AppStrings.values.selectBackground)),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, ''),
          child: Row(children: [
            Container(
              width: 32,
              height: 24,
              decoration: BoxDecoration(
                color: AppColors.grey200,
                borderRadius: BorderRadius.circular(2),
              ),
              child: '' == currentBgId
                  ? const Icon(Icons.check, size: 14)
                  : null,
            ),
            const SizedBox(width: 8),
            Text(l(appState, AppStrings.values.noBackground)),
          ]),
        ),
        for (final image in images)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, image.id),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  width: 32,
                  height: 24,
                  child: Image.file(
                    File(image.path),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image,
                      size: 14,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  image.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (image.id == currentBgId)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.check, size: 14),
                ),
            ]),
          ),
      ],
    ),
  );
  if (result != null && context.mounted) {
    appState.setStageBackgroundImage(stage.id, result);
  }
}

