import 'package:flutter/foundation.dart';
import 'local_store.dart';

/// Application-wide text scale. Applied at the MaterialApp level via
/// MediaQuery.textScaler so it scales EVERY Text widget in the app,
/// not just chat message bubbles.
class FontSizeNotifier extends ChangeNotifier {
  static final FontSizeNotifier instance = FontSizeNotifier._();
  FontSizeNotifier._();

  String _size = 'orta';
  String get size => _size;

  /// Chat bubble font size (kept for backward compat with existing widgets).
  double get msgFontSize => _size == 'kucuk' ? 12.0 : _size == 'buyuk' ? 16.0 : 13.5;

  /// Global scale factor applied via MediaQuery.textScaler on MaterialApp.
  double get scale =>
      _size == 'kucuk' ? 0.85 :
      _size == 'buyuk' ? 1.20 :
      1.0;

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
