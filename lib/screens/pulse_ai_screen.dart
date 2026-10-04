import 'package:flutter/material.dart';
import '../photon_api.dart';
import '../i18n.dart';
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
  // {role: 'user'|'assistant', content: String}
  final List<Map<String, String>> _messages = [];
  bool _loading = false;
  String? _inputError;

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final raw = _ctrl.text;
    final error = validateMessage(raw);
    if (error != null) { setState(() => _inputError = error); return; }
    final text = sanitizeMessage(raw);
    setState(() { _inputError = null; _loading = true; });
    _ctrl.clear();

    setState(() => _messages.add({'role': 'user', 'content': text}));
    _scrollToBottom();

    String reply;
    try {
      reply = await PhotonApi.chatWithPulseAI(widget.myServerUrl, List.from(_messages));
    } catch (e) {
      reply = '${AppLang.instance.t('error')}: $e';
    }
    if (!mounted) return;

    setState(() {
      _messages.add({'role': 'assistant', 'content': reply});
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
              color: PhotonColors.accent.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: PhotonColors.accent.withOpacity(0.4)),
            ),
            child: Icon(Icons.bolt_outlined, size: 16, color: PhotonColors.accent),
          ),
          const SizedBox(width: 8),
          Text(AppLang.instance.t('pulseAiTitle')),
        ]),
      ),
      backgroundColor: PhotonColors.bg,
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(Space.s3, Space.s6, Space.s3, Space.s3),
                    children: [
                      Container(
                        width: Space.s6, height: Space.s6,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: PhotonColors.accentWash,
                          borderRadius: BorderRadius.circular(PhotonRadius.card),
                          border: Border.all(color: PhotonColors.line),
                        ),
                        child: Icon(Icons.bolt_outlined, size: 32, color: PhotonColors.accent),
                      ),
                      const SizedBox(height: Space.s3),
                      Text(AppLang.instance.t('pulseAiTitle'), style: PText.display),
                      const SizedBox(height: Space.s2),
                      Text(AppLang.instance.t('pulseAiWelcome'), style: PText.bodyDim),
                    ],
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final m = _messages[i];
                      final isUser = m['role'] == 'user';
                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
                          decoration: BoxDecoration(
                            color: isUser ? PhotonColors.accent : PhotonColors.panel,
                            border: isUser ? null : Border.all(color: PhotonColors.line),
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
                                Padding(
                                  padding: EdgeInsets.only(bottom: 4),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(Icons.bolt_outlined, size: 13, color: PhotonColors.accent),
                                    const SizedBox(width: 4),
                                    Text('Pulse AI', style: TextStyle(color: PhotonColors.accent, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                                  ]),
                                ),
                              SelectableText(
                                m['content'] ?? '',
                                style: TextStyle(
                                  color: isUser ? PhotonColors.onAccent : PhotonColors.text,
                                  fontSize: 15,
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
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: PhotonColors.accent)),
                SizedBox(width: 8),
                Text(AppLang.instance.t('pulseAiTyping'), style: PText.small),
              ]),
            ),
          if (_inputError != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: PhotonColors.danger.withOpacity(0.1),
              child: Text(_inputError!, style: TextStyle(color: PhotonColors.danger, fontSize: 13)),
            ),
          Container(
            padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).viewInsets.bottom + 16),
            decoration: BoxDecoration(
              color: PhotonColors.panel,
              border: Border(top: BorderSide(color: PhotonColors.line)),
            ),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  enabled: !_loading,
                  style: TextStyle(color: PhotonColors.text, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: AppLang.instance.t('pulseAiHint'),
                    hintStyle: PText.small,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: PhotonColors.line), borderRadius: BorderRadius.circular(999)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: PhotonColors.accent), borderRadius: BorderRadius.circular(999)),
                    disabledBorder: OutlineInputBorder(borderSide: BorderSide(color: PhotonColors.line), borderRadius: BorderRadius.circular(999)),
                  ),
                  maxLines: 4, minLines: 1,
                  onChanged: (_) { if (_inputError != null) setState(() => _inputError = null); },
                  onSubmitted: (_) { if (!_loading) _send(); },
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _loading ? null : _send,
                child: Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: _loading ? PhotonColors.line : PhotonColors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.arrow_upward_outlined, color: _loading ? PhotonColors.textDim : PhotonColors.onAccent, size: 20),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
