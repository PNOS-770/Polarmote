import 'package:flutter/widgets.dart';

abstract class LayoutSafeWidget {
  Widget buildSafe(BuildContext context, BoxConstraints constraints);
}
