import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../chat_wallpaper.dart';
import '../theme.dart';

class WallpaperPickerScreen extends StatefulWidget {
  const WallpaperPickerScreen({super.key});

  @override
  State<WallpaperPickerScreen> createState() => _WallpaperPickerScreenState();
}

class _WallpaperPickerScreenState extends State<WallpaperPickerScreen> {
  String _selectedType = ChatWallpaper.type;
  String _selectedValue = ChatWallpaper.value;

  Future<void> _pickGallery() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 30,
      maxWidth: 800,
      maxHeight: 1400,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > 300 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fotoğraf çok büyük (max 300KB)')),
        );
      }
      return;
    }
    final b64 = base64Encode(bytes);
    await ChatWallpaper.saveWallpaper('image', b64);
    setState(() {
      _selectedType = 'image';
      _selectedValue = b64;
    });
  }

  Future<void> _selectNone() async {
    await ChatWallpaper.saveWallpaper('none', '');
    setState(() {
      _selectedType = 'none';
      _selectedValue = '';
    });
  }

  Future<void> _selectColor(Color color) async {
    final hex = color.value.toRadixString(16).padLeft(8, '0');
    await ChatWallpaper.saveWallpaper('color', hex);
    setState(() {
      _selectedType = 'color';
      _selectedValue = hex;
    });
  }

  Widget _buildPreview() {
    Widget content;
    if (_selectedType == 'color' && _selectedValue.isNotEmpty) {
      content = Container(color: Color(int.parse(_selectedValue, radix: 16)));
    } else if (_selectedType == 'image' && _selectedValue.isNotEmpty) {
      try {
        final bytes = base64Decode(_selectedValue);
        content = Image.memory(bytes, fit: BoxFit.cover, width: double.infinity, height: double.infinity);
      } catch (_) {
        content = Container(color: PhotonColors.bg);
      }
    } else {
      content = Container(color: PhotonColors.bg);
    }
    return Container(
      height: 200,
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PhotonColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(child: content),
          Center(
            child: Text(
              'Duvar Kağıdı Önizleme',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PhotonColors.bg,
      appBar: AppBar(
        title: const Text('Sohbet Duvar Kağıdı'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: PhotonColors.text),
          onPressed: () => Navigator.pop(context, true),
        ),
      ),
      body: ListView(
        children: [
          _buildPreview(),

          // Default option
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GestureDetector(
              onTap: _selectNone,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: PhotonColors.panel,
                  border: Border.all(
                    color: _selectedType == 'none' ? PhotonColors.accent : PhotonColors.line,
                    width: _selectedType == 'none' ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.block, color: PhotonColors.textDim, size: 20),
                    const SizedBox(width: 12),
                    Text('Varsayilan', style: TextStyle(color: PhotonColors.text, fontSize: 14)),
                    const Spacer(),
                    if (_selectedType == 'none')
                      Icon(Icons.check_circle, color: PhotonColors.accent, size: 20),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Color grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Renkler', style: TextStyle(color: PhotonColors.textDim, fontSize: 11, letterSpacing: 1.2)),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: ChatWallpaper.presetColors.length,
              itemBuilder: (context, index) {
                final color = ChatWallpaper.presetColors[index];
                final hex = color.value.toRadixString(16).padLeft(8, '0');
                final isSelected = _selectedType == 'color' && _selectedValue == hex;
                return GestureDetector(
                  onTap: () => _selectColor(color),
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(10),
                      border: isSelected ? Border.all(color: PhotonColors.accent, width: 3) : null,
                    ),
                    child: isSelected
                        ? Center(child: Icon(Icons.check, color: Colors.white, size: 20))
                        : null,
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 20),

          // Gallery option
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GestureDetector(
              onTap: _pickGallery,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: PhotonColors.panel,
                  border: Border.all(color: PhotonColors.line),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.photo_library, color: PhotonColors.accent, size: 20),
                    const SizedBox(width: 12),
                    Text('Galeriden Sec', style: TextStyle(color: PhotonColors.text, fontSize: 14)),
                    const Spacer(),
                    if (_selectedType == 'image')
                      Icon(Icons.check_circle, color: PhotonColors.accent, size: 20),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
