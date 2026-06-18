import 'package:flutter/material.dart';
import 'theme.dart';
import 'root_gate.dart';
import 'app_keys.dart';
import 'local_store.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final isDark = await LocalStore.loadThemeDark();
  KnkTheme.instance.setDark(isDark);
  runApp(const KnkApp());
}

class KnkApp extends StatelessWidget {
  const KnkApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: KnkTheme.instance,
      builder: (context, _) => MaterialApp(
        title: 'Photon Chat',
        debugShowCheckedModeBanner: false,
        theme: KnkTheme.instance.isDark ? knkTheme : knkLightTheme,
        home: RootGate(key: rootGateKey),
      ),
    );
  }
}
