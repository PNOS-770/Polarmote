import 'package:flutter/widgets.dart';

String localize(Locale locale, String zh, String en) {
  return locale.languageCode == 'en' ? en : zh;
}

String localizeFromContext(BuildContext context, String zh, String en) {
  return localize(Localizations.localeOf(context), zh, en);
}
