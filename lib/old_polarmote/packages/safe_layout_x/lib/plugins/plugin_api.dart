import '../panel/panel_registry.dart';

abstract class SafeLayoutPlugin {
  void registerPanels(PanelRegistry registry);
}
