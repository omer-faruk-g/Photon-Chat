import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Photon Chat tasarım sistemi
//
// Web sitesinin (site/index.html) koyu temasıyla aynı marka değerleri:
//   Ana renk  : sinyal yeşili   (KnkColors.accent)
//   Nötr      : yeşile çalan mürekkep / zemin (bg, panel, line, text)
//   Vurgu     : amber           (KnkColors.accent2)
//   Başlık    : Young Serif     (KnkFonts.display)
//   Gövde     : IBM Plex Sans   (KnkFonts.body)
//   Boşluk    : 8 tabanlı ölçek (Space.s1 … Space.s7)
// ---------------------------------------------------------------------------

class KnkColors {
  // Nötr: hepsi yeşile hafif çalar; saf gri yok.
  static const bg = Color(0xFF0B0E0F);
  static const panel = Color(0xFF11161A);
  static const panelAlt = Color(0xFF15201B);
  static const line = Color(0xFF23352D); // kenarlık: yeşilden türetilmiş
  static const text = Color(0xFFE7F3EF); // bg üzerinde 17:1
  static const textDim = Color(0xFF9DB3AC); // bg üzerinde 8.7:1

  // Ana renk: sinyal yeşili
  static const accent = Color(0xFF3DDC97); // bg üzerinde 11:1
  static const accentHover = Color(0xFF6BE8B1);
  static const accentWash = Color(0xFF102A20); // yeşilden türetilmiş zemin
  static const onAccent = Color(0xFF06251A); // yeşil üzerinde 9.2:1

  // Vurgu: amber (bölüm etiketleri, numaralar, bekleyen durumlar)
  static const accent2 = Color(0xFFF2A33D); // bg üzerinde 9.3:1

  // Semantik: hata / tehlike (marka renginden ayrı)
  static const danger = Color(0xFFF07167); // bg üzerinde 6.7:1
}

/// 8px tabanlı boşluk ölçeği: 8 / 16 / 24 / 32 / 48 / 64 / 96.
class Space {
  static const s1 = 8.0;
  static const s2 = 16.0;
  static const s3 = 24.0;
  static const s4 = 32.0;
  static const s5 = 48.0;
  static const s6 = 64.0;
  static const s7 = 96.0;
}

/// Türkçe kurallarına göre büyük harf: i → İ, ı → I ("Kişiler" → "KİŞİLER").
/// Dart'ın toUpperCase'i dil bilmez ve "KIŞILER" üretir.
String trUpper(String s) =>
    s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

/// Bileşen boyutları (boşluk değil): avatar ve ikon kutuları.
class KnkSize {
  static const tile = 40.0;
}

class KnkFonts {
  static const display = 'YoungSerif';
  static const body = 'IBMPlexSans';
}

/// Köşe yarıçapları: kartlar 6 (site ile aynı), baloncuklar 12, haplar tam yuvarlak.
class KnkRadius {
  static const card = 6.0;
  static const bubble = 12.0;
  static const pill = 999.0;
}

/// Tip ölçeği. h1 > h2 > h3 > gövde > küçük > etiket; ara boyut yok.
class KnkText {
  static const _tabular = [FontFeature.tabularFigures()];

  static const h1 = TextStyle(
      fontFamily: KnkFonts.display,
      fontSize: 34,
      height: 1.1,
      color: KnkColors.text);
  static const h2 = TextStyle(
      fontFamily: KnkFonts.display,
      fontSize: 26,
      height: 1.15,
      color: KnkColors.text);
  static const h3 = TextStyle(
      fontFamily: KnkFonts.display,
      fontSize: 19,
      height: 1.25,
      color: KnkColors.text);
  static const body = TextStyle(
      fontFamily: KnkFonts.body,
      fontSize: 15,
      height: 1.55,
      color: KnkColors.text);
  static const bodyDim = TextStyle(
      fontFamily: KnkFonts.body,
      fontSize: 15,
      height: 1.6,
      color: KnkColors.textDim);
  static const small = TextStyle(
      fontFamily: KnkFonts.body,
      fontSize: 13,
      height: 1.5,
      color: KnkColors.textDim);
  static const strong = TextStyle(
      fontFamily: KnkFonts.body,
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: KnkColors.text);
  static const meta = TextStyle(
      fontFamily: KnkFonts.body,
      fontSize: 11,
      height: 1.3,
      color: KnkColors.textDim);

  /// Bölüm etiketi (büyük harf, amber). Metni büyük harfle yazın.
  static const label = TextStyle(
      fontFamily: KnkFonts.body,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.3,
      color: KnkColors.accent2);

  /// Kodlar ve rakam grupları için eşit genişlikli rakamlar.
  static const code = TextStyle(
      fontFamily: KnkFonts.body,
      fontSize: 15,
      fontWeight: FontWeight.w600,
      letterSpacing: 2,
      color: KnkColors.accent,
      fontFeatures: _tabular);
  static const tabular = TextStyle(fontFeatures: _tabular);
}

/// Gölgeler marka renginden türetilir (gri değil).
List<BoxShadow> knkShadow({double strength = 1}) => [
      BoxShadow(
          color: KnkColors.accent.withOpacity(0.10 * strength),
          blurRadius: 24,
          offset: const Offset(0, 12),
          spreadRadius: -12),
    ];

// --- Bileşen stilleri (hover / basılı durumları tanımlı) ---

WidgetStateProperty<Color?> _overlay(Color c) =>
    WidgetStateProperty.resolveWith((s) {
      if (s.contains(WidgetState.pressed)) return c.withOpacity(0.16);
      if (s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)) {
        return c.withOpacity(0.08);
      }
      return null;
    });

ButtonStyle knkPrimaryButtonStyle() => ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) {
          return KnkColors.accent.withOpacity(0.30);
        }
        if (s.contains(WidgetState.hovered) || s.contains(WidgetState.pressed)) {
          return KnkColors.accentHover;
        }
        return KnkColors.accent;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.disabled)
              ? KnkColors.onAccent.withOpacity(0.6)
              : KnkColors.onAccent),
      overlayColor: WidgetStateProperty.all(Colors.transparent),
      elevation: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.hovered) ? 6 : 0),
      shadowColor: WidgetStateProperty.all(KnkColors.accent.withOpacity(0.5)),
      padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(vertical: Space.s2, horizontal: Space.s3)),
      shape: WidgetStateProperty.all(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KnkRadius.card))),
      textStyle: WidgetStateProperty.all(const TextStyle(
          fontFamily: KnkFonts.body,
          fontWeight: FontWeight.w600,
          fontSize: 15)),
      mouseCursor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.disabled)
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click),
    );

ButtonStyle knkGhostButtonStyle() => ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) {
          return KnkColors.textDim.withOpacity(0.5);
        }
        if (s.contains(WidgetState.hovered)) return KnkColors.accent;
        return KnkColors.text;
      }),
      backgroundColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.hovered)
              ? KnkColors.accentWash
              : Colors.transparent),
      side: WidgetStateProperty.resolveWith((s) => BorderSide(
          color: s.contains(WidgetState.hovered)
              ? KnkColors.accent
              : KnkColors.line)),
      overlayColor: _overlay(KnkColors.accent),
      padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(vertical: Space.s2, horizontal: Space.s3)),
      shape: WidgetStateProperty.all(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KnkRadius.card))),
      textStyle: WidgetStateProperty.all(const TextStyle(
          fontFamily: KnkFonts.body,
          fontWeight: FontWeight.w500,
          fontSize: 15)),
    );

ButtonStyle knkDangerButtonStyle() => ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) {
          return KnkColors.danger.withOpacity(0.3);
        }
        if (s.contains(WidgetState.hovered)) return const Color(0xFFF48A81);
        return KnkColors.danger;
      }),
      foregroundColor: WidgetStateProperty.all(const Color(0xFF2A0B08)),
      overlayColor: WidgetStateProperty.all(Colors.transparent),
      padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(vertical: Space.s2, horizontal: Space.s3)),
      shape: WidgetStateProperty.all(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KnkRadius.card))),
      textStyle: WidgetStateProperty.all(const TextStyle(
          fontFamily: KnkFonts.body,
          fontWeight: FontWeight.w600,
          fontSize: 15)),
    );

InputDecoration knkInputDecoration(String hint,
        {String? label, String? error, Widget? suffix}) =>
    InputDecoration(
      hintText: hint,
      labelText: label,
      errorText: error,
      errorMaxLines: 3,
      suffixIcon: suffix,
    );

final knkTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: KnkColors.bg,
  fontFamily: KnkFonts.body,
  colorScheme: const ColorScheme.dark(
    primary: KnkColors.accent,
    onPrimary: KnkColors.onAccent,
    secondary: KnkColors.accent2,
    error: KnkColors.danger,
    surface: KnkColors.panel,
    onSurface: KnkColors.text,
    outline: KnkColors.line,
  ),
  textTheme: const TextTheme(
    headlineLarge: KnkText.h1,
    headlineMedium: KnkText.h2,
    titleLarge: KnkText.h3,
    bodyLarge: KnkText.body,
    bodyMedium: KnkText.body,
    bodySmall: KnkText.small,
    labelSmall: KnkText.meta,
  ),
  hoverColor: KnkColors.accent.withOpacity(0.06),
  focusColor: KnkColors.accent.withOpacity(0.12),
  splashColor: KnkColors.accent.withOpacity(0.10),
  highlightColor: KnkColors.accent.withOpacity(0.06),
  dividerColor: KnkColors.line,
  appBarTheme: const AppBarTheme(
    backgroundColor: KnkColors.bg,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
    titleSpacing: Space.s1,
    iconTheme: IconThemeData(color: KnkColors.text),
    titleTextStyle: TextStyle(
        fontFamily: KnkFonts.display, fontSize: 19, color: KnkColors.text),
    shape: Border(bottom: BorderSide(color: KnkColors.line)),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(style: knkPrimaryButtonStyle()),
  outlinedButtonTheme: OutlinedButtonThemeData(style: knkGhostButtonStyle()),
  textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
    foregroundColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.hovered)
            ? KnkColors.accentHover
            : KnkColors.accent),
    overlayColor: _overlay(KnkColors.accent),
    textStyle: WidgetStateProperty.all(const TextStyle(
        fontFamily: KnkFonts.body, fontWeight: FontWeight.w600, fontSize: 15)),
    shape: WidgetStateProperty.all(RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KnkRadius.card))),
  )),
  iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
    foregroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.hovered) ? KnkColors.accent : null),
    overlayColor: _overlay(KnkColors.accent),
  )),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: KnkColors.panel,
    hoverColor: KnkColors.accentWash,
    contentPadding:
        const EdgeInsets.symmetric(horizontal: Space.s2, vertical: Space.s2),
    hintStyle: const TextStyle(color: KnkColors.textDim),
    labelStyle: const TextStyle(color: KnkColors.textDim),
    floatingLabelStyle: const TextStyle(color: KnkColors.accent),
    errorStyle: const TextStyle(color: KnkColors.danger),
    counterStyle: KnkText.meta,
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KnkRadius.card),
        borderSide: const BorderSide(color: KnkColors.line)),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KnkRadius.card),
        borderSide: const BorderSide(color: KnkColors.line)),
    disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KnkRadius.card),
        borderSide: BorderSide(color: KnkColors.line.withOpacity(0.6))),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KnkRadius.card),
        borderSide: const BorderSide(color: KnkColors.accent, width: 1.5)),
    errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KnkRadius.card),
        borderSide: const BorderSide(color: KnkColors.danger)),
    focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KnkRadius.card),
        borderSide: const BorderSide(color: KnkColors.danger, width: 1.5)),
  ),
  textSelectionTheme: TextSelectionThemeData(
    cursorColor: KnkColors.accent,
    selectionColor: KnkColors.accent.withOpacity(0.3),
    selectionHandleColor: KnkColors.accent,
  ),
  dialogTheme: DialogTheme(
    backgroundColor: KnkColors.panel,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KnkRadius.card),
        side: const BorderSide(color: KnkColors.line)),
    titleTextStyle: KnkText.h3,
    contentTextStyle: KnkText.bodyDim,
  ),
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: KnkColors.panel,
    surfaceTintColor: Colors.transparent,
    showDragHandle: true,
    dragHandleColor: KnkColors.line,
    constraints: BoxConstraints(maxWidth: 640),
    shape: RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(KnkRadius.bubble)),
      side: BorderSide(color: KnkColors.line),
    ),
  ),
  listTileTheme: const ListTileThemeData(
    iconColor: KnkColors.textDim,
    textColor: KnkColors.text,
    contentPadding: EdgeInsets.symmetric(horizontal: Space.s3),
  ),
  snackBarTheme: const SnackBarThemeData(
    backgroundColor: KnkColors.panelAlt,
    contentTextStyle: TextStyle(
        fontFamily: KnkFonts.body, color: KnkColors.text, fontSize: 13),
    behavior: SnackBarBehavior.floating,
  ),
  tooltipTheme: TooltipThemeData(
    decoration: BoxDecoration(
        color: KnkColors.panelAlt,
        border: Border.all(color: KnkColors.line),
        borderRadius: BorderRadius.circular(KnkRadius.card)),
    textStyle: const TextStyle(
        fontFamily: KnkFonts.body, color: KnkColors.text, fontSize: 13),
  ),
  progressIndicatorTheme:
      const ProgressIndicatorThemeData(color: KnkColors.accent),
  scrollbarTheme:
      ScrollbarThemeData(thumbColor: WidgetStateProperty.all(KnkColors.line)),
);

// ---------------------------------------------------------------------------
// Ortak bileşenler
// ---------------------------------------------------------------------------

/// Uygulama işareti: sitedeki logo ile aynı (yeşil kare içinde sinyal dalgaları).
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 32});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            color: KnkColors.accent,
            borderRadius: BorderRadius.circular(KnkRadius.card)),
        child: Icon(Icons.sensors, size: size * 0.6, color: KnkColors.onAccent),
      );
}

/// Bölüm etiketi: büyük harf, amber, aralıklı.
class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Space.s1),
        child: Row(children: [
          Expanded(child: Text(trUpper(text), style: KnkText.label)),
          if (trailing != null) trailing!,
        ]),
      );
}

/// Üzerine gelince kenarlığı yeşile dönen, marka renginden gölge alan kart.
/// Dokunulabilir satırlar (kişi, grup, ayar) için kullanılır.
class HoverCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  const HoverCard(
      {super.key,
      required this.child,
      this.onTap,
      this.onLongPress,
      this.onSecondaryTap,
      this.padding = const EdgeInsets.all(Space.s2),
      this.color,
      this.borderColor});
  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null;
    final border = (_hover && interactive)
        ? KnkColors.accent
        : (widget.borderColor ?? KnkColors.line);
    return Semantics(
      button: interactive,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: widget.color ?? KnkColors.panel,
            borderRadius: BorderRadius.circular(KnkRadius.card),
            border: Border.all(color: border),
            boxShadow: (_hover && interactive) ? knkShadow() : const [],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(KnkRadius.card),
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
              onSecondaryTap: widget.onSecondaryTap,
              child: Padding(padding: widget.padding, child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bilgi / uyarı şeridi. tone: accent (bilgi), accent2 (bekleyen), danger (hata).
class NoticeBar extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color tone;
  final VoidCallback? onTap;
  const NoticeBar(
      {super.key,
      required this.icon,
      required this.text,
      this.tone = KnkColors.accent2,
      this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: tone.withOpacity(0.12),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: Space.s2, vertical: Space.s1),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: tone, size: 18),
              const SizedBox(width: Space.s1),
              Expanded(
                  child: Text(text,
                      style:
                          TextStyle(color: tone, fontSize: 13, height: 1.45))),
            ]),
          ),
        ),
      );
}

/// Geniş ekranlarda (web, masaüstü) içerik sütununu okunabilir genişlikte tutar.
class ContentWidth extends StatelessWidget {
  final Widget child;
  final double max;

  /// true: yükseklik içeriğe göre (alt şeritler gibi, dikeyde serbest alanlarda kullanılır).
  final bool shrinkHeight;
  const ContentWidth(
      {super.key,
      required this.child,
      this.max = 760,
      this.shrinkHeight = false});
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        heightFactor: shrinkHeight ? 1 : null,
        child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: max), child: child),
      );
}
