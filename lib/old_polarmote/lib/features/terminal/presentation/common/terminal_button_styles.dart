import 'package:flutter/material.dart';

class TerminalButtonStyles {
  static const Color textPrimary = Color(0xFF1F1F1F);
  static const Color textSecondary = Color(0xFF4F4F4F);
  static const Color borderLight = Color(0xFFD6D9DE);
  static const Color borderHover = Color(0xFFC5CAD2);
  static const Color fillPrimary = Color(0xFF2F3338);
  static const Color fillPrimaryHover = Color(0xFF262A2F);
  static const Color selectedBlueLight = Color(0xFFDCEAFF);
  static const Color surfaceBase = Color(0xFFFFFFFF);
  static const Color surfaceHover = Color(0xFFF2F4F7);
  static const Color surfacePressed = Color(0xFFE7EBF0);

  static ButtonStyle outlinedLikeQuickConnect({
    EdgeInsetsGeometry? padding,
    Size? minimumSize,
  }) {
    return ButtonStyle(
      foregroundColor: WidgetStateProperty.all(textPrimary),
      side: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused) ||
            states.contains(WidgetState.pressed)) {
          return const BorderSide(color: borderHover, width: 1.0);
        }
        return const BorderSide(color: borderLight, width: 1.0);
      }),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return surfacePressed;
        }
        if (states.contains(WidgetState.hovered)) {
          return surfaceHover;
        }
        return surfaceBase;
      }),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return const Color(0x26000000);
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return const Color(0x16000000);
        }
        return null;
      }),
      elevation: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) return 0;
        if (states.contains(WidgetState.hovered)) return 1;
        return 0;
      }),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      padding: WidgetStateProperty.all(
        padding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      minimumSize: WidgetStateProperty.all(minimumSize),
    );
  }

  static ThemeData apply(ThemeData base) {
    final shared = outlinedLikeQuickConnect();
    return base.copyWith(
      outlinedButtonTheme: OutlinedButtonThemeData(style: shared),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.all(Colors.white),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed) ||
                states.contains(WidgetState.focused)) {
              return fillPrimaryHover;
            }
            if (states.contains(WidgetState.hovered)) {
              return const Color(0xFF3A3F45);
            }
            return fillPrimary;
          }),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return const Color(0x33FFFFFF);
            }
            if (states.contains(WidgetState.hovered)) {
              return const Color(0x1FFFFFFF);
            }
            return null;
          }),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          minimumSize: WidgetStateProperty.all(const Size(72, 40)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return const Color(0xFFA3A8B1);
            }
            return textSecondary;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return surfacePressed;
            }
            if (states.contains(WidgetState.hovered)) {
              return surfaceHover;
            }
            return null;
          }),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return const Color(0x26000000);
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return const Color(0x16000000);
            }
            return null;
          }),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return const Color(0xFFA3A8B1);
            }
            return textSecondary;
          }),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused) ||
                states.contains(WidgetState.pressed)) {
              return const BorderSide(color: borderHover, width: 1.0);
            }
            return const BorderSide(color: borderLight, width: 1.0);
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return surfacePressed;
            }
            if (states.contains(WidgetState.hovered)) {
              return surfaceHover;
            }
            return surfaceBase;
          }),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return const Color(0x26000000);
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return const Color(0x18000000);
            }
            return null;
          }),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: const Color(0xFFFCFDFE),
        selectedColor: selectedBlueLight,
        secondarySelectedColor: selectedBlueLight,
        disabledColor: const Color(0xFFF5F6F8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: const BorderSide(color: borderLight, width: 1.0),
        labelStyle: const TextStyle(color: textSecondary),
        secondaryLabelStyle: const TextStyle(color: textPrimary),
        pressElevation: 1.5,
        elevation: 0,
        showCheckmark: false,
      ),
    );
  }
}
