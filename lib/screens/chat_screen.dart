import 'package:flutter/material.dart';
import '../fip.dart';
import '../knk_api.dart';
import '../local_store.dart';
import '../obfuscate.dart';
import '../theme.dart';
import '../profanity_filter.dart';
import '../message_guard.dart';

class ChatScreen extends StatefulWidget {
  final FipBlock identity;
  final Contact contact;
  final String myServerUrl;

  const ChatScreen({super.key, required this.identity, required this.contact, required this.myServerUrl});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _draftCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<ChatMessage> _messages = [];
  late final String _chatKey;
  bool _alive = true;
  bool _contactActive = true;
  String? _inputError;

  @override
  void initState() {
    super.initState();
    _chatKey = chatKeyFor(widget.identity.fipId, widget.contact.fipId);
    _poll();
    _pollContactStatus();
  }

  @override
  void dispose() {
    _alive = false;
    _draftCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _poll() async {
    while (_alive) {
      final raw = await KnkApi.getMessages(_chatKey, receiverServerUrl: widget.myServerUrl);
      final msgs = raw
          .map((m) => ChatMessage(
                from: m['from'] as String,
                text: deobfuscate(m['text'] as String),
                ts: m['ts'] as int,
              ))
          .toList();
      if (_alive && mounted) {
        setState(() => _messages = msgs);
        _scrollToBottom();
      }
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  Future<void> _pollContactStatus() async {
    while (_alive) {
      final active = await KnkApi.isActive(widget.contact.serverUrl, widget.contact.fipId);
      if (_alive && mounted && active != _contactActive) {
        setState(() => _contactActive = active);
      }
      await Future.delayed(const Duration(seconds: 5));
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final raw = _draftCtrl.text;
    final error = validateMessage(raw);
    if (error != null) {
      setState(() => _inputError = error);
      return;
    }
    final text = sanitizeMessage(raw);
    setState(() => _inputError = null);

    if (!_contactActive) {
      final active = await KnkApi.isActive(widget.contact.serverUrl, widget.contact.fipId);
      if (!active) {
        if (mounted) { setState(() => _contactActive = false); _showDeactivatedDialog(); }
        return;
      }
      setState(() => _contactActive = true);
    }

    final ts = DateTime.now().millisecondsSinceEpoch;
    await KnkApi.sendMessage(receiverServerUrl: widget.contact.serverUrl, chatKey: _chatKey, from: widget.identity.fipId, text: obfuscate(text), ts: ts);
    await KnkApi.sendMessage(receiverServerUrl: widget.myServerUrl, chatKey: _chatKey, from: widget.identity.fipId, text: obfuscate(text), ts: ts);
    setState(() {
      _messages.add(ChatMessage(from: widget.identity.fipId, text: text, ts: ts));
      _draftCtrl.clear();
    });
    _scrollToBottom();
  }

  void _showDeactivatedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: KnkColors.panel,
        title: const Text('Kişi artık aktif değil', style: TextStyle(color: KnkColors.text, fontSize: 15)),
        content: const Text('Bu kişi hesabını bu cihazdan kaldırdı. Mesajın iletilemeyecek.', style: TextStyle(color: KnkColors.textDim, fontSize: 13, height: 1.6)),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tamam', style: TextStyle(color: KnkColors.accent)))],
      ),
    );
  }

  String _formatTime(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.contact.name)),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: KnkColors.line))),
            child: Row(children: [
              Container(width: 7, height: 7, decoration: const BoxDecoration(color: KnkColors.accent, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('FIP eşleşmesi · ${widget.contact.code}', style: const TextStyle(color: KnkColors.textDim, fontSize: 10, letterSpacing: 1)),
            ]),
          ),
          if (!_contactActive)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: KnkColors.danger.withOpacity(0.12),
              child: Row(children: [
                const Icon(Icons.info_outline, color: KnkColors.danger, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text('${widget.contact.name} hesabını kaldırdı. Artık aktif değil.', style: const TextStyle(color: KnkColors.danger, fontSize: 11.5, height: 1.4))),
              ]),
            ),
          Expanded(
            child: _messages.isEmpty
                ? const Center(child: Padding(padding: EdgeInsets.symmetric(horizontal: 40), child: Text('Bu sohbet temiz. İlk mesajı sen gönder.', textAlign: TextAlign.center, style: TextStyle(color: KnkColors.textDim, fontSize: 12, height: 1.6))))
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(14),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) {
                      final m = _messages[i];
                      final mine = m.from == widget.identity.fipId;
                      final displayText = filterProfanity(m.text);
                      return Align(
                        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                          decoration: BoxDecoration(
                            color: mine ? KnkColors.accent : KnkColors.panel,
                            border: mine ? null : Border.all(color: KnkColors.line),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(12), topRight: const Radius.circular(12),
                              bottomLeft: Radius.circular(mine ? 12 : 2), bottomRight: Radius.circular(mine ? 2 : 12),
                            ),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text(displayText, style: TextStyle(color: mine ? const Color(0xFF06251A) : KnkColors.text, fontSize: 13.5, height: 1.45)),
                            Text(_formatTime(m.ts), style: TextStyle(color: (mine ? const Color(0xFF06251A) : KnkColors.text).withOpacity(0.6), fontSize: 9.5)),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
          if (_inputError != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: KnkColors.danger.withOpacity(0.1),
              child: Text(_inputError!, style: const TextStyle(color: KnkColors.danger, fontSize: 12)),
            ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(color: KnkColors.panel, border: Border(top: BorderSide(color: KnkColors.line))),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _draftCtrl,
                  style: const TextStyle(color: KnkColors.text, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: _contactActive ? 'Mesaj yaz…' : 'Kişi artık aktif değil…',
                    hintStyle: const TextStyle(color: Color(0xFF5C6E6B)),
                    filled: true, fillColor: KnkColors.bg,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: const BorderSide(color: KnkColors.line)),
                  ),
                  onChanged: (_) { if (_inputError != null) setState(() => _inputError = null); },
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _send,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 40, height: 40, alignment: Alignment.center,
                  decoration: BoxDecoration(color: _contactActive ? KnkColors.accent : KnkColors.line, shape: BoxShape.circle),
                  child: Icon(Icons.arrow_upward, color: _contactActive ? const Color(0xFF06251A) : KnkColors.textDim),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
