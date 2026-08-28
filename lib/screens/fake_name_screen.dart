import 'package:flutter/material.dart';
import '../i18n.dart';
import '../photon_api.dart';
import '../theme.dart';
import '../vip.dart';

/// Alias settings for photonPulseVip subscribers.
///
/// Switching the alias on rewrites the name everywhere, including on messages
/// already sent: names are resolved live from the bridge at render time rather
/// than stamped onto each message when it is sent.
class FakeNameScreen extends StatefulWidget {
  final String fipId;
  final String realName;

  const FakeNameScreen({super.key, required this.fipId, required this.realName});

  @override
  State<FakeNameScreen> createState() => _FakeNameScreenState();
}

class _FakeNameScreenState extends State<FakeNameScreen> {
  final _ctrl = TextEditingController();
  bool _active = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final raw = await PhotonApi.getTier(widget.fipId);
    if (!mounted) return;
    final s = raw == null ? VipStatus.none : VipStatus.fromJson(raw);
    setState(() {
      _ctrl.text = s.fakeName;
      _active = s.fakeActive;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final name = _ctrl.text.trim();
    // Turning the alias on without one would silently do nothing — the bridge
    // refuses to activate a blank alias.
    if (_active && name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLang.instance.t('fakeNameEmpty'))),
      );
      return;
    }
    setState(() => _saving = true);
    final ok = await PhotonApi.setTierPrefs(
      widget.fipId,
      fakeName: name,
      fakeActive: _active,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(AppLang.instance.t(ok ? 'fakeNameSaved' : 'fakeNameFailed')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final shown = _active && _ctrl.text.trim().isNotEmpty
        ? _ctrl.text.trim()
        : widget.realName;

    return Scaffold(
      appBar: AppBar(title: Text(AppLang.instance.t('fakeNameTitle'))),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: PhotonColors.accent))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: PhotonColors.panel,
                    border: Border.all(color: PhotonColors.line),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(AppLang.instance.t('fakeNameField'),
                            style: TextStyle(
                                color: PhotonColors.textDim,
                                fontSize: 10,
                                letterSpacing: 1.5)),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _ctrl,
                          maxLength: 40,
                          style: TextStyle(color: PhotonColors.text, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: AppLang.instance.t('fakeNameHint'),
                            hintStyle: TextStyle(
                                color: PhotonColors.textDim, fontSize: 13),
                            filled: true,
                            fillColor: PhotonColors.bg,
                            counterStyle: TextStyle(
                                color: PhotonColors.textDim, fontSize: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: PhotonColors.line),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        Row(children: [
                          Expanded(
                            child: Text(AppLang.instance.t('fakeNameEnabled'),
                                style: TextStyle(
                                    color: PhotonColors.text, fontSize: 14)),
                          ),
                          Switch(
                            value: _active,
                            activeColor: PhotonColors.accent,
                            onChanged: (v) => setState(() => _active = v),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        Text(
                          '${AppLang.instance.t('fakeNameShowing')}: $shown',
                          style: TextStyle(
                              color: PhotonColors.textDim, fontSize: 12),
                        ),
                      ]),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: photonPrimaryButtonStyle(),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Color(0xFF06251A)))
                        : Text(AppLang.instance.t('save')),
                  ),
                ),
              ],
            ),
    );
  }
}
