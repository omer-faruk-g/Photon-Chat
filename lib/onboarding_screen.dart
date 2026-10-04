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
          padding: const EdgeInsets.fromLTRB(Space.s3, Space.s2, Space.s3, Space.s4),
          child: ContentWidth(max: 560, child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                BrandMark(size: 28),
                const SizedBox(width: Space.s1),
                Text('Photon Chat', style: PText.h2),
              ]),
              const SizedBox(height: Space.s5),
              Text(AppLang.instance.t('createIdentityOnDevice'), style: PText.display),
              const SizedBox(height: Space.s2),
              Text(AppLang.instance.t('photonChatTagline'), style: PText.bodyDim),
              const SizedBox(height: 24),
              FipCard(
                title: AppLang.instance.t('fipPreview'),
                fip: preview,
                onRegen: _regen,
              ),
              const SizedBox(height: 24),
              Text(AppLang.instance.t('displayNameFriendsOnly'), style: PText.small.copyWith(color: PhotonColors.text)),
              const SizedBox(height: 8),
              TextField(
                controller: _nameCtrl,
                maxLength: 20,
                style: TextStyle(color: PhotonColors.text, fontSize: 15),
                decoration: photonInputDecoration(AppLang.instance.t('displayNameExample')),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: photonPrimaryButtonStyle(),
                onPressed: (_nameCtrl.text.trim().isEmpty || _created != null || _creating) ? null : _create,
                child: _creating
                    ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: PhotonColors.onAccent))
                    : Text(AppLang.instance.t('createIdentityOnDevice')),
              ),
              const SizedBox(height: 16),
              Text(
                AppLang.instance.t('onboardingPrivacyNote'),
                style: PText.meta.copyWith(height: 1.5),
              ),
              if (_created != null) ...[
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: PhotonColors.panel,
                    border: Border.all(color: PhotonColors.accent.withOpacity(0.4)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(AppLang.instance.t('yourCode'), style: PText.label),
                    const SizedBox(height: 8),
                    Text(
                      _created!.code,
                      style: PText.display.merge(PText.tabular).copyWith(color: PhotonColors.accent, fontFamily: PhotonFonts.body, fontWeight: FontWeight.w600, letterSpacing: 6),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppLang.instance.t('shareCodeWithFriends'),
                      style: PText.meta,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.copy_outlined, size: 15),
                        label: Text(AppLang.instance.t('copyCode')),
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
          )),
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
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: PhotonColors.panel,
        border: Border.all(color: PhotonColors.line),
        borderRadius: BorderRadius.circular(PhotonRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.s2, Space.s2, Space.s1, Space.s1),
            child: Row(children: [
              Expanded(child: Text(trUpper(title), style: PText.label)),
              if (onRegen != null)
                TextButton.icon(
                  onPressed: onRegen,
                  icon: const Icon(Icons.refresh_outlined, size: 16),
                  label: Text(AppLang.instance.t('regenerateShort')),
                ),
            ]),
          ),
          Divider(height: 1, color: PhotonColors.line),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: Space.s1),
            child: Column(children: [
              for (final (i, line) in fip.lines.take(6).indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    SizedBox(
                      width: Space.s3,
                      child: Text((i + 1).toString().padLeft(2, '0'),
                          style: PText.meta.merge(PText.tabular).copyWith(color: PhotonColors.accent2, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: Space.s1),
                    Expanded(
                      child: Text(line, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: PText.small.merge(PText.tabular).copyWith(color: PhotonColors.text)),
                    ),
                  ]),
                ),
              if (fip.lines.length > 6)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: Space.s4, top: 2),
                    child: Text('+ ${fip.lines.length - 6}', style: PText.meta),
                  ),
                ),
            ]),
          ),
          Container(
            color: PhotonColors.accentWash,
            padding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: Space.s2),
            child: Row(children: [
              Expanded(child: Text(trUpper(AppLang.instance.t('matchCodeUpper')), style: PText.label.copyWith(color: PhotonColors.textDim))),
              FittedBox(
                child: Text(fip.code,
                    style: PText.h1.merge(PText.tabular).copyWith(color: PhotonColors.accent, fontFamily: PhotonFonts.body, fontWeight: FontWeight.w600, letterSpacing: 4)),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
