import 'dart:convert';
import 'package:flutter/material.dart';
import '../i18n.dart';
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
  late final ProfileAnim _anim;
  VipStatus? _vip;

  @override
  void initState() {
    super.initState();
    _vip = VipCache.instance.peek(widget.fipId);
    _anim = ProfileAnim.fromId(_vip?.anim);
    _introDone = _anim == ProfileAnim.none;
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
              icon: Icon(Icons.settings, color: PhotonColors.textDim),
              tooltip: AppLang.instance.t('settings'),
              onPressed: widget.onSettings,
            ),
        ],
      ),
      body: Stack(
        children: [
          // The player wraps the body rather than covering it: the spiral flies
          // the content in and the balloon burst scatters it, which means the
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
          if (_anim.leavesResidue)
            Positioned.fill(
              child: IgnorePointer(child: CrackResidue(accent: accent)),
            ),
        ],
      ),
    );
  }

  Widget _profileBody(String shownName, Color nameColor, VipStatus? vip) =>
      ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          Center(child: _avatar(shownName, 96)),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(
              child: Text(
                shownName,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: nameColor,
                    fontSize: 22,
                    fontWeight: FontWeight.w700),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if ((vip ?? VipStatus.none).effectiveTier.premiumTag) ...[
              const SizedBox(width: 8),
              VipBadge(status: vip, fontSize: 10),
            ],
          ]),
          const SizedBox(height: 6),
          Center(
            child: Text(
              widget.isOnline
                  ? AppLang.instance.t('online')
                  : (widget.statusMsg.isNotEmpty
                      ? widget.statusMsg
                      : AppLang.instance.t('offline')),
              style: TextStyle(
                color: widget.isOnline
                    ? const Color(0xFF4CAF50)
                    : PhotonColors.textDim,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 20),
          _card(AppLang.instance.t('codeLabel'), widget.code),
          if (widget.bio.isNotEmpty) ...[
            const SizedBox(height: 10),
            _card(AppLang.instance.t('bioSection'), widget.bio),
          ],
          if ((vip ?? VipStatus.none).effectiveTier != VipTier.none) ...[
            const SizedBox(height: 10),
            _card(AppLang.instance.t('shopCurrentTier'),
                (vip ?? VipStatus.none).effectiveTier.label,
                valueColor: nameColor),
          ],
          const SizedBox(height: 26),
          if (widget.isSelf && widget.onSettings != null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: photonPrimaryButtonStyle(),
                onPressed: widget.onSettings,
                child: Text(AppLang.instance.t('settings')),
              ),
            )
          else if (widget.onMessage != null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: photonPrimaryButtonStyle(),
                onPressed: widget.onMessage,
                child: Text(AppLang.instance.t('sendMessage')),
              ),
            ),
        ],
      );

  Widget _card(String label, String value, {Color? valueColor}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: PhotonColors.panel,
          border: Border.all(color: PhotonColors.line),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  color: PhotonColors.textDim,
                  fontSize: 10,
                  letterSpacing: 1.5)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: valueColor ?? PhotonColors.text,
                  fontSize: 14,
                  height: 1.5,
                  fontWeight:
                      valueColor != null ? FontWeight.w700 : FontWeight.normal)),
        ]),
      );

  Widget _avatar(String name, double size) {
    if (widget.avatar.isNotEmpty) {
      try {
        return CircleAvatar(
          radius: size / 2,
          backgroundImage: MemoryImage(base64Decode(widget.avatar)),
        );
      } catch (_) {
        // Fall through to initials — a corrupt avatar must not blank the page.
      }
    }
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: PhotonColors.accent.withOpacity(0.2),
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
            color: PhotonColors.accent,
            fontSize: size * 0.38,
            fontWeight: FontWeight.bold),
      ),
    );
  }
}
