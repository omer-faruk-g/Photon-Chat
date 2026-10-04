import 'package:flutter/material.dart';
import 'message_guard.dart';
import 'theme.dart';

/// Mesaj yazma alanı: birebir, grup ve Pulse AI ekranlarında ortak.
class MessageComposer extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final bool sending;
  final String hint;
  final ValueChanged<String>? onChanged;
  final VoidCallback onSend;
  const MessageComposer({super.key, required this.controller, required this.enabled, required this.sending, required this.hint, this.onChanged, required this.onSend});

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(color: KnkColors.panel, border: Border(top: BorderSide(color: KnkColors.line))),
    child: SafeArea(
      top: false,
      child: ContentWidth(
        child: Padding(
          padding: const EdgeInsets.all(Space.s2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                maxLength: maxMessageLength,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: hint,
                  fillColor: KnkColors.bg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: Space.s2),
                ),
                onChanged: onChanged,
                // Enter ile gönderdikten sonra odak kutuda kalsın; art arda mesaj yazılabilsin.
                onEditingComplete: () {},
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: Space.s1),
            IconButton.filled(
              tooltip: 'Gönder',
              onPressed: (!enabled || sending) ? null : onSend,
              style: IconButton.styleFrom(
                backgroundColor: KnkColors.accent,
                foregroundColor: KnkColors.onAccent,
                hoverColor: KnkColors.accentHover,
                disabledBackgroundColor: KnkColors.line,
                disabledForegroundColor: KnkColors.textDim,
                fixedSize: const Size.square(Space.s5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KnkRadius.card)),
              ),
              icon: sending
                  ? const SizedBox(width: Space.s2, height: Space.s2, child: CircularProgressIndicator(strokeWidth: 2, color: KnkColors.onAccent))
                  : const Icon(Icons.arrow_upward),
            ),
          ]),
        ),
      ),
    ),
  );
}

class CenterNote extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const CenterNote({super.key, required this.icon, required this.title, required this.body});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Space.s4),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: KnkColors.textDim, size: 32),
        const SizedBox(height: Space.s2),
        Text(title, style: KnkText.h3, textAlign: TextAlign.center),
        const SizedBox(height: Space.s1),
        Text(body, style: KnkText.small, textAlign: TextAlign.center),
      ]),
    ),
  );
}

