import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;

class ImageFileViewer extends StatelessWidget {
  const ImageFileViewer({required this.filePath, super.key});

  final String filePath;

  @override
  Widget build(BuildContext context) {
    final ext = p.extension(filePath).toLowerCase();
    final file = File(filePath);
    final image = ext == '.svg'
        ? SvgPicture.file(file, fit: BoxFit.contain)
        : Image.file(
            file,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Center(child: Text('Failed to load image: $error'));
            },
          );
    return Container(
      color: Colors.white,
      alignment: Alignment.center,
      child: InteractiveViewer(minScale: 0.5, maxScale: 8, child: image),
    );
  }
}
