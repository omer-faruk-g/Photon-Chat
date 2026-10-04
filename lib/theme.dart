import 'package:flutter/material.dart';
import 'i18n.dart';

class PhotonTheme extends ChangeNotifier {
  static final PhotonTheme instance = PhotonTheme._();
  PhotonTheme._();
  bool _isDark = true;
  bool get isDark => _isDark;
  void setDark(bool v) { _isDark = v; notifyListeners(); }
  void toggle() { _isDark = !_isDark; notifyListeners(); }
}

// ---------------------------------------------------------------------------
// Marka kimliği
//
// Ana renk: Photon yeşili — bir sinyalin "hat açık" ışığı. Nötr: mürekkep
// siyahına çalan yeşilimsi gri. Vurgu: kehribar — yalnızca etiket, uyarı ve
// rozetlerde, asla büyük yüzeylerde.
//
// Açık temada yeşil ve kehribar koyulaştırılır; beyaz zeminde metin olarak
// WCAG AA (4.5:1) sağlamaları için.
// ---------------------------------------------------------------------------
class PhotonColors {
  static bool get _d => PhotonTheme.instance.isDark;

  // Nötrler
  static Color get bg => _d ? const Color(0xFF0B0E0F) : const Color(0xFFF3F6F4);
  static Color get panel => _d ? const Color(0xFF11161A) : const Color(0xFFFFFFFF);
  static Color get panelAlt => _d ? const Color(0xFF15201B) : const Color(0xFFE8F0EB);
  static Color get line => _d ? const Color(0xFF23352D) : const Color(0xFFCCDAD2);
  static Color get text => _d ? const Color(0xFFE7F3EF) : const Color(0xFF10201A);
  static Color get textDim => _d ? const Color(0xFF9DB3AC) : const Color(0xFF4A5F57);

  // Ana renk
  static Color get accent => _d ? const Color(0xFF3DDC97) : const Color(0xFF0E7A4F);
  static Color get accentHover => _d ? const Color(0xFF6BE8B1) : const Color(0xFF0A6640);
  static Color get accentWash => _d ? const Color(0xFF102A20) : const Color(0xFFDDF3E8);
  static Color get onAccent => _d ? const Color(0xFF06251A) : const Color(0xFFFFFFFF);

  // Vurgu
  static Color get accent2 => _d ? const Color(0xFFF2A33D) : const Color(0xFF9A5600);
  static Color get danger => _d ? const Color(0xFFF07167) : const Color(0xFFB3261E);

  /// Gölgeler gri değil, markanın koyu yeşilinden türetilir.
  static Color get shadow => _d ? const Color(0xFF000000) : const Color(0xFF0E3A27);
}

/// 8px tabanlı boşluk ölçeği. Düzen boşlukları yalnızca bu değerlerden gelir.
class Space {
  static const double s1 = 8;
  static const double s2 = 16;
  static const double s3 = 24;
  static const double s4 = 32;
  static const double s5 = 48;
  static const double s6 = 64;
  static const double s7 = 96;
}

class PhotonRadius {
  static const double card = 8;
  static const double bubble = 16;
  static const double pill = 999;
}

class PhotonFonts {
  /// Karakterli başlık fontu.
  static const String display = 'YoungSerif';
  /// Okunaklı gövde fontu.
  static const String body = 'IBMPlexSans';
}

/// Tip ölçeği: 34 / 26 / 19 / 15 / 13 / 11. Başlıklar Young Serif, geri kalan
/// her şey IBM Plex Sans. Renkler temaya göre değiştiği için getter.
class PText {
  static TextStyle get display => TextStyle(fontFamily: PhotonFonts.display, fontSize: 34, height: 1.12, color: PhotonColors.text);
  static TextStyle get h1 => TextStyle(fontFamily: PhotonFonts.display, fontSize: 26, height: 1.18, color: PhotonColors.text);
  static TextStyle get h2 => TextStyle(fontFamily: PhotonFonts.display, fontSize: 19, height: 1.25, color: PhotonColors.text);
  static TextStyle get title => TextStyle(fontFamily: PhotonFonts.body, fontSize: 15, fontWeight: FontWeight.w600, height: 1.3, color: PhotonColors.text);
  static TextStyle get body => TextStyle(fontFamily: PhotonFonts.body, fontSize: 15, height: 1.45, color: PhotonColors.text);
  static TextStyle get bodyDim => TextStyle(fontFamily: PhotonFonts.body, fontSize: 15, height: 1.45, color: PhotonColors.textDim);
  static TextStyle get small => TextStyle(fontFamily: PhotonFonts.body, fontSize: 13, height: 1.4, color: PhotonColors.textDim);
  static TextStyle get meta => TextStyle(fontFamily: PhotonFonts.body, fontSize: 11, height: 1.3, color: PhotonColors.textDim);
  /// Bölüm etiketleri: küçük, aralıklı büyük harf, kehribar.
  static TextStyle get label => TextStyle(fontFamily: PhotonFonts.body, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2, color: PhotonColors.accent2);
  /// Kodlar ve sayılar hizalı dursun.
  static const TextStyle tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);
}

/// Dile duyarlı büyük harf. Türkçede i → İ, ı → I (Dart'ın toUpperCase'i bunu bilmez).
String trUpper(String s) => AppLang.instance.lang == 'tr' || AppLang.instance.lang == 'az'
    ? s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase()
    : s.toUpperCase();

List<BoxShadow> photonShadow({double strength = 1}) => [
  BoxShadow(
    color: PhotonColors.shadow.withOpacity((PhotonTheme.instance.isDark ? 0.45 : 0.12) * strength),
    blurRadius: 24, offset: const Offset(0, 8),
  ),
];

/// Fareyle üzerine gelince (masaüstü/web) kenarlık ana renge döner.
WidgetStateProperty<BorderSide?> _hoverSide(Color base) => WidgetStateProperty.resolveWith((s) {
  if (s.contains(WidgetState.disabled)) return BorderSide(color: PhotonColors.line);
  if (s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)) return BorderSide(color: PhotonColors.accent);
  return BorderSide(color: base);
});

ThemeData _build(bool dark) {
  final c = PhotonColors.accent;
  final scheme = (dark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
    primary: c,
    onPrimary: PhotonColors.onAccent,
    secondary: PhotonColors.accent2,
    error: PhotonColors.danger,
    surface: PhotonColors.panel,
    onSurface: PhotonColors.text,
    outline: PhotonColors.line,
    surfaceContainerHighest: PhotonColors.panelAlt,
  );
  final base = TextStyle(fontFamily: PhotonFonts.body, color: PhotonColors.text);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(PhotonRadius.card));
  return ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: PhotonColors.bg,
    fontFamily: PhotonFonts.body,
    colorScheme: scheme,
    dividerColor: PhotonColors.line,
    hoverColor: PhotonColors.accent.withOpacity(0.08),
    splashColor: PhotonColors.accent.withOpacity(0.12),
    highlightColor: PhotonColors.accent.withOpacity(0.06),
    focusColor: PhotonColors.accent.withOpacity(0.14),
    textTheme: TextTheme(
      displaySmall: PText.display,
      headlineMedium: PText.h1,
      headlineSmall: PText.h1,
      titleLarge: PText.h2,
      titleMedium: PText.title,
      titleSmall: PText.title.copyWith(fontSize: 13),
      bodyLarge: PText.body,
      bodyMedium: base.copyWith(fontSize: 15),
      bodySmall: PText.small,
      labelLarge: base.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
      labelMedium: base.copyWith(fontSize: 13),
      labelSmall: PText.meta,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: PhotonColors.bg,
      foregroundColor: PhotonColors.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      shape: Border(bottom: BorderSide(color: PhotonColors.line)),
      iconTheme: IconThemeData(color: PhotonColors.text, size: 24),
      titleTextStyle: PText.h2,
    ),
    iconTheme: IconThemeData(color: PhotonColors.textDim, size: 24),
    elevatedButtonTheme: ElevatedButtonThemeData(style: photonPrimaryButtonStyle()),
    filledButtonTheme: FilledButtonThemeData(style: photonPrimaryButtonStyle()),
    outlinedButtonTheme: OutlinedButtonThemeData(style: photonGhostButtonStyle()),
    textButtonTheme: TextButtonThemeData(style: ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.hovered) ? PhotonColors.accentHover : PhotonColors.accent),
      overlayColor: WidgetStatePropertyAll(PhotonColors.accent.withOpacity(0.08)),
      textStyle: WidgetStatePropertyAll(base.copyWith(fontSize: 15, fontWeight: FontWeight.w600)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: Space.s2, vertical: Space.s1)),
      shape: WidgetStatePropertyAll(shape),
    )),
    iconButtonTheme: IconButtonThemeData(style: ButtonStyle(
      overlayColor: WidgetStatePropertyAll(PhotonColors.accent.withOpacity(0.10)),
    )),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: PhotonColors.accent,
      foregroundColor: PhotonColors.onAccent,
      hoverColor: PhotonColors.accentHover,
      elevation: 0, hoverElevation: 0, focusElevation: 0, highlightElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Space.s2)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PhotonColors.panel,
      hintStyle: TextStyle(color: PhotonColors.textDim),
      labelStyle: TextStyle(color: PhotonColors.textDim),
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: Space.s2),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(PhotonRadius.card), borderSide: BorderSide(color: PhotonColors.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(PhotonRadius.card), borderSide: BorderSide(color: PhotonColors.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(PhotonRadius.card), borderSide: BorderSide(color: PhotonColors.accent, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(PhotonRadius.card), borderSide: BorderSide(color: PhotonColors.danger)),
    ),
    cardTheme: CardThemeData(
      color: PhotonColors.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PhotonRadius.card), side: BorderSide(color: PhotonColors.line)),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: PhotonColors.textDim,
      textColor: PhotonColors.text,
      titleTextStyle: PText.title,
      subtitleTextStyle: PText.small,
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.s2),
      minVerticalPadding: Space.s1,
      shape: shape,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: PhotonColors.panel,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: PText.h2,
      contentTextStyle: PText.bodyDim,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Space.s2), side: BorderSide(color: PhotonColors.line)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: PhotonColors.panel,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: PhotonColors.line,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Space.s2))),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: PhotonColors.panel,
      surfaceTintColor: Colors.transparent,
      textStyle: PText.body,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PhotonRadius.card), side: BorderSide(color: PhotonColors.line)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: PhotonColors.panelAlt,
      contentTextStyle: PText.body,
      actionTextColor: PhotonColors.accent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PhotonRadius.card), side: BorderSide(color: PhotonColors.line)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? PhotonColors.onAccent : PhotonColors.textDim),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? PhotonColors.accent : PhotonColors.panelAlt),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? PhotonColors.accent : PhotonColors.line),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? PhotonColors.accent : Colors.transparent),
      checkColor: WidgetStatePropertyAll(PhotonColors.onAccent),
      side: BorderSide(color: PhotonColors.textDim, width: 1.5),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? PhotonColors.accent : PhotonColors.textDim),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: PhotonColors.accent,
      inactiveTrackColor: PhotonColors.line,
      thumbColor: PhotonColors.accent,
      overlayColor: PhotonColors.accent.withOpacity(0.12),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: PhotonColors.panel,
      selectedColor: PhotonColors.accentWash,
      side: BorderSide(color: PhotonColors.line),
      labelStyle: base.copyWith(fontSize: 13),
      padding: const EdgeInsets.symmetric(horizontal: Space.s1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PhotonRadius.pill)),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: PhotonColors.accent,
      unselectedLabelColor: PhotonColors.textDim,
      indicatorColor: PhotonColors.accent,
      dividerColor: PhotonColors.line,
      labelStyle: base.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
      unselectedLabelStyle: base.copyWith(fontSize: 15),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: PhotonColors.accent, linearTrackColor: PhotonColors.line),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: PhotonColors.panelAlt, borderRadius: BorderRadius.circular(PhotonRadius.card), border: Border.all(color: PhotonColors.line)),
      textStyle: PText.small.copyWith(color: PhotonColors.text),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: PhotonColors.accent,
      selectionColor: PhotonColors.accent.withOpacity(0.3),
      selectionHandleColor: PhotonColors.accent,
    ),
  );
}

ThemeData get photonTheme => _build(true);
ThemeData get photonLightTheme => _build(false);

InputDecoration photonInputDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: PhotonColors.textDim),
    filled: true,
    fillColor: PhotonColors.panel,
    contentPadding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: Space.s2),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(PhotonRadius.card), borderSide: BorderSide(color: PhotonColors.line)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(PhotonRadius.card), borderSide: BorderSide(color: PhotonColors.line)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(PhotonRadius.card), borderSide: BorderSide(color: PhotonColors.accent, width: 1.5)),
  );
}

ButtonStyle photonPrimaryButtonStyle() {
  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((s) {
      if (s.contains(WidgetState.disabled)) return PhotonColors.accent.withOpacity(0.35);
      if (s.contains(WidgetState.hovered) || s.contains(WidgetState.pressed)) return PhotonColors.accentHover;
      return PhotonColors.accent;
    }),
    foregroundColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.disabled) ? PhotonColors.onAccent.withOpacity(0.6) : PhotonColors.onAccent),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(0),
    // Hover'da marka renginden türetilmiş hafif bir parıltı.
    shadowColor: WidgetStatePropertyAll(PhotonColors.accent.withOpacity(0.45)),
    minimumSize: const WidgetStatePropertyAll(Size(0, Space.s5)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: Space.s3, vertical: Space.s1)),
    shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(PhotonRadius.card))),
    textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: PhotonFonts.body, fontWeight: FontWeight.w600, fontSize: 15)),
  );
}

ButtonStyle photonGhostButtonStyle() {
  return ButtonStyle(
    foregroundColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.hovered) ? PhotonColors.accent : PhotonColors.text),
    backgroundColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.hovered) ? PhotonColors.accentWash : Colors.transparent),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    side: _hoverSide(PhotonColors.line),
    minimumSize: const WidgetStatePropertyAll(Size(0, Space.s5)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: Space.s2, vertical: Space.s1)),
    shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(PhotonRadius.card))),
    textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: PhotonFonts.body, fontWeight: FontWeight.w500, fontSize: 15)),
  );
}

ButtonStyle photonDangerButtonStyle() {
  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.hovered) ? Color.lerp(PhotonColors.danger, Colors.black, 0.15) : PhotonColors.danger),
    foregroundColor: const WidgetStatePropertyAll(Colors.white),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(0),
    minimumSize: const WidgetStatePropertyAll(Size(0, Space.s5)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: Space.s2, vertical: Space.s1)),
    shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(PhotonRadius.card))),
    textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: PhotonFonts.body, fontWeight: FontWeight.w600, fontSize: 15)),
  );
}

// ---------------------------------------------------------------------------
// Ortak parçalar
// ---------------------------------------------------------------------------

/// Uygulama işareti: yeşil karede sinyal simgesi.
class BrandMark extends StatelessWidget {
  final double size;
  BrandMark({super.key, this.size = 32});
  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(color: PhotonColors.accent, borderRadius: BorderRadius.circular(size / 4)),
    child: Icon(Icons.sensors_outlined, size: size * 0.6, color: PhotonColors.onAccent),
  );
}

/// Bölüm başlığı: küçük, aralıklı, kehribar büyük harf + isteğe bağlı sağ eylem.
class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  SectionLabel(this.text, {super.key, this.trailing,
      this.padding = const EdgeInsets.fromLTRB(Space.s2, Space.s3, Space.s2, Space.s1)});
  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(children: [
      Expanded(child: Text(trUpper(text), style: PText.label)),
      if (trailing != null) trailing!,
    ]),
  );
}

/// Dokunulabilir kart: hover'da kenarlık ana renge döner ve marka gölgesi alır.
class HoverCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  const HoverCard({super.key, required this.child, this.onTap,
      this.padding = const EdgeInsets.all(Space.s2), this.color, this.borderColor});
  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final active = _hover && widget.onTap != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          color: widget.color ?? PhotonColors.panel,
          borderRadius: BorderRadius.circular(PhotonRadius.card),
          border: Border.all(color: active ? PhotonColors.accent : (widget.borderColor ?? PhotonColors.line)),
          boxShadow: active ? photonShadow(strength: 0.6) : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(PhotonRadius.card),
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// Geniş ekranlarda (masaüstü/web) içeriği okunabilir bir sütunda tutar.
class ContentWidth extends StatelessWidget {
  final Widget child;
  final double max;
  const ContentWidth({super.key, required this.child, this.max = 760});
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(constraints: BoxConstraints(maxWidth: max), child: child),
  );
}
