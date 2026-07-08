import 'package:flutter/material.dart';

import '../../../../../shared/constants/app_string.dart';

class UnsupportedFileViewer extends StatelessWidget {
  const UnsupportedFileViewer({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context);
    final code = (locale?.languageCode ?? 'en').toLowerCase();
    return Center(
      child: Text(AppStrings.values.unsupportedViewerType.resolve(code)),
    );
  }
}

