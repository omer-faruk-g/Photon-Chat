import 'package:flutter/material.dart';
import '../knk_api.dart';
import '../theme.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Container(
            width: 28, height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: KnkColors.accent.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: KnkColors.accent.withOpacity(0.4)),
            ),
            child: const Text('⚡', style: TextStyle(fontSize: 14)),
          ),
          const SizedBox(width: 10),
          const Text('Pulse AI'),
        ]),
      ),
      backgroundColor: KnkColors.bg,
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 36),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 64, height: 64,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: KnkColors.accent.withOpacity(0.1),
                              shape: BoxShape.circle,
                              border: Border.all(color: KnkColors.accent.withOpacity(0.3)),
                            ),
                            child: const Text('⚡', style: TextStyle(fontSize: 30)),
                          ),
                          const SizedBox(height: 16),
                          const Text('Pulse AI', style: TextStyle(color: KnkColors.text, fontWeight: FontWeight.w700, fontSize: 18)),
                          const SizedBox(height: 8),
                          const Text(
                            'Kelime anlamı mı merak ediyorsun? Bir şey mi sormak istiyorsun? Sohbet etmek mi istiyorsun? Buradayım.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: KnkColors.textDim, fontSize: 13, height: 1.7),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final m = _messages[i];
                      final isUser = m['role'] == 'user';
                      final isError = m['error'] != null;
                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
                          decoration: BoxDecoration(
                            color: isUser ? KnkColors.accent : KnkColors.panel,
                            border: isUser ? null : Border.all(color: isError ? KnkColors.danger.withOpacity(0.5) : KnkColors.line),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(14),
                              topRight: const Radius.circular(14),
                              bottomLeft: Radius.circular(isUser ? 14 : 2),
                              bottomRight: Radius.circular(isUser ? 2 : 14),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!isUser)
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 4),
                                  child: Text('⚡ Pulse AI', style: TextStyle(color: KnkColors.accent, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                                ),
                              SelectableText(
                                m['content'] ?? '',
                                style: TextStyle(
                                  color: isUser ? const Color(0xFF06251A) : (isError ? KnkColors.danger : KnkColors.text),
                                  fontSize: 14,
                                  height: 1.55,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: KnkColors.accent)),
                SizedBox(width: 10),
                Text('Pulse AI yazıyor…', style: TextStyle(color: KnkColors.textDim, fontSize: 12)),
              ]),
            ),
          if (_inputError != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: KnkColors.danger.withOpacity(0.1),
              child: Text(_inputError!, style: const TextStyle(color: KnkColors.danger, fontSize: 12)),
            ),
          SafeArea(
            top: false,
            child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: const BoxDecoration(
              color: KnkColors.panel,
              border: Border(top: BorderSide(color: KnkColors.line)),
            ),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  style: const TextStyle(color: KnkColors.text, fontSize: 14),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'Pulse AI\'e bir şey sor…',
                    hintStyle: const TextStyle(color: KnkColors.textDim, fontSize: 13),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: KnkColors.line), borderRadius: BorderRadius.circular(999)),
                    focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: KnkColors.accent), borderRadius: BorderRadius.circular(999)),
                    disabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: KnkColors.line), borderRadius: BorderRadius.circular(999)),
                  ),
                  maxLines: 4, minLines: 1,
                  maxLength: maxMessageLength,
                  textInputAction: TextInputAction.send,
                  onChanged: (_) { if (_inputError != null) setState(() => _inputError = null); },
                  // Enter ile gönderdikten sonra odak kutuda kalsın; art arda mesaj yazılabilsin.
                  onEditingComplete: () {},
                  onSubmitted: (_) { if (!_loading) _send(); },
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _loading ? null : _send,
                child: Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: _loading ? KnkColors.line : KnkColors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.arrow_upward, color: _loading ? KnkColors.textDim : const Color(0xFF06251A), size: 20),
                ),
              ),
            ]),
          ),
          ),
        ],
      ),
    );
  }
}
