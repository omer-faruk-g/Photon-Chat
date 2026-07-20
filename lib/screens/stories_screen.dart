import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../fip.dart';
import '../local_store.dart';
import '../story_manager.dart';
import '../theme.dart';

class StoriesRow extends StatefulWidget {
  final FipBlock identity;
  final String displayName;
  final String myServerUrl;
  final List<Contact> contacts;
  const StoriesRow({super.key, required this.identity, required this.displayName, required this.myServerUrl, required this.contacts});
  @override
  State<StoriesRow> createState() => _StoriesRowState();
}

class _StoriesRowState extends State<StoriesRow> {
  List<StoryItem> _myStories = [];
  Map<String, List<StoryItem>> _contactStories = {};
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final my = await StoryManager.loadMyStories(widget.identity.fipId);
    final contactStories = <String, List<StoryItem>>{};
    for (final c in widget.contacts.where((c) => c.status == 'on')) {
      final stories = await StoryManager.loadContactStories(c.serverUrl, c.fipId);
      if (stories.isNotEmpty) contactStories[c.fipId] = stories;
    }
    if (mounted) setState(() { _myStories = my; _contactStories = contactStories; });
  }

  void _addStory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: PhotonColors.panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: Icon(Icons.text_fields, color: PhotonColors.accent),
          title: Text('Metin Hikaye', style: TextStyle(color: PhotonColors.text)),
          onTap: () { Navigator.pop(context); _addTextStory(); },
        ),
        ListTile(
          leading: Icon(Icons.image, color: PhotonColors.accent),
          title: Text('Görsel Hikaye', style: TextStyle(color: PhotonColors.text)),
          onTap: () { Navigator.pop(context); _addImageStory(); },
        ),
      ])),
    );
  }

  void _addTextStory() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PhotonColors.panel,
        title: Text('Metin Hikaye', style: TextStyle(color: PhotonColors.text, fontSize: 15)),
        content: TextField(
          controller: ctrl, autofocus: true, maxLines: 3, maxLength: 200,
          style: TextStyle(color: PhotonColors.text),
          decoration: InputDecoration(hintText: 'Hikayeni yaz...', hintStyle: TextStyle(color: PhotonColors.textDim), filled: true, fillColor: PhotonColors.bg, border: OutlineInputBorder(borderSide: BorderSide(color: PhotonColors.line))),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Iptal', style: TextStyle(color: PhotonColors.textDim))),
          ElevatedButton(
            style: photonPrimaryButtonStyle(),
            onPressed: () async {
              Navigator.pop(ctx);
              if (ctrl.text.trim().isEmpty) return;
              await StoryManager.postStory(serverUrl: widget.myServerUrl, fipId: widget.identity.fipId, authorName: widget.displayName, type: 'text', content: ctrl.text.trim());
              _load();
            },
            child: const Text('Paylas'),
          ),
        ],
      ),
    );
  }

  Future<void> _addImageStory() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 800);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (bytes.length > 3 * 1024 * 1024) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gorsel cok buyuk (maks 3 MB)')));
      return;
    }
    final b64 = base64Encode(bytes);
    await StoryManager.postStory(serverUrl: widget.myServerUrl, fipId: widget.identity.fipId, authorName: widget.displayName, type: 'image', content: b64);
    _load();
  }

  void _viewStories(List<StoryItem> stories, String name) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => _StoryViewerScreen(stories: stories, authorName: name)));
  }

  @override
  Widget build(BuildContext context) {
    final hasContactStories = _contactStories.isNotEmpty;
    if (_myStories.isEmpty && !hasContactStories) {
      return SizedBox(
        height: 90,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
          _storyCircle(label: 'Hikayeni Ekle', icon: Icons.add, onTap: _addStory),
        ]),
      );
    }
    return SizedBox(
      height: 90,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
        _storyCircle(
          label: 'Hikayem',
          icon: _myStories.isEmpty ? Icons.add : null,
          hasStory: _myStories.isNotEmpty,
          onTap: _myStories.isNotEmpty ? () => _viewStories(_myStories, widget.displayName) : _addStory,
          onLongPress: _addStory,
        ),
        ..._contactStories.entries.map((e) {
          final contact = widget.contacts.firstWhere((c) => c.fipId == e.key, orElse: () => Contact(fipId: e.key, name: '?', code: '', serverUrl: '', status: 'on'));
          return _storyCircle(label: contact.name, hasStory: true, onTap: () => _viewStories(e.value, contact.name));
        }),
      ]),
    );
  }

  Widget _storyCircle({required String label, IconData? icon, bool hasStory = false, VoidCallback? onTap, VoidCallback? onLongPress}) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: hasStory ? PhotonColors.accent : PhotonColors.line, width: hasStory ? 2.5 : 1.5),
              color: PhotonColors.panelAlt,
            ),
            child: icon != null ? Icon(icon, color: PhotonColors.accent, size: 24) : Center(child: Text(label.isNotEmpty ? label[0].toUpperCase() : '?', style: TextStyle(color: PhotonColors.accent, fontWeight: FontWeight.bold, fontSize: 20))),
          ),
          const SizedBox(height: 4),
          SizedBox(width: 64, child: Text(label, style: TextStyle(color: PhotonColors.textDim, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center)),
        ]),
      ),
    );
  }
}

class StoriesScreen extends StatelessWidget {
  final List<StoryItem> stories;
  final int initialIndex;
  const StoriesScreen({super.key, required this.stories, this.initialIndex = 0});
  @override
  Widget build(BuildContext context) {
    if (stories.isEmpty) return const Scaffold(body: Center(child: Text('Hikaye bulunamadi')));
    final startIdx = initialIndex.clamp(0, stories.length - 1);
    return _StoryViewerScreen(stories: stories, authorName: stories[startIdx].authorName, startIndex: startIdx);
  }
}

class _StoryViewerScreen extends StatefulWidget {
  final List<StoryItem> stories;
  final String authorName;
  final int startIndex;
  const _StoryViewerScreen({required this.stories, required this.authorName, this.startIndex = 0});
  @override
  State<_StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<_StoryViewerScreen> {
  late int _current = widget.startIndex.clamp(0, widget.stories.length - 1);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 5), _next);
  }

  void _next() {
    if (_current < widget.stories.length - 1) {
      setState(() => _current++);
      _startTimer();
    } else {
      Navigator.pop(context);
    }
  }

  void _prev() {
    if (_current > 0) {
      setState(() => _current--);
      _startTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.stories[_current];
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: (details) {
          if (details.globalPosition.dx < MediaQuery.of(context).size.width / 2) {
            _prev();
          } else {
            _next();
          }
        },
        child: SafeArea(child: Stack(children: [
          // Progress bars
          Positioned(top: 8, left: 16, right: 16, child: Row(
            children: List.generate(widget.stories.length, (i) => Expanded(
              child: Container(
                height: 3, margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: i <= _current ? PhotonColors.accent : Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            )),
          )),
          // Header
          Positioned(top: 28, left: 16, right: 16, child: Row(children: [
            Text(widget.authorName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(width: 8),
            Text(_formatAgo(story.ts), style: const TextStyle(color: Colors.white60, fontSize: 11)),
            const Spacer(),
            GestureDetector(onTap: () => Navigator.pop(context), child: const Icon(Icons.close, color: Colors.white, size: 24)),
          ])),
          // Content
          Center(child: story.type == 'text'
            ? Padding(padding: const EdgeInsets.all(32), child: Text(story.content, style: const TextStyle(color: Colors.white, fontSize: 22, height: 1.6), textAlign: TextAlign.center))
            : _buildImageStory(story.content)),
        ])),
      ),
    );
  }

  Widget _buildImageStory(String b64) {
    try {
      final bytes = base64Decode(b64);
      return Image.memory(bytes, fit: BoxFit.contain);
    } catch (_) {
      return const Text('Gorsel yuklenemedi', style: TextStyle(color: Colors.white60));
    }
  }

  String _formatAgo(int ts) {
    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ts));
    if (diff.inMinutes < 1) return 'az once';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk once';
    return '${diff.inHours} saat once';
  }
}
