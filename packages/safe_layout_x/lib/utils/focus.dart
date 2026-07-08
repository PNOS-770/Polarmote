import 'package:flutter/widgets.dart';

void unfocusPrimary() {
  FocusManager.instance.primaryFocus?.unfocus();
}
