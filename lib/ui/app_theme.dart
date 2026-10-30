import 'package:flutter/material.dart';

import '../theme.dart';

ThemeData buildAppTheme() {
  final theme = CodenfastTheme();
  return ThemeData(
        useMaterial3: true,
        canvasColor: Colors.black,
        primarySwatch: theme.blackTransparent,
        textTheme: theme.textTheme(),
        primaryTextTheme: theme.textTheme(),
        colorScheme: theme.colorScheme(),
        iconTheme: theme.iconTheme(),
        inputDecorationTheme: theme.inputDecorationTheme(),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: Color(0xFF00E5FF),
          linearTrackColor: Color(0xFF252C3D),
        ),
        snackBarTheme: SnackBarThemeData(
          contentTextStyle: theme.textTheme().bodySmall,
          backgroundColor: Colors.black,
        ),
        dialogTheme: DialogThemeData(
          contentTextStyle: theme.textTheme().bodySmall,
          backgroundColor: const Color(0xFF1B1F2B),
          iconColor: Colors.white,
          titleTextStyle: theme.textTheme().titleSmall,
          elevation: 8,
          alignment: Alignment.center,
          actionsPadding: const EdgeInsets.all(20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0x2E00E5FF), width: 1),
          ),
        ),
        listTileTheme: const ListTileThemeData(
          textColor: Colors.white,
          iconColor: Colors.white,
          selectedColor: Color(0xFF00E5FF),
          subtitleTextStyle: TextStyle(fontSize: 12, color: Colors.white70),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? Colors.black : Colors.white,
            ),
            backgroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected)
                  ? const Color(0xFF00E5FF)
                  : const Color(0xFF1B1F2B),
            ),
            side: const WidgetStatePropertyAll(BorderSide(color: Color(0x5500E5FF))),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFF1B1F2B),
          selectedColor: const Color(0xFF00E5FF),
          disabledColor: const Color(0xFF1B1F2B),
          labelStyle: const TextStyle(color: Colors.white),
          secondaryLabelStyle: const TextStyle(color: Colors.black),
          checkmarkColor: Colors.black,
          side: const BorderSide(color: Color(0x5500E5FF)),
        ),
        focusColor: Colors.cyan,
        appBarTheme: AppBarTheme(
          backgroundColor: theme.cyanTransparent,
          foregroundColor: Colors.white,
          iconTheme: theme.iconTheme(),
          titleTextStyle: theme.textTheme().titleLarge,
          toolbarTextStyle: theme.textTheme().bodySmall,
          centerTitle: true,
        ),
      );
}
