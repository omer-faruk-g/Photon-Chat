import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'theme.dart';
import 'device_manager.dart';
import 'i18n.dart';

class ServerSetupScreen extends StatefulWidget {
  final void Function(String url) onDone;
  final void Function(String url, String ownerFipId)? onDeviceLink;
  const ServerSetupScreen({super.key, required this.onDone, this.onDeviceLink});
  @override
  State<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends State<ServerSetupScreen> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _test() async {
    final raw = _ctrl.text.trim();
    if (raw.isEmpty) { setState(() => _error = AppLang.instance.t('urlEmpty')); return; }
    if (!raw.startsWith('http://') && !raw.startsWith('https://')) {
      setState(() => _error = AppLang.instance.t('urlMustStartHttps'));
      return;
    }
    final url = raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
    final parsed = Uri.tryParse(url);
    if (parsed == null || parsed.host.isEmpty) {
      setState(() => _error = AppLang.instance.t('invalidUrlFormat'));
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final r = await http.get(Uri.parse('$url/lookup/00000')).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (r.statusCode == 200 || r.statusCode == 404) {
        final banned = await DeviceManager.isServerBanned(url, '');
        if (!mounted) return;
        if (banned) {
          setState(() => _error = AppLang.instance.t('serverBanned'));
          return;
        }

        final presenceCheck = await _checkExistingPresence(url);
        if (!mounted) return;
        if (presenceCheck != null && widget.onDeviceLink != null) {
          widget.onDeviceLink!(url, presenceCheck);
        } else {
          widget.onDone(url);
        }
      } else {
        setState(() => _error = '${AppLang.instance.t('serverNoResponse')} (${r.statusCode})');
      }
    } catch (e) {
      if (mounted) setState(() => _error = '${AppLang.instance.t('connectionError')}: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<String?> _checkExistingPresence(String url) async {
    try {
      final r = await http.get(Uri.parse('$url/presence/owner')).timeout(const Duration(seconds: 5));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        final ownerFipId = data['fipId'] as String?;
        if (ownerFipId != null && ownerFipId.isNotEmpty) return ownerFipId;
      }
    } catch (_) {}
    return null;
  }

  /// Çeviri metnindeki "1. …" satırlarını ayrı adımlara böler.
  List<String> get _steps => AppLang.instance.t('renderSteps')
      .split('\n')
      .map((l) => l.trim().replaceFirst(RegExp(r'^\d+[.)]\s*'), ''))
      .where((l) => l.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    return Scaffold(
      backgroundColor: PhotonColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(Space.s3, Space.s2, Space.s3, Space.s4 + MediaQuery.of(context).viewInsets.bottom),
          child: ContentWidth(
            max: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  BrandMark(size: 28),
                  const SizedBox(width: Space.s1),
                  Text('Photon Chat', style: PText.h2),
                ]),
                const SizedBox(height: Space.s5),
                Text(AppLang.instance.t('serverSetupTitle'), style: PText.display),
                const SizedBox(height: Space.s2),
                Text(AppLang.instance.t('photonChatOwnServer'), style: PText.bodyDim),
                const SizedBox(height: Space.s4),
                for (final (i, step) in steps.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.s2),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        width: Space.s3, height: Space.s3,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: PhotonColors.accentWash,
                          borderRadius: BorderRadius.circular(PhotonRadius.pill),
                          border: Border.all(color: PhotonColors.line),
                        ),
                        child: Text('${i + 1}', style: PText.meta.merge(PText.tabular).copyWith(color: PhotonColors.accent, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: Space.s2),
                      Expanded(child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(step, style: PText.body),
                      )),
                    ]),
                  ),
                const SizedBox(height: Space.s3),
                TextField(
                  controller: _ctrl,
                  style: PText.body,
                  decoration: InputDecoration(
                    labelText: AppLang.instance.t('renderUrl'),
                    hintText: AppLang.instance.t('renderUrlHint'),
                    errorText: _error,
                    errorMaxLines: 3,
                    prefixIcon: Icon(Icons.dns_outlined, color: PhotonColors.textDim),
                  ),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  onSubmitted: (_) => _loading ? null : _test(),
                ),
                const SizedBox(height: Space.s2),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _test,
                    child: _loading
                        ? SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: PhotonColors.onAccent))
                        : Text(AppLang.instance.t('connectAndContinue')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
