import 'package:flutter/material.dart';

/// KNK renk paleti — koyu zemin, sinyal yeşili ve amber accent.
class KnkColors {
  static const bg = Color(0xFF0B0E0F);
  static const panel = Color(0xFF11161A);
  static const panelAlt = Color(0xFF161D22);
  static const line = Color(0xFF222C32);
  static const text = Color(0xFFE7F3EF);
  static const textDim = Color(0xFF7E9290);
  static const accent = Color(0xFF3DDC97);
  static const accent2 = Color(0xFFF2A33D);
  static const danger = Color(0xFFE0594B);
}

final knkTheme = ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: KnkColors.bg,
  fontFamily: 'monospace',
  colorScheme: ColorScheme.dark(
    primary: KnkColors.accent,
    secondary: KnkColors.accent2,
    error: KnkColors.danger,
    surface: KnkColors.panel,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: KnkColors.panel,
    elevation: 0,
    centerTitle: true,
    titleTextStyle: TextStyle(
      color: KnkColors.text,
      fontWeight: FontWeight.w700,
      fontSize: 15,
      letterSpacing: 0.5,
    ),
  ),
);

InputDecoration knkInputDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0xFF5C6E6B)),
    filled: true,
    fillColor: KnkColors.panel,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: KnkColors.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: KnkColors.line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: KnkColors.accent),
    ),
  );
}

ButtonStyle knkPrimaryButtonStyle() {
  return ElevatedButton.styleFrom(
    backgroundColor: KnkColors.accent,
    disabledBackgroundColor: KnkColors.accent.withOpacity(0.35),
    foregroundColor: const Color(0xFF06251A),
    padding: const EdgeInsets.symmetric(vertical: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: 0.5),
  );
}

ButtonStyle knkGhostButtonStyle() {
  return OutlinedButton.styleFrom(
    foregroundColor: KnkColors.textDim,
    side: const BorderSide(color: KnkColors.line),
    padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    textStyle: const TextStyle(fontSize: 13),
  );
}

ButtonStyle knkDangerButtonStyle() {
  return ElevatedButton.styleFrom(
    backgroundColor: KnkColors.danger,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
  );
}
