import 'package:flutter/material.dart';
import '../local_store.dart';
import '../theme.dart';

class StarredMessagesScreen extends StatefulWidget {
  const StarredMessagesScreen({super.key});
  @override
  State<StarredMessagesScreen> createState() => _StarredMessagesScreenState();
}

class _StarredMessagesScreenState extends State<StarredMessagesScreen> {
  List<Map<String, dynamic>> _starred = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    LocalStore.loadStarredMessages().then((msgs) { if (mounted) setState(() { _starred = msgs; _loading = false; }); });
  }

  String _formatTime(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yildizli Mesajlar')),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: PhotonColors.accent))
          : _starred.isEmpty
          ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Text('Yildizli mesajin yok.', style: TextStyle(color: PhotonColors.textDim, fontSize: 13))))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _starred.length,
              itemBuilder: (_, i) {
                final m = _starred[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: PhotonColors.panel, border: Border.all(color: PhotonColors.line), borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    Icon(Icons.star, color: Colors.amber, size: 20),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(m['text'] as String? ?? '', style: TextStyle(color: PhotonColors.text, fontSize: 13), maxLines: 3, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(_formatTime(m['ts'] as int? ?? 0), style: TextStyle(color: PhotonColors.textDim, fontSize: 10)),
                    ])),
                    GestureDetector(
                      onTap: () async {
                        await LocalStore.unstarMessage(m['msgId'] as String);
                        setState(() => _starred.removeAt(i));
                      },
                      child: Icon(Icons.close, color: PhotonColors.textDim, size: 18),
                    ),
                  ]),
                );
              },
            ),
    );
  }
}
