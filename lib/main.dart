import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'theme.dart';
import 'i18n.dart';
import 'root_gate.dart';
import 'app_keys.dart';
import 'local_store.dart';
import 'notification_service.dart';
import 'chat_wallpaper.dart';
import 'offline_queue.dart';
import 'app_lock.dart';
import 'screens/lock_screen.dart';
import 'font_size.dart';

@pragma('vm:entry-point')
void _bgDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == 'photon_keep_alive') {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString('knk_my_server_url_v1');
      if (url != null && url.isNotEmpty) {
        try {
          await http.get(Uri.parse('${url.endsWith('/') ? url.substring(0, url.length - 1) : url}/lookup/00000'))
              .timeout(const Duration(seconds: 10));
        } catch (_) {}
      }
    }
    return true;
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final isDark = await LocalStore.loadThemeDark();
  PhotonTheme.instance.setDark(isDark);
  await AppLang.loadLang();
  await FontSizeNotifier.instance.load();
  await ChatWallpaper.loadWallpaper();
  await OfflineQueue.instance.load();
  if (Platform.isAndroid) {
    await NotificationService.init();
    await Workmanager().initialize(_bgDispatcher);
    await Workmanager().registerPeriodicTask(
      'photon_keep_alive',
      'photon_keep_alive',
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }
  runApp(const PhotonApp());
}

class PhotonApp extends StatelessWidget {
  const PhotonApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([PhotonTheme.instance, AppLang.instance, FontSizeNotifier.instance]),
      builder: (context, _) => MaterialApp(
        title: 'Photon Chat',
        debugShowCheckedModeBanner: false,
        theme: PhotonTheme.instance.isDark ? photonTheme : photonLightTheme,
        home: const _LockGate(),
      ),
    );
  }
}

class _LockGate extends StatefulWidget {
  const _LockGate();
  @override
  State<_LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<_LockGate> with WidgetsBindingObserver {
  bool _locked = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkLock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkLock() async {
    final enabled = await AppLock.isEnabled();
    setState(() { _locked = enabled; _checking = false; });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkLock();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return Scaffold(backgroundColor: PhotonColors.bg, body: const SizedBox());
    }
    if (_locked) {
      return LockScreen(onUnlocked: () => setState(() => _locked = false));
    }
    return RootGate(key: rootGateKey);
  }
}

