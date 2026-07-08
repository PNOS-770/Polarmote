import 'package:flutter/widgets.dart';

import '../../responsive/layout_breakpoints.dart';

class BannerPositioner {
  const BannerPositioner._();

  static const double topInset = 16;
  static const double rightInset = 16;
  static const double spacing = 12;
  static const double desktopWidth = 320;
  static const double mobileHorizontalPadding = 12;

  static double widthFor(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= LayoutBreakpoints.compactWidth) {
      return desktopWidth;
    }
    final mobileWidth = width - (mobileHorizontalPadding * 2);
    return mobileWidth.clamp(240.0, desktopWidth);
  }

  static EdgeInsets stackPadding(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final width = MediaQuery.sizeOf(context).width;
    if (width >= LayoutBreakpoints.compactWidth) {
      return EdgeInsets.only(top: top + topInset, right: rightInset);
    }
    return EdgeInsets.only(
      top: top + topInset,
      right: mobileHorizontalPadding,
      left: mobileHorizontalPadding,
    );
  }
}
