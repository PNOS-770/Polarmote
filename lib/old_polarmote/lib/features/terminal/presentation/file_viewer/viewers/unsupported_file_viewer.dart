import 'package:flutter/material.dart';

class UnsupportedFileViewer extends StatelessWidget {
  const UnsupportedFileViewer({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Unsupported internal viewer type.'));
  }
}
