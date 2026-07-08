import 'package:flutter/foundation.dart';

import '../features/terminal/models/script_entry.dart';
import '../features/terminal/models/script_folder_entry.dart';
import '../features/terminal/models/script_workflow_entry.dart';
import '../features/terminal/state/terminal_app_state.dart';

class ScriptProvider extends ChangeNotifier {
  final TerminalAppState _appState;

  ScriptProvider({required TerminalAppState appState})
    : _appState = appState;

  List<ScriptEntry> get scripts => _appState.scripts;
  List<ScriptFolderEntry> get folders => _appState.scriptFolders;
  List<ScriptWorkflowEntry> get workflows => _appState.scriptWorkflows;

  void addScriptEntry({
    required String name,
    required List<String> commands,
    String folderId = '',
  }) {
    _appState.addScriptEntry(name: name, commands: commands, folderId: folderId);
    notifyListeners();
  }

  void updateScriptEntry(String id, {required String name, required List<String> commands}) {
    _appState.updateScriptEntry(id, name: name, commands: commands);
    notifyListeners();
  }

  void removeScriptEntry(String id) {
    _appState.removeScriptEntry(id);
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
  }
}

