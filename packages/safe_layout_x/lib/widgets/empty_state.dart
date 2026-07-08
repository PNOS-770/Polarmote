import 'package:flutter/material.dart';

class EmptyStatePanel extends StatelessWidget {
  const EmptyStatePanel({
    super.key,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(description, style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
