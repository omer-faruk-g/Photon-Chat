import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../i18n.dart';
import '../theme.dart';

enum QrScanMode { contact, group, any }

/// QR scan screen supports scanning either a 5-digit contact code or a
/// `photon://groupCode@ownerServerUrl` group invite. Returns the raw string
/// via `Navigator.pop`, and the caller decides how to parse it.
class QrScanScreen extends StatefulWidget {
  final QrScanMode mode;
  final String? hintOverride;
  const QrScanScreen({super.key, this.mode = QrScanMode.any, this.hintOverride});
  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  bool _scanned = false;

  bool _isContactCode(String v) => RegExp(r'^\d{5}$').hasMatch(v);
  bool _isGroupInvite(String v) {
    if (!v.startsWith('photon://')) return false;
    final rest = v.substring(9);
    final at = rest.indexOf('@');
    if (at <= 0) return false;
    final code = rest.substring(0, at);
    final server = rest.substring(at + 1);
    return code.isNotEmpty && server.startsWith('http');
  }

  bool _matchesMode(String v) {
    switch (widget.mode) {
      case QrScanMode.contact: return _isContactCode(v);
      case QrScanMode.group:   return _isGroupInvite(v);
      case QrScanMode.any:     return _isContactCode(v) || _isGroupInvite(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLang.instance.t('scanQr'))),
      body: SafeArea(child: Stack(children: [
        MobileScanner(
          onDetect: (capture) {
            if (_scanned) return;
            final barcode = capture.barcodes.firstOrNull;
            final value = barcode?.rawValue;
            if (value == null) return;
            if (!_matchesMode(value)) return;
            setState(() => _scanned = true);
            Navigator.pop(context, value);
          },
        ),
        // Corner brackets for aim
        Center(
          child: Container(
            width: 240, height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: PhotonColors.accent, width: 3),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: PhotonColors.panel.withOpacity(0.9), borderRadius: BorderRadius.circular(12), border: Border.all(color: PhotonColors.line)),
            child: Text(
              widget.hintOverride ?? AppLang.instance.t(
                widget.mode == QrScanMode.group ? 'qrHoldGroupCode' : 'qrHoldCode'),
              textAlign: TextAlign.center,
              style: TextStyle(color: PhotonColors.text, fontSize: 13),
            ),
          ),
        ),
      ])),
    );
  }
}
