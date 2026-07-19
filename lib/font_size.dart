import 'package:flutter/foundation.dart';
import 'local_store.dart';

class FontSizeNotifier extends ChangeNotifier {
  static final FontSizeNotifier instance = FontSizeNotifier._();
  FontSizeNotifier._();

  String _size = 'orta';
  String get size => _size;

  double get msgFontSize => _size == 'kucuk' ? 12.0 : _size == 'buyuk' ? 16.0 : 13.5;

  Future<void> load() async {
    _size = await LocalStore.loadFontSize();
    notifyListeners();
  }

  Future<void> setSize(String s) async {
    if (_size == s) return;
    _size = s;
    await LocalStore.saveFontSize(s);
    notifyListeners();
  }
}
