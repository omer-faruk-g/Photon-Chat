import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});
  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  bool _scanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QR ile Ekle')),
      body: Stack(children: [
        MobileScanner(
          onDetect: (capture) {
            if (_scanned) return;
            final barcode = capture.barcodes.firstOrNull;
            final value = barcode?.rawValue;
            if (value != null && value.length == 5 && RegExp(r'^\d{5}$').hasMatch(value)) {
              setState(() => _scanned = true);
              Navigator.pop(context, value);
            }
          },
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: KnkColors.panel.withOpacity(0.9), borderRadius: BorderRadius.circular(12), border: Border.all(color: KnkColors.line)),
            child: Text('Arkadaşının QR kodunu kameraya tut', textAlign: TextAlign.center, style: TextStyle(color: KnkColors.text, fontSize: 13)),
          ),
        ),
      ]),
    );
  }
}
