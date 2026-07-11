import 'package:flutter/widgets.dart';

abstract class DockPanel {
  String get id;
  String get title;
  IconData? get icon;

  Widget buildPanel(BuildContext context);
}
