import 'package:flutter/material.dart';
import 'theme.dart';
import 'root_gate.dart';
import 'app_keys.dart';

void main() {
  runApp(const KnkApp());
}

class KnkApp extends StatelessWidget {
  const KnkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Photon Chat',
      debugShowCheckedModeBanner: false,
      theme: knkTheme,
      home: RootGate(key: rootGateKey),
    );
  }
}
