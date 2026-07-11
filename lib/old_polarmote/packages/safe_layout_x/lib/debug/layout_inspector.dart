import 'dart:convert';

import 'package:flutter/material.dart';

import '../dock/dock_tree.dart';

class LayoutInspector extends StatelessWidget {
  const LayoutInspector({
    super.key,
    required this.tree,
    this.padding = const EdgeInsets.all(8),
  });

  final DockTree tree;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final pretty = const JsonEncoder.withIndent('  ').convert(tree.toJson());
    return Container(
      color: const Color(0xFF111111),
      padding: padding,
      child: SingleChildScrollView(
        child: SelectableText(
          pretty,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFFE0E0E0),
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}
