import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../i18n.dart';
import '../photon_api.dart';
import '../profile_anim.dart';
import '../theme.dart';
import '../vip.dart';
import '../vip_text.dart';
import '../anims/profile_anim_player.dart';

/// Full-screen profile view.
///
/// The intro animation belongs to the person being looked at, not the viewer:
/// whoever opens A's profile sees A's animation, A included.
class ProfileScreen extends StatefulWidget {
  final String fipId;
  final String name;
  final String code;
  final String avatar;
  final String bio;
  final String statusMsg;
  final bool isOnline;

  /// True when this is your own profile — swaps the action button for Settings.
  final bool isSelf;

  /// Opens the chat with this person. Null on your own profile.
  final VoidCallback? onMessage;

  /// Opens Settings. Null on someone else's profile — settings are private.
  final VoidCallback? onSettings;

  const ProfileScreen({
    super.key,
    required this.fipId,
    required this.name,
    required this.code,
    this.avatar = '',
    this.bio = '',
    this.statusMsg = '',
    this.isOnline = false,
    this.isSelf = false,
    this.onMessage,
    this.onSettings,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  /// Whether the intro has finished. The profile is built underneath it the
  /// whole time so nothing has to be re-laid-out when the animation ends.
  bool _introDone = false;
  ProfileAnim _anim = ProfileAnim.none;
  VipStatus? _vip;

  /// True while waiting to find out whether this person has an animation.
  bool _resolving = false;
  Timer? _holdTimer;

  @override
  void initState() {
    super.initState();
    final cached = VipCache.instance.peek(widget.fipId);
    if (cached != null) {
      _vip = cached;
      _anim = ProfileAnim.fromId(cached.anim);
      _introDone = _anim == ProfileAnim.none;
      return;
    }
    // Cold cache. Reading only from the cache meant the animation was silently
    // skipped whenever it had not been filled yet — right after adding someone,
    // or on the first profile opened after a cold start. Fetch it, but on a
    // short leash: a sleeping bridge shows the profile rather than hanging.
    _resolving = true;
    _resolve();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  Future<void> _resolve() async {
    _holdTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted && _resolving) {
        setState(() {
          _resolving = false;
          _introDone = true;
        });
      }
    });
    final raw = await PhotonApi.getTier(widget.fipId);
    if (!mounted || !_resolving) return;
    final st = raw == null ? VipStatus.none : VipStatus.fromJson(raw);
    VipCache.instance.put(widget.fipId, st);
    _holdTimer?.cancel();
    setState(() {
      _vip = st;
      _anim = ProfileAnim.fromId(st.anim);
      _resolving = false;
      _introDone = _anim == ProfileAnim.none;
    });
  }

  @override
  Widget build(BuildContext context) {
    final vip = _vip;
    final shownName = vipDisplayName(vip, widget.name);
    final nameColor = vipNameColor(vip) ?? PhotonColors.text;
    final accent = vip?.color ?? PhotonColors.accent;

    return Scaffold(
      backgroundColor: PhotonColors.bg,
      appBar: AppBar(
        title: Text(AppLang.instance.t('profileTitle')),
        actions: [
          if (widget.isSelf && widget.onSettings != null)
            IconButton(
              icon: Icon(Icons.settings_outlined, color: PhotonColors.textDim),
              tooltip: AppLang.instance.t('settings'),
              onPressed: widget.onSettings,
            ),
        ],
      ),
      body: Stack(
        children: [
          // Blank while we find out whether there is an animation, so the
          // profile does not flash up and then get covered by one.
          if (_resolving)
            const SizedBox.shrink()
          else
            // The player wraps the body rather than covering it: the spiral
            // flies the content in and the balloon burst scatters it, so the
            // effect has to be able to transform it.
            Positioned.fill(
            child: _introDone
                ? _profileBody(shownName, nameColor, vip)
                : ProfileAnimPlayer(
                    anim: _anim,
                    accent: accent,
                    onDone: () {
                      if (mounted) setState(() => _introDone = true);
                    },
                    child: _profileBody(shownName, nameColor, vip),
                  ),
          ),
          // The shatter deliberately never heals — the cracks stay over the
          // profile until it is closed.
          if (!_resolving && _anim.leavesResidue)
            Positioned.fill(
              child: IgnorePointer(child: CrackResidue(accent: accent)),
            ),
        ],
      ),
    );
  }

  Widget _profileBody(String shownName, Color nameColor, VipStatus? vip) {
    final tier = (vip ?? VipStatus.none).effectiveTier;
    final status = widget.isOnline
        ? AppLang.instance.t('online')
        : (widget.statusMsg.isNotEmpty ? widget.statusMsg : AppLang.instance.t('offline'));
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.s3, Space.s4, Space.s3, Space.s5),
      children: [
        ContentWidth(
          max: 560,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _avatar(shownName, Space.s7),
            const SizedBox(height: Space.s3),
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Flexible(
                child: Text(shownName,
                    style: PText.display.copyWith(color: nameColor),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              if (tier.premiumTag) ...[
                const SizedBox(width: Space.s1),
                VipBadge(status: vip, fontSize: 11),
              ],
            ]),
            const SizedBox(height: Space.s1),
            Row(children: [
              Container(
                width: Space.s1, height: Space.s1,
                decoration: BoxDecoration(
                  color: widget.isOnline ? PhotonColors.accent : PhotonColors.textDim,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: Space.s1),
              Flexible(child: Text(status,
                  style: PText.small.copyWith(color: widget.isOnline ? PhotonColors.accent : PhotonColors.textDim))),
            ]),
            const SizedBox(height: Space.s4),
            // Kod, profildeki tek "kimlik" bilgisi: kendi vurgulu bloğunda.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Space.s2),
              decoration: BoxDecoration(
                color: PhotonColors.accentWash,
                border: Border.all(color: PhotonColors.line),
                borderRadius: BorderRadius.circular(PhotonRadius.card),
              ),
              child: Row(children: [
                Expanded(child: Text(trUpper(AppLang.instance.t('codeLabel')), style: PText.label)),
                Text(widget.code,
                    style: PText.h1.merge(PText.tabular).copyWith(
                        color: PhotonColors.accent, fontFamily: PhotonFonts.body, fontWeight: FontWeight.w600, letterSpacing: 4)),
              ]),
            ),
            if (widget.bio.isNotEmpty) ...[
              const SizedBox(height: Space.s1),
              _card(AppLang.instance.t('bioSection'), widget.bio),
            ],
            if (tier != VipTier.none) ...[
              const SizedBox(height: Space.s1),
              _card(AppLang.instance.t('shopCurrentTier'), tier.label, valueColor: nameColor),
            ],
            const SizedBox(height: Space.s4),
            if (widget.isSelf && widget.onSettings != null)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: widget.onSettings,
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  label: Text(AppLang.instance.t('settings')),
                ),
              )
            else if (widget.onMessage != null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: widget.onMessage,
                  icon: const Icon(Icons.chat_outlined, size: 18),
                  label: Text(AppLang.instance.t('sendMessage')),
                ),
              ),
          ]),
        ),
      ],
    );
  }

  Widget _card(String label, String value, {Color? valueColor}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Space.s2),
        decoration: BoxDecoration(
          color: PhotonColors.panel,
          border: Border.all(color: PhotonColors.line),
          borderRadius: BorderRadius.circular(PhotonRadius.card),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(trUpper(label), style: PText.label.copyWith(color: PhotonColors.textDim)),
          const SizedBox(height: Space.s1),
          Text(value,
              style: PText.body.copyWith(
                  color: valueColor ?? PhotonColors.text,
                  fontWeight: valueColor != null ? FontWeight.w600 : FontWeight.normal)),
        ]),
      );

  Widget _avatar(String name, double size) {
    if (widget.avatar.isNotEmpty) {
      try {
        return ClipRRect(
          borderRadius: BorderRadius.circular(size / 4),
          child: Image.memory(base64Decode(widget.avatar), width: size, height: size, fit: BoxFit.cover),
        );
      } catch (_) {
        // Fall through to initials — a corrupt avatar must not blank the page.
      }
    }
    return Container(
      width: size, height: size, alignment: Alignment.center,
      decoration: BoxDecoration(
        color: PhotonColors.accentWash,
        borderRadius: BorderRadius.circular(size / 4),
        border: Border.all(color: PhotonColors.line),
      ),
      child: Text(
        name.isNotEmpty ? trUpper(name[0]) : '?',
        style: TextStyle(fontFamily: PhotonFonts.display, color: PhotonColors.accent, fontSize: size * 0.42),
      ),
    );
  }
}
