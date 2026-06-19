import 'dart:io';
import 'package:flutter/material.dart';
import 'theme.dart';
import 'i18n.dart';
import 'root_gate.dart';
import 'app_keys.dart';
import 'local_store.dart';
import 'notification_service.dart';
import 'chat_wallpaper.dart';
import 'offline_queue.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final isDark = await LocalStore.loadThemeDark();
  KnkTheme.instance.setDark(isDark);
  await AppLang.loadLang();
  await ChatWallpaper.loadWallpaper();
  await OfflineQueue.instance.load();
  if (Platform.isAndroid) await NotificationService.init();
  runApp(const KnkApp());
}

class KnkApp extends StatelessWidget {
  const KnkApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([KnkTheme.instance, AppLang.instance]),
      builder: (context, _) => MaterialApp(
        title: 'Photon Chat',
        debugShowCheckedModeBanner: false,
        theme: KnkTheme.instance.isDark ? knkTheme : knkLightTheme,
        home: RootGate(key: rootGateKey),
      ),
    );
  }
}
