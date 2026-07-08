import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:safe_layout_x/safe_layout_x.dart';

import '../../../../shared/constants/app_string.dart';
import '../../state/terminal_app_state.dart';

String l(
  TerminalAppState appState,
  AppText text, {
  Map<String, String> params = const {},
}) {
  return text.resolve(appState.locale.languageCode, params: params);
}

String t(
  BuildContext context,
  AppText text, {
  Map<String, String> params = const {},
}) {
  final appState = Provider.of<TerminalAppState>(context, listen: false);
  return l(appState, text, params: params);
}

void showBannerAndLog(TerminalAppState appState, BannerData data) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    BannerManager.show(data);
  });
}

void showErrorIfNeeded(BuildContext context, TerminalAppState appState) {
  final message = appState.lastError;
  if (message == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    BannerManager.show(
      BannerData(
        id: 'error-$timestamp',
        type: BannerType.error,
        title: l(appState, AppStrings.values.failed),
        message: message,
      ),
    );
    appState.clearError();
  });
}
