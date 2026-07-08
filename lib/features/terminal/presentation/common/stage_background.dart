import 'dart:io';

import 'package:flutter/material.dart';
import '../../state/terminal_app_state.dart';

String? backgroundImagePathForStage(
  TerminalAppState appState,
  TerminalStage stage,
) {
  if (stage.backgroundImageId.isEmpty) return null;
  for (final e in appState.terminalBackgroundImages) {
    if (e.id == stage.backgroundImageId) return e.path;
  }
  return null;
}

Widget buildStageBackgroundImage(String bgPath) {
  return Positioned.fill(
    child: Image.file(
      File(bgPath),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    ),
  );
}

