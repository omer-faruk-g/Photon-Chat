import 'package:flutter/material.dart';
import '../anims/profile_anim_player.dart';
import '../i18n.dart';
import '../photon_api.dart';
import '../profile_anim.dart';
import '../theme.dart';
import '../vip.dart';
import 'shop_screen.dart';

/// Picks which owned animation plays when someone opens your profile.
///
/// Mirrors fake_name_screen: load current state, change it, save to the bridge,
/// drop the cache entry so your own screens do not keep showing the old value.
class ProfileAnimScreen extends StatefulWidget {
  final String fipId;
  const ProfileAnimScreen({super.key, required this.fipId});

  @override
  State<ProfileAnimScreen> createState() => _ProfileAnimScreenState();
}

class _ProfileAnimScreenState extends State<ProfileAnimScreen> {
  AnimOwnership _own = AnimOwnership.empty;
  ProfileAnim _selected = ProfileAnim.none;
  ProfileAnim _previewing = ProfileAnim.none;
  Color _accent = PhotonColors.accent;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final raw = await PhotonApi.getAnims(widget.fipId);
    final tierRaw = await PhotonApi.getTier(widget.fipId);
    if (!mounted) return;
    final own = raw == null ? AnimOwnership.empty : AnimOwnership.fromJson(raw);
    final vip = tierRaw == null ? VipStatus.none : VipStatus.fromJson(tierRaw);
    setState(() {
      _own = own;
      _selected = own.active;
      _previewing = own.active == ProfileAnim.none
          ? (own.owned.isEmpty ? ProfileAnim.none : own.owned.first)
          : own.active;
      _accent = vip.color ?? PhotonColors.accent;
      _loading = false;
    });
  }

  Future<void> _select(ProfileAnim a) async {
    final ok = await PhotonApi.setActiveAnim(widget.fipId, a.id);
    if (ok) VipCache.instance.invalidate(widget.fipId);
    if (!mounted) return;
    if (ok) setState(() => _selected = a);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(AppLang.instance.t(ok ? 'animSaved' : 'animSaveFailed')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLang.instance.t('animPickerTitle'))),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: PhotonColors.accent))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ProfileAnimPreview(anim: _previewing, accent: _accent),
                const SizedBox(height: 16),
                _row(ProfileAnim.none),
                ...ProfileAnim.purchasable.map(_row),
                const SizedBox(height: 12),
                Text(AppLang.instance.t('animFreeNote'),
                    style: TextStyle(
                        color: PhotonColors.textDim, fontSize: 11, height: 1.5)),
              ],
            ),
    );
  }

  Widget _row(ProfileAnim a) {
    final owned = a == ProfileAnim.none || _own.owns(a);
    final isSelected = _selected == a;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          if (!owned) {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ShopScreen(fipId: widget.fipId)),
            ).then((_) { if (mounted) _load(); });
            return;
          }
          // Preview first, select on the second tap — so browsing does not keep
          // writing to the bridge.
          if (_previewing != a) {
            setState(() => _previewing = a);
          } else {
            _select(a);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: PhotonColors.panel,
            border: Border.all(
              color: isSelected ? PhotonColors.accent : PhotonColors.line,
              width: isSelected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Icon(
              owned
                  ? (isSelected ? Icons.check_circle : Icons.play_circle_outline)
                  : Icons.lock_outline,
              size: 18,
              color: isSelected ? PhotonColors.accent : PhotonColors.textDim,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppLang.instance.t(a.nameKey),
                        style: TextStyle(
                            color: PhotonColors.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(AppLang.instance.t(a.descKey),
                        style: TextStyle(
                            color: PhotonColors.textDim, fontSize: 11)),
                  ]),
            ),
            if (isSelected)
              Text(AppLang.instance.t('animActive'),
                  style: TextStyle(
                      color: PhotonColors.accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w700))
            else if (!owned)
              Text(AppLang.instance.t('animLocked'),
                  style:
                      TextStyle(color: PhotonColors.textDim, fontSize: 10)),
          ]),
        ),
      ),
    );
  }
}
