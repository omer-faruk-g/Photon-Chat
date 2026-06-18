import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'theme.dart';

class UpdateChecker {
  static const _releasesApi = 'https://api.github.com/repos/omer-faruk-g/Photon-Chat/releases/latest';

  static Future<void> check(BuildContext context) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final current = _parseVersion(info.version);

      final r = await http.get(Uri.parse(_releasesApi), headers: {'Accept': 'application/vnd.github+json'}).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return;

      final data = jsonDecode(r.body) as Map<String, dynamic>;
      final tagName = (data['tag_name'] as String?)?.replaceAll(RegExp(r'[^0-9.]'), '') ?? '';
      final latest = _parseVersion(tagName);
      final releaseUrl = data['html_url'] as String? ?? '';
      final assets = (data['assets'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      if (!_isNewer(latest, current)) return;
      if (!context.mounted) return;

      final displayTag = data['tag_name'] as String? ?? tagName;
      final body = (data['body'] as String?) ?? '';

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => _UpdateDialog(
          currentVersion: info.version,
          newVersion: displayTag,
          releaseNotes: body,
          releaseUrl: releaseUrl,
          assets: assets,
        ),
      );
    } catch (_) {}
  }

  static List<int> _parseVersion(String v) {
    final parts = v.split('.');
    return parts.map((p) => int.tryParse(p) ?? 0).toList();
  }

  static bool _isNewer(List<int> latest, List<int> current) {
    for (var i = 0; i < 3; i++) {
      final l = i < latest.length ? latest[i] : 0;
      final c = i < current.length ? current[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }
}

class _UpdateDialog extends StatefulWidget {
  final String currentVersion;
  final String newVersion;
  final String releaseNotes;
  final String releaseUrl;
  final List<Map<String, dynamic>> assets;

  const _UpdateDialog({
    required this.currentVersion,
    required this.newVersion,
    required this.releaseNotes,
    required this.releaseUrl,
    required this.assets,
  });

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress;
  bool _downloading = false;
  String? _error;

  String? _apkUrl() {
    for (final a in widget.assets) {
      final name = (a['name'] as String?) ?? '';
      if (name.endsWith('.apk')) return a['browser_download_url'] as String?;
    }
    return null;
  }

  Future<void> _downloadAndInstall() async {
    final apkUrl = _apkUrl();
    if (apkUrl == null) {
      await launchUrl(Uri.parse(widget.releaseUrl), mode: LaunchMode.externalApplication);
      return;
    }

    setState(() { _downloading = true; _error = null; _progress = 0; });

    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/PhotonChat-update.apk';
      final dio = Dio();
      await dio.download(
        apkUrl,
        path,
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) setState(() => _progress = received / total);
        },
      );
      if (mounted) setState(() { _downloading = false; _progress = null; });
      await OpenFile.open(path);
    } catch (e) {
      if (mounted) setState(() { _downloading = false; _progress = null; _error = 'İndirme başarısız. Tarayıcıdan güncelle.'; });
    }
  }

  Future<void> _openBrowser() async {
    await launchUrl(Uri.parse(widget.releaseUrl), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final isAndroid = Platform.isAndroid;
    final hasApk = _apkUrl() != null;

    return AlertDialog(
      backgroundColor: KnkColors.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Row(children: [
        const Text('🚀 ', style: TextStyle(fontSize: 18)),
        Expanded(child: Text('Güncelleme Mevcut', style: TextStyle(color: KnkColors.text, fontSize: 16, fontWeight: FontWeight.w700))),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(widget.currentVersion, style: TextStyle(color: KnkColors.textDim, fontSize: 12)),
            Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward, size: 14, color: KnkColors.accent)),
            Text(widget.newVersion, style: TextStyle(color: KnkColors.accent, fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
          if (widget.releaseNotes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: KnkColors.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: KnkColors.line)),
              child: Text(
                widget.releaseNotes.length > 300 ? '${widget.releaseNotes.substring(0, 300)}…' : widget.releaseNotes,
                style: TextStyle(color: KnkColors.textDim, fontSize: 11, height: 1.5),
              ),
            ),
          ],
          if (_downloading) ...[
            const SizedBox(height: 14),
            LinearProgressIndicator(value: _progress, backgroundColor: KnkColors.line, color: KnkColors.accent),
            const SizedBox(height: 6),
            Text(
              _progress != null ? '%${(_progress! * 100).toStringAsFixed(0)} indiriliyor…' : 'Hazırlanıyor…',
              style: TextStyle(color: KnkColors.textDim, fontSize: 11),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: KnkColors.danger, fontSize: 11)),
          ],
        ],
      ),
      actions: _downloading
          ? []
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Sonra', style: TextStyle(color: KnkColors.textDim, fontSize: 13)),
              ),
              if (isAndroid && hasApk)
                ElevatedButton(
                  style: knkPrimaryButtonStyle(),
                  onPressed: _downloadAndInstall,
                  child: const Text('Güncelle'),
                )
              else
                ElevatedButton(
                  style: knkPrimaryButtonStyle(),
                  onPressed: _openBrowser,
                  child: const Text('İndir'),
                ),
            ],
    );
  }
}
