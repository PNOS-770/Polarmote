import 'package:flutter/material.dart';

class AnsiSpan {
  const AnsiSpan(this.text, {this.color, this.bold = false, this.dim = false});

  final String text;
  final Color? color;
  final bool bold;
  final bool dim;
}

List<AnsiSpan> parseAnsi(String text) {
  final spans = <AnsiSpan>[];
  final buffer = StringBuffer();
  Color? currentColor;
  var bold = false;
  var dim = false;

  void flush() {
    if (buffer.isNotEmpty) {
      spans.add(AnsiSpan(buffer.toString(),
          color: currentColor, bold: bold, dim: dim));
      buffer.clear();
    }
  }

  for (var i = 0; i < text.length; i++) {
    if (text[i] == '\x1b' && i + 1 < text.length && text[i + 1] == '[') {
      flush();
      final end = text.indexOf('m', i + 2);
      if (end == -1) {
        buffer.write(text[i]);
        continue;
      }
      final codeStr = text.substring(i + 2, end);
      final codes = codeStr.split(';').map((s) => int.tryParse(s) ?? 0);
      for (final code in codes) {
        switch (code) {
          case 0:
            currentColor = null;
            bold = false;
            dim = false;
          case 1:
            bold = true;
          case 2:
            dim = true;
          case 30:
            currentColor = Colors.black;
          case 31:
            currentColor = Colors.red;
          case 32:
            currentColor = Colors.green;
          case 33:
            currentColor = Colors.amber;
          case 34:
            currentColor = Colors.blue;
          case 35:
            currentColor = Colors.purple;
          case 36:
            currentColor = Colors.cyan;
          case 37:
            currentColor = Colors.grey[300];
          case 90:
            currentColor = Colors.grey[600];
          case 91:
            currentColor = Colors.red[300];
          case 92:
            currentColor = Colors.green[300];
          case 93:
            currentColor = Colors.amber[200];
          case 94:
            currentColor = Colors.blue[300];
          case 95:
            currentColor = Colors.purple[200];
          case 96:
            currentColor = Colors.cyan[200];
          case 97:
            currentColor = Colors.white;
        }
      }
      i = end;
    } else {
      buffer.write(text[i]);
    }
  }
  flush();
  return spans;
}

