import 'package:flutter/material.dart';
import 'theme.dart';
import 'vip.dart';

/// Rendering helpers for paid-tier decoration.
///
/// Every entry point tolerates a null [VipStatus]: tier data comes from the
/// bridge, which sleeps on the free plan, and a badge failing to load must never
/// take a message bubble down with it.

/// Colour for a display name. Null means "leave the caller's colour alone".
Color? vipNameColor(VipStatus? s) {
  final st = s ?? VipStatus.none;
  if (!st.effectiveTier.coloredName) return null;
  return st.color;
}

/// Colour for message body text. A step above [vipNameColor] — VIP paints the
/// name only, VIP+ also paints what they say.
Color? vipTextColor(VipStatus? s) {
  final st = s ?? VipStatus.none;
  if (!st.effectiveTier.coloredText) return null;
  return st.color;
}

/// The name to show for someone. Falls back to [realName] whenever an alias is
/// not in play, including when the bridge could not be reached.
///
/// The bridge already refuses to report an alias below photonPulseVip, so this
/// does not re-check the tier — trusting one gate keeps the two in step.
String vipDisplayName(VipStatus? s, String realName) {
  final st = s ?? VipStatus.none;
  if (st.fakeActive && st.fakeName.trim().isNotEmpty) return st.fakeName.trim();
  return realName;
}

const _boldOpen = '/k';
const _boldClose = '/t';

/// Splits [text] on the `/k` … `/t` markers into styled runs.
///
/// The markers are consumed, an unclosed `/k` runs to the end of the message,
/// and a message may contain several blocks. Below PVip the markers are left in
/// place as ordinary characters so the perk cannot be used without paying.
List<InlineSpan> vipMessageSpans(String text, VipStatus? s, TextStyle base) {
  final st = s ?? VipStatus.none;
  final tier = st.effectiveTier;
  final coloured = tier.coloredText && st.color != null
      ? base.copyWith(color: st.color)
      : base;

  if (!tier.boldMessages || !text.contains(_boldOpen)) {
    return [TextSpan(text: text, style: coloured)];
  }

  final spans = <InlineSpan>[];
  final buf = StringBuffer();
  var bold = false;
  var i = 0;

  void flush() {
    if (buf.isEmpty) return;
    spans.add(TextSpan(
      text: buf.toString(),
      style: bold ? coloured.copyWith(fontWeight: FontWeight.bold) : coloured,
    ));
    buf.clear();
  }

  while (i < text.length) {
    if (text.startsWith(_boldOpen, i)) {
      flush();
      bold = true;
      i += _boldOpen.length;
      continue;
    }
    if (text.startsWith(_boldClose, i)) {
      flush();
      bold = false;
      i += _boldClose.length;
      continue;
    }
    buf.write(text[i]);
    i++;
  }
  flush();
  return spans.isEmpty ? [TextSpan(text: '', style: coloured)] : spans;
}

/// Convenience wrapper so call sites read like the `Text` they replace.
Widget vipMessageText(
  String text,
  VipStatus? status, {
  required TextStyle style,
  TextAlign? textAlign,
}) =>
    Text.rich(
      TextSpan(children: vipMessageSpans(text, status, style)),
      textAlign: textAlign,
    );

/// PREMIUM marker for pvipPlus and above. Mirrors the existing MOD chip so the
/// two read as the same family of badge.
class VipBadge extends StatelessWidget {
  final VipStatus? status;
  final double fontSize;

  const VipBadge({super.key, required this.status, this.fontSize = 8});

  @override
  Widget build(BuildContext context) {
    final st = status ?? VipStatus.none;
    if (!st.effectiveTier.premiumTag) return const SizedBox.shrink();
    final c = st.color ?? PhotonColors.accent2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: c.withOpacity(0.15),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.workspace_premium, size: fontSize + 3, color: c),
        const SizedBox(width: 2),
        // Brand-style marker, kept untranslated like the MOD and FAKE chips.
        Text('PREMIUM',
            style: TextStyle(color: c, fontSize: fontSize, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
