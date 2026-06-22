import 'package:flutter/material.dart';

class PhotonTheme extends ChangeNotifier {
  static final PhotonTheme instance = PhotonTheme._();
  PhotonTheme._();
  bool _isDark = true;
  bool get isDark => _isDark;
  void setDark(bool v) { _isDark = v; notifyListeners(); }
  void toggle() { _isDark = !_isDark; notifyListeners(); }
}

class PhotonColors {
  static bool get _d => PhotonTheme.instance.isDark;
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

ThemeData get photonTheme => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: PhotonColors.bg,
  fontFamily: 'monospace',
  colorScheme: ColorScheme.dark(
    primary: PhotonColors.accent,
    secondary: PhotonColors.accent2,
    error: PhotonColors.danger,
    surface: PhotonColors.panel,
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: PhotonColors.panel,
    elevation: 0,
    centerTitle: true,
    titleTextStyle: const TextStyle(color: Color(0xFFE7F3EF), fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 0.5),
  ),
);

ThemeData get photonLightTheme => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: PhotonColors.bg,
  fontFamily: 'monospace',
  colorScheme: ColorScheme.light(
    primary: PhotonColors.accent,
    secondary: PhotonColors.accent2,
    error: PhotonColors.danger,
    surface: PhotonColors.panel,
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: PhotonColors.panel,
    elevation: 0,
    centerTitle: true,
    titleTextStyle: TextStyle(color: PhotonColors.text, fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 0.5),
  ),
);

InputDecoration photonInputDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: PhotonColors.textDim),
    filled: true,
    fillColor: PhotonColors.panel,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: PhotonColors.line)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: PhotonColors.line)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: PhotonColors.accent)),
  );
}

ButtonStyle photonPrimaryButtonStyle() {
  return ElevatedButton.styleFrom(
    backgroundColor: PhotonColors.accent,
    disabledBackgroundColor: PhotonColors.accent.withOpacity(0.35),
    foregroundColor: const Color(0xFF06251A),
    padding: const EdgeInsets.symmetric(vertical: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: 0.5),
  );
}

ButtonStyle photonGhostButtonStyle() {
  return OutlinedButton.styleFrom(
    foregroundColor: PhotonColors.textDim,
    side: BorderSide(color: PhotonColors.line),
    padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    textStyle: const TextStyle(fontSize: 13),
  );
}

ButtonStyle photonDangerButtonStyle() {
  return ElevatedButton.styleFrom(
    backgroundColor: PhotonColors.danger,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
  );
}
