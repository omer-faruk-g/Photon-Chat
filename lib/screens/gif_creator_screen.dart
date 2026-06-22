import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import '../nsfw_scanner.dart';
import '../profanity_filter.dart';
import '../theme.dart';

class GifCreatorScreen extends StatefulWidget {
  const GifCreatorScreen({super.key});

  @override
  State<GifCreatorScreen> createState() => _GifCreatorScreenState();
}

class _GifCreatorScreenState extends State<GifCreatorScreen> {
  final _picker = ImagePicker();
  final _captionCtrl = TextEditingController();
  final List<Uint8List> _frames = [];
  bool _scanning = false;
  bool _encoding = false;
  String? _error;

  @override
  void dispose() {
    _captionCtrl.dispose();
    super.dispose();
  }

  Future<void> _addFrame() async {
    if (_frames.length >= 8) {
      setState(() => _error = 'En fazla 8 kare eklenebilir');
      return;
    }
    final xfile = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (xfile == null) return;
    final bytes = await xfile.readAsBytes();

    setState(() { _scanning = true; _error = null; });
    final isNsfw = await NsfwScanner.hasImageViolation(bytes);
    setState(() => _scanning = false);

    if (isNsfw) {
      setState(() => _error = '⛔ Bu görsel uygunsuz içerik taşıyor — eklenemez.');
      return;
    }
    setState(() => _frames.add(bytes));
  }

  void _removeFrame(int index) {
    setState(() { _frames.removeAt(index); _error = null; });
  }

  Future<void> _createAndSend() async {
    if (_frames.isEmpty) {
      setState(() => _error = 'En az 1 kare gerekli');
      return;
    }

    final caption = _captionCtrl.text.trim();

    // Metin küfür kontrolü
    if (caption.isNotEmpty && NsfwScanner.hasTextViolation(caption)) {
      setState(() => _error = '⛔ Başlık uygunsuz içerik taşıyor — düzelt.');
      return;
    }

    setState(() { _encoding = true; _error = null; });

    try {
      // Kareleri yeniden tara (encoding öncesi son kontrol)
      final hasViolation = await NsfwScanner.hasAnyFrameViolation(_frames);
      if (hasViolation) {
        setState(() { _encoding = false; _error = '⛔ Uygunsuz içerik tespit edildi — GIF oluşturulmadı.'; });
        return;
      }

      final gifBytes = await _encodeGif(_frames);
      if (!mounted) return;
      setState(() => _encoding = false);
      Navigator.pop(context, GifResult(gifBytes: gifBytes, caption: caption));
    } catch (e) {
      setState(() { _encoding = false; _error = 'GIF oluşturulurken hata: $e'; });
    }
  }

  static Future<Uint8List> _encodeGif(List<Uint8List> frames) async {
    final animation = img.Image(width: 320, height: 320);
    for (final frameBytes in frames) {
      var frame = img.decodeImage(frameBytes);
      if (frame == null) continue;
      frame = img.copyResizeCropSquare(frame, size: 320);
      final gifFrame = img.Image(width: 320, height: 320, numChannels: 4);
      gifFrame.frames.add(frame);
      gifFrame.frameDuration = 500; // 0.5 saniye / kare
      animation.addFrame(gifFrame);
    }
    return Uint8List.fromList(img.encodeGif(animation));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GIF Oluştur'),
        actions: [
          if (_frames.isNotEmpty && !_encoding && !_scanning)
            TextButton(
              onPressed: _createAndSend,
              child: Text('Gönder', style: TextStyle(color: KnkColors.accent, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      backgroundColor: KnkColors.bg,
      body: Column(
        children: [
          // Hata mesajı
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: KnkColors.danger.withOpacity(0.12),
              child: Text(_error!, style: TextStyle(color: KnkColors.danger, fontSize: 13)),
            ),

          // Kare listesi
          Expanded(
            child: _frames.isEmpty
                ? Center(
                    child: Text('Galeriden fotoğraf ekle\n(en fazla 8 kare)',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: KnkColors.textDim, fontSize: 14, height: 1.7)),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemCount: _frames.length,
                    itemBuilder: (_, i) => Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(_frames[i], fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 4, right: 4,
                          child: GestureDetector(
                            onTap: () => _removeFrame(i),
                            child: Container(
                              width: 22, height: 22,
                              decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                              child: const Icon(Icons.close, color: Colors.white, size: 14),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 4, left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                            child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 11)),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),

          // Başlık alanı + butonlar
          Container(
            padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).viewInsets.bottom + 12),
            decoration: BoxDecoration(
              color: KnkColors.panel,
              border: Border(top: BorderSide(color: KnkColors.line)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _captionCtrl,
                  style: TextStyle(color: KnkColors.text, fontSize: 14),
                  maxLength: 100,
                  decoration: InputDecoration(
                    hintText: 'Başlık (isteğe bağlı)',
                    hintStyle: TextStyle(color: KnkColors.textDim),
                    counterText: '',
                    border: InputBorder.none,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: KnkColors.text,
                          side: BorderSide(color: KnkColors.line),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: (_scanning || _encoding) ? null : _addFrame,
                        icon: _scanning
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.add_photo_alternate_outlined, size: 18),
                        label: Text(_scanning ? 'Taranıyor…' : 'Kare Ekle'),
                      ),
                    ),
                    if (_frames.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: knkPrimaryButtonStyle(),
                          onPressed: (_encoding || _scanning) ? null : _createAndSend,
                          icon: _encoding
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                              : const Icon(Icons.gif_box_outlined, size: 18),
                          label: Text(_encoding ? 'Oluşturuluyor…' : 'GIF Gönder'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class GifResult {
  final Uint8List gifBytes;
  final String caption;
  const GifResult({required this.gifBytes, required this.caption});
}
