import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'fip.dart';
import 'i18n.dart';
import 'local_store.dart';
import 'theme.dart';

/// İlk açılışta cihazda yeni bir FIP kimliği oluşturma ekranı.
class OnboardingScreen extends StatefulWidget {
  final String myServerUrl;
  final void Function(FipBlock fip, String name) onCreated;
  const OnboardingScreen({super.key, required this.myServerUrl, required this.onCreated});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  FipBlock? _preview;
  final _nameCtrl = TextEditingController();
  FipBlock? _created;

  @override
  void initState() {
    super.initState();
    _preview = FipBlock.generate();
  }

  void _regen() {
    setState(() => _preview = FipBlock.generate());
  }

  bool _creating = false;

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _preview == null || _creating) return;
    setState(() => _creating = true);
    try {
      final fip = await LocalStore.createIdentity(existing: _preview);
      await LocalStore.saveDisplayName(name);
      if (!mounted) return;
      setState(() => _created = fip);
      // Do NOT immediately advance — let the user see and copy their code.
      // A "Devam" button below fires widget.onCreated.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLang.instance.t('identityCreateFailed')}: $e'), backgroundColor: PhotonColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _finish() {
    if (_created == null) return;
    widget.onCreated(_created!, _nameCtrl.text.trim());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview!;
    return Scaffold(
      backgroundColor: PhotonColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset(
                        'assets/icon/icon.png',
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'PHOTON CHAT',
                      style: TextStyle(
                        fontFamily: 'sans-serif',
                        fontWeight: FontWeight.w800,
                        fontSize: 28,
                        letterSpacing: 4,
                        color: PhotonColors.accent,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      AppLang.instance.t('photonChatTagline'),
                      style: TextStyle(color: PhotonColors.textDim, fontSize: 11, letterSpacing: 0.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              FipCard(
                title: AppLang.instance.t('fipPreview'),
                fip: preview,
                onRegen: _regen,
              ),
              const SizedBox(height: 24),
              Text(AppLang.instance.t('displayNameFriendsOnly'),
                  style: TextStyle(color: PhotonColors.textDim, fontSize: 11, letterSpacing: 1)),
              const SizedBox(height: 8),
              TextField(
                controller: _nameCtrl,
                maxLength: 20,
                style: TextStyle(color: PhotonColors.text, fontSize: 15),
                decoration: photonInputDecoration(AppLang.instance.t('displayNameExample')),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                style: photonPrimaryButtonStyle(),
                onPressed: (_nameCtrl.text.trim().isEmpty || _created != null || _creating) ? null : _create,
                child: _creating
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF06251A)))
                    : Text(AppLang.instance.t('createIdentityOnDevice')),
              ),
              const SizedBox(height: 12),
              Text(
                AppLang.instance.t('onboardingPrivacyNote'),
                style: TextStyle(color: PhotonColors.textDim, fontSize: 11, height: 1.6),
              ),
              if (_created != null) ...[
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: PhotonColors.panel,
                    border: Border.all(color: PhotonColors.accent.withOpacity(0.4)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(AppLang.instance.t('yourCode'), style: TextStyle(color: PhotonColors.textDim, fontSize: 10, letterSpacing: 1.5)),
                    const SizedBox(height: 8),
                    Text(
                      _created!.code,
                      style: TextStyle(color: PhotonColors.accent, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 6, fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppLang.instance.t('shareCodeWithFriends'),
                      style: TextStyle(color: PhotonColors.textDim, fontSize: 11),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: PhotonColors.text,
                          side: BorderSide(color: PhotonColors.line),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.copy, size: 15),
                        label: Text(AppLang.instance.t('copyCode'), style: const TextStyle(fontSize: 13)),
                        onPressed: () => Clipboard.setData(ClipboardData(text: _created!.code)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: photonPrimaryButtonStyle(),
                        onPressed: _finish,
                        child: Text(AppLang.instance.t('continueArrow')),
                      ),
                    ),
                  ]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// FIP bloğunu 20 satır halinde gösteren kart (önizleme ve ayarlarda kullanılır).
class FipCard extends StatelessWidget {
  final String title;
  final FipBlock fip;
  final VoidCallback? onRegen;

  const FipCard({super.key, required this.title, required this.fip, this.onRegen});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PhotonColors.panel,
        border: Border.all(color: PhotonColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: TextStyle(color: PhotonColors.textDim, fontSize: 11, letterSpacing: 1.5)),
              if (onRegen != null)
                GestureDetector(
                  onTap: onRegen,
                  child: Text(AppLang.instance.t('regenerateShort'),
                      style: TextStyle(
                          color: PhotonColors.accent2,
                          fontSize: 11,
                          decoration: TextDecoration.underline)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: PhotonColors.bg,
              border: Border.all(color: PhotonColors.line),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: fip.lines.length,
              itemBuilder: (context, i) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        child: Text((i + 1).toString().padLeft(2, '0'),
                            style: TextStyle(
                                color: PhotonColors.accent2, fontSize: 11, fontFamily: 'monospace')),
                      ),
                      Expanded(
                        child: Text(
                          fip.lines[i],
                          style: TextStyle(
                              color: PhotonColors.text,
                              fontSize: 10.5,
                              fontFamily: 'monospace',
                              letterSpacing: 0.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(AppLang.instance.t('matchCodeUpper'),
                  style: TextStyle(color: PhotonColors.textDim, fontSize: 11, letterSpacing: 1.5)),
              Text(
                fip.code,
                style: TextStyle(
                  color: PhotonColors.accent,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
