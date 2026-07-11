part of 'terminal_dialogs.dart';

Future<void> showRenameTabDialog(
  BuildContext context,
  TerminalAppState appState,
  TerminalSession session,
) async {
  final newName = await showInputDialog(
    context,
    title: t(context, AppStrings.values.renameTab),
    initialValue: session.tab.title,
    confirmText: t(context, AppStrings.values.save),
    cancelText: t(context, AppStrings.values.cancel),
    validator: (v) => v == null || v.trim().isEmpty ? '' : null,
  );
  if (newName != null && newName.trim().isNotEmpty && context.mounted) {
    appState.renameSessionTab(session, newName.trim());
  }
}

Future<void> handleCloseSession(
  BuildContext context,
  TerminalAppState appState,
  TerminalSession session,
) async {
  if (appState.hasOngoingTransfers(session)) {
    final confirm = await _confirmDialog(
      context,
      t(
        context,
        AppStrings.values.transfersAreRunningClosingWillStopThemContinue,
      ),
    );
    if (!confirm) return;
  }
  await appState.closeSession(session.id);
}

Future<void> showCreateFolderDialog(
  BuildContext context,
  TerminalAppState appState,
  TerminalSession session,
) async {
  final name = await showInputDialog(
    context,
    title: t(context, AppStrings.values.newFolder),
    hint: t(context, AppStrings.values.folderName),
    confirmText: t(context, AppStrings.values.create),
    cancelText: t(context, AppStrings.values.cancel),
    validator: (v) => v == null || v.trim().isEmpty ? '' : null,
  );
  if (name != null && name.trim().isNotEmpty && context.mounted) {
    final parent = session.fileState.currentPath.isNotEmpty
        ? session.fileState.currentPath
        : session.fileState.rootPath;
    unawaited(appState.createDirectory(session, parent, name.trim()));
  }
}

Future<void> showCreateFileDialog(
  BuildContext context,
  TerminalAppState appState,
  TerminalSession session,
) async {
  final name = await showInputDialog(
    context,
    title: t(context, AppStrings.values.newFile),
    hint: t(context, AppStrings.values.name),
    confirmText: t(context, AppStrings.values.create),
    cancelText: t(context, AppStrings.values.cancel),
    validator: (v) => v == null || v.trim().isEmpty ? '' : null,
  );
  if (name != null && name.trim().isNotEmpty && context.mounted) {
    final parent = session.fileState.currentPath.isNotEmpty
        ? session.fileState.currentPath
        : session.fileState.rootPath;
    unawaited(appState.createFile(session, parent, name.trim()));
  }
}

Future<void> showFileEditDialog(
  BuildContext context,
  TerminalAppState appState,
  TerminalSession session,
  FileNode node,
) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return _FileEditDialog(appState: appState, session: session, node: node);
    },
  );
}

Future<void> showFileMenu(
  BuildContext context,
  TerminalAppState appState,
  TerminalSession session,
  FileNode node,
  Offset position,
) async {
  final action = await showCompactMenu<_FileAction>(
    context: context,
    position: position,
    items: [
      if (!session.profile.isLocal && !node.isDirectory)
        compactMenuItem(
          value: _FileAction.download,
          label: t(context, AppStrings.values.download),
        ),
      compactMenuItem(
        value: _FileAction.rename,
        label: t(context, AppStrings.values.rename),
      ),
      compactMenuItem(
        value: _FileAction.delete,
        label: t(context, AppStrings.values.delete),
      ),
    ],
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case _FileAction.download:
      final targetDir = await getDirectoryPath();
      if (!context.mounted || targetDir == null) return;
      unawaited(appState.downloadFiles(session, [node.path], targetDir));
      break;
    case _FileAction.rename:
      final newName = await showInputDialog(
        context,
        title: t(context, AppStrings.values.rename),
        initialValue: node.name,
        confirmText: t(context, AppStrings.values.save),
        cancelText: t(context, AppStrings.values.cancel),
        validator: (v) => v == null || v.trim().isEmpty ? '' : null,
      );
      if (!context.mounted || newName == null || newName.trim().isEmpty) return;
      unawaited(appState.renameEntry(session, node.path, newName.trim()));
      break;
    case _FileAction.delete:
      final confirm = await _confirmDialog(
        context,
        t(context, AppStrings.values.deleteVar, params: {'name': node.name}),
      );
      if (!context.mounted) return;
      if (confirm) {
        unawaited(appState.deleteEntry(session, node));
      }
      break;
  }
}

