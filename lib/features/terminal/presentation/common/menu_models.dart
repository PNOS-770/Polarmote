import 'package:flutter/material.dart';

class MenuCategory {
  final String id;
  final IconData icon;
  final String label;
  final List<MenuItem> items;

  const MenuCategory(this.id, this.icon, this.label, this.items);
}

class MenuItem {
  final String id;
  final IconData icon;
  final String label;
  final String? shortcut;

  const MenuItem(this.id, this.icon, this.label, {this.shortcut});
}

