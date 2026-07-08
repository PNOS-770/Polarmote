import 'package:flutter/material.dart';

import '../responsive/layout_breakpoints.dart';
import 'safe_desktop_pane_layout.dart';
import 'safe_desktop_shell.dart';
import 'safe_mobile_shell.dart';
import 'shell_models.dart';

typedef SafeAdaptiveBuilder = Widget Function(BuildContext context);

class SafeAdaptiveShell extends StatelessWidget {
  const SafeAdaptiveShell({
    super.key,
    required this.navItems,
    this.footerNavItems = const <ShellNavItem>[],
    required this.mobileTitle,
    this.mobileActions = const <Widget>[],
    required this.mobileDrawerBody,
    this.desktopSecondaryPane,
    this.desktopPane,
    this.desktopPaneConfig,
    this.desktopMain,
    required this.main,
    this.desktopRailStyle = const SafeDesktopRailStyle(),
    this.mobileStyle = const SafeMobileShellStyle(),
    this.desktopBackgroundColor = const Color(0xFFF6F6F6),
    this.desktopRailWidth = 60,
    this.onDesktopRailPointerDown,
    this.compactWidth = LayoutBreakpoints.compactWidth,
    this.mobileDrawerWidth,
  });

  final List<ShellNavItem> navItems;
  final List<ShellNavItem> footerNavItems;
  final String mobileTitle;
  final List<Widget> mobileActions;
  final Widget mobileDrawerBody;
  final Widget? desktopSecondaryPane;
  final Widget? desktopPane;
  final SafeDesktopPaneLayoutConfig? desktopPaneConfig;
  final Widget? desktopMain;
  final Widget main;
  final SafeDesktopRailStyle desktopRailStyle;
  final SafeMobileShellStyle mobileStyle;
  final Color desktopBackgroundColor;
  final double desktopRailWidth;
  final VoidCallback? onDesktopRailPointerDown;
  final double compactWidth;
  final double? mobileDrawerWidth;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < compactWidth) {
      return SafeMobileShell(
        title: mobileTitle,
        actions: mobileActions,
        navItems: [...navItems, ...footerNavItems],
        drawerBody: mobileDrawerBody,
        main: main,
        style: mobileStyle,
        drawerWidth: mobileDrawerWidth,
      );
    }
    final resolvedDesktopMain = desktopMain ?? main;
    final desktopBody = desktopPane != null
        ? SafeDesktopPaneLayout(
            pane: desktopPane!,
            main: resolvedDesktopMain,
            config: desktopPaneConfig ?? const SafeDesktopPaneLayoutConfig(),
          )
        : resolvedDesktopMain;
    return SafeDesktopShell(
      navItems: navItems,
      footerNavItems: footerNavItems,
      main: desktopBody,
      secondaryPane: desktopPane == null ? desktopSecondaryPane : null,
      backgroundColor: desktopBackgroundColor,
      railWidth: desktopRailWidth,
      onRailPointerDown: onDesktopRailPointerDown,
      railStyle: desktopRailStyle,
    );
  }
}
