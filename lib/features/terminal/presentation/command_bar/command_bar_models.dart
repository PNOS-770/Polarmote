import 'package:flutter/material.dart';

/// 命令栏项（单个命令）
class CommandBarItem {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final String? shortcut;
  final bool enabled;

  const CommandBarItem({
    required this.label,
    required this.icon,
    required this.onTap,
    this.shortcut,
    this.enabled = true,
  });
}

/// 命令栏分组（一个 Tab）
class CommandBarSection {
  final String id;
  final String title;
  final IconData icon;
  final List<CommandBarItem> items;

  const CommandBarSection({
    required this.id,
    required this.title,
    required this.icon,
    required this.items,
  });
}

