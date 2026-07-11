import 'package:flutter/material.dart';

import '../text/safe_text.dart';
import 'shell_models.dart';

class SafeMobileShell extends StatelessWidget {
  const SafeMobileShell({
    super.key,
    required this.title,
    required this.actions,
    required this.navItems,
    required this.drawerBody,
    required this.main,
    this.style = const SafeMobileShellStyle(),
    this.drawerWidth,
  });

  final String title;
  final List<Widget> actions;
  final List<ShellNavItem> navItems;
  final Widget drawerBody;
  final Widget main;
  final SafeMobileShellStyle style;
  final double? drawerWidth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: SafeText(title), actions: actions),
      drawer: Drawer(
        width: drawerWidth,
        child: SafeArea(
          child: Column(
            children: [
              for (final item in navItems)
                ListTile(
                  leading:
                      item.iconBuilder?.call(
                        context,
                        item.selected,
                        item.selected
                            ? style.selectedColor
                            : style.unselectedColor,
                        24,
                      ) ??
                      Icon(
                        item.icon,
                        color: item.selected
                            ? style.selectedColor
                            : style.unselectedColor,
                      ),
                  title: SafeText(item.label, maxLines: 1),
                  selected: item.selected,
                  onTap: item.onTap,
                ),
              if (style.showDivider) const Divider(),
              Expanded(child: drawerBody),
            ],
          ),
        ),
      ),
      body: main,
    );
  }
}
