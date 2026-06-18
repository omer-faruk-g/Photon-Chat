import 'package:flutter/material.dart';

class KnkTheme extends ChangeNotifier {
  static final KnkTheme instance = KnkTheme._();
  KnkTheme._();
  bool _isDark = true;
  bool get isDark => _isDark;
  void setDark(bool v) { _isDark = v; notifyListeners(); }
  void toggle() { _isDark = !_isDark; notifyListeners(); }
}

class KnkColors {
  static bool get _d => KnkTheme.instance.isDark;
  static Color get bg => _d ? const Color(0xFF0B0E0F) : const Color(0xFFF0F4F2);
  static Color get panel => _d ? const Color(0xFF11161A) : const Color(0xFFFFFFFF);
  static Color get panelAlt => _d ? const Color(0xFF161D22) : const Color(0xFFE8EFED);
  static Color get line => _d ? const Color(0xFF222C32) : const Color(0xFFD0DBD8);
  static Color get text => _d ? const Color(0xFFE7F3EF) : const Color(0xFF1A2E28);
  static Color get textDim => _d ? const Color(0xFF7E9290) : const Color(0xFF607570);
  static Color get accent => const Color(0xFF3DDC97);
  static Color get accent2 => const Color(0xFFF2A33D);
  static Color get danger => const Color(0xFFE0594B);
}

ThemeData get knkTheme => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: KnkColors.bg,
  fontFamily: 'monospace',
  colorScheme: ColorScheme.dark(
    primary: KnkColors.accent,
    secondary: KnkColors.accent2,
    error: KnkColors.danger,
    surface: KnkColors.panel,
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: KnkColors.panel,
    elevation: 0,
    centerTitle: true,
    titleTextStyle: const TextStyle(color: Color(0xFFE7F3EF), fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 0.5),
  ),
);

ThemeData get knkLightTheme => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: KnkColors.bg,
  fontFamily: 'monospace',
  colorScheme: ColorScheme.light(
    primary: KnkColors.accent,
    secondary: KnkColors.accent2,
    error: KnkColors.danger,
    surface: KnkColors.panel,
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: KnkColors.panel,
    elevation: 0,
    centerTitle: true,
    titleTextStyle: TextStyle(color: KnkColors.text, fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 0.5),
  ),
);

InputDecoration knkInputDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: KnkColors.textDim),
    filled: true,
    fillColor: KnkColors.panel,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: KnkColors.line)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: KnkColors.line)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: KnkColors.accent)),
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
    side: BorderSide(color: KnkColors.line),
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
