import 'package:flutter/material.dart';
import '../knk_api.dart';
import '../theme.dart';
import '../widgets.dart';
import '../message_guard.dart';

class PulseAiScreen extends StatefulWidget {
  final String myServerUrl;
  const PulseAiScreen({super.key, required this.myServerUrl});

  @override
  State<PulseAiScreen> createState() => _PulseAiScreenState();
}

class _PulseAiScreenState extends State<PulseAiScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  // {role: 'user'|'assistant', content: String, error?: '1'}
  final List<Map<String, String>> _messages = [];
  bool _loading = false;
  String? _inputError;

  static const _maxHistory = 20;

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_loading) return;
    final raw = _ctrl.text;
    final error = validateMessage(raw);
    if (error != null) { setState(() => _inputError = error); return; }
    final text = sanitizeMessage(raw);
    setState(() {
      _inputError = null;
      _loading = true;
      _messages.add({'role': 'user', 'content': text});
    });
    _ctrl.clear();
    _scrollToBottom();

    // Hata mesajları sohbet geçmişine (AI'ye gönderilen bağlama) dahil edilmez.
    final history = _messages
        .where((m) => m['error'] == null)
        .map((m) => {'role': m['role']!, 'content': m['content']!})
        .toList();
    final trimmed = history.length > _maxHistory ? history.sublist(history.length - _maxHistory) : history;

    final (reply, err) = await KnkApi.chatWithPulseAI(widget.myServerUrl, trimmed);
    if (!mounted) return;

    setState(() {
      if (reply != null) {
        _messages.add({'role': 'assistant', 'content': reply});
      } else {
        _messages.add({'role': 'assistant', 'content': err ?? 'Bir hata oluştu.', 'error': '1'});
      }
      _loading = false;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  static const _starters = [
    '"Mütevazı" ne demek?',
    'Uçtan uca şifreleme nasıl çalışır?',
    'Bana kısa bir kitap öner.',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.bolt_outlined, color: KnkColors.accent),
          SizedBox(width: Space.s1),
          Text('Pulse AI'),
        ]),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(Space.s3, Space.s5, Space.s3, Space.s3),
                    child: ContentWidth(
                      max: 560,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const SectionLabel('Asistan'),
                        const SizedBox(height: Space.s1),
                        const Text('Sor, Pulse kısa ve net cevaplasın.', style: KnkText.h1),
                        const SizedBox(height: Space.s3),
                        const Text(
                          'Pulse AI senin sunucun üzerinden çalışır. Sorduklarını arkadaşların görmez; konuşma bu ekranı kapatınca silinir.',
                          style: KnkText.bodyDim,
                        ),
                        const SizedBox(height: Space.s4),
                        Wrap(spacing: Space.s1, runSpacing: Space.s1, children: [
                          for (final s in _starters)
                            ActionChip(
                              label: Text(s),
                              avatar: const Icon(Icons.north_east, size: 16, color: KnkColors.accent),
                              backgroundColor: KnkColors.panel,
                              side: const BorderSide(color: KnkColors.line),
                              labelStyle: KnkText.small.copyWith(color: KnkColors.text),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KnkRadius.card)),
                              onPressed: () {
                                _ctrl.text = s;
                                _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
                              },
                            ),
                        ]),
                      ]),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: Space.s2),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final m = _messages[i];
                      final isUser = m['role'] == 'user';
                      final isError = m['error'] != null;
                      final maxW = (MediaQuery.sizeOf(context).width * 0.82).clamp(0.0, 560.0);
                      return ContentWidth(child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Space.s2),
                        child: Align(
                          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: Space.s1),
                            padding: const EdgeInsets.fromLTRB(Space.s2, Space.s1, Space.s2, Space.s1),
                            constraints: BoxConstraints(maxWidth: maxW),
                            decoration: BoxDecoration(
                              color: isUser ? KnkColors.accent : KnkColors.panel,
                              border: isUser ? null : Border.all(color: isError ? KnkColors.danger.withOpacity(0.6) : KnkColors.line),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(KnkRadius.bubble),
                                topRight: const Radius.circular(KnkRadius.bubble),
                                bottomLeft: Radius.circular(isUser ? KnkRadius.bubble : 2),
                                bottomRight: Radius.circular(isUser ? 2 : KnkRadius.bubble),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!isUser)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: Space.s1),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      Icon(isError ? Icons.error_outline : Icons.bolt_outlined, size: 14, color: isError ? KnkColors.danger : KnkColors.accent2),
                                      const SizedBox(width: Space.s1),
                                      Text(isError ? 'Ulaşılamadı' : 'Pulse AI', style: TextStyle(color: isError ? KnkColors.danger : KnkColors.accent2, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                                    ]),
                                  ),
                                SelectableText(
                                  m['content'] ?? '',
                                  style: TextStyle(
                                    color: isUser ? KnkColors.onAccent : (isError ? KnkColors.danger : KnkColors.text),
                                    fontSize: 15,
                                    height: 1.55,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ));
                    },
                  ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: Space.s1),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                SizedBox(width: Space.s2, height: Space.s2, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: Space.s1),
                Text('Pulse AI yazıyor…', style: KnkText.small),
              ]),
            ),
          if (_inputError != null) NoticeBar(icon: Icons.error_outline, text: _inputError!, tone: KnkColors.danger),
          MessageComposer(
            controller: _ctrl,
            enabled: true,
            sending: _loading,
            hint: 'Pulse AI’a bir şey sor',
            onChanged: (_) { if (_inputError != null) setState(() => _inputError = null); },
            onSend: () { if (!_loading) _send(); },
          ),
        ],
      ),
    );
  }
}
