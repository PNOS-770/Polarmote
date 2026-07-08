import 'dock_panel.dart';

class PanelRegistry {
  PanelRegistry();

  final Map<String, DockPanel> _panels = <String, DockPanel>{};

  void register(DockPanel panel) {
    _panels[panel.id] = panel;
  }

  void registerAll(Iterable<DockPanel> panels) {
    for (final panel in panels) {
      register(panel);
    }
  }

  DockPanel? resolve(String id) {
    return _panels[id];
  }

  List<DockPanel> get all => _panels.values.toList(growable: false);
}
