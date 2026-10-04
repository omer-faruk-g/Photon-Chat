import 'package:flutter/material.dart';
import '../i18n.dart';
import '../local_store.dart';
import '../photon_api.dart';
import '../theme.dart';
import '../profile_anim.dart';
import '../vip.dart';
import 'shop_anim_screen.dart';
import 'shop_tier_screen.dart';

/// Tier catalogue. Each row names only what that tier *adds* — showing the full
/// cumulative list eight times over would be unreadable. The complete list lives
/// on the detail page.
class ShopScreen extends StatefulWidget {
  final String fipId;
  const ShopScreen({super.key, required this.fipId});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  VipStatus _status = VipStatus.none;
  AnimOwnership _anims = AnimOwnership.empty;
  bool _loading = true;

  /// TEMPORARY. Lets the owner move between tiers without a payment path while
  /// Play Billing is unwired. Remove together with the redeem section once real
  /// purchases land — the grant endpoint it drives is unauthenticated.
  bool _ownerMode = false;
  final _codeCtrl = TextEditingController();
  static const _ownerCode = 'OWNER';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final raw = await PhotonApi.getTier(widget.fipId);
    final animRaw = await PhotonApi.getAnims(widget.fipId);
    final owner = await LocalStore.loadOwnerMode();
    if (!mounted) return;
    setState(() {
      _status = raw == null ? VipStatus.none : VipStatus.fromJson(raw);
      _anims =
          animRaw == null ? AnimOwnership.empty : AnimOwnership.fromJson(animRaw);
      _ownerMode = owner;
      _loading = false;
    });
  }

  Future<void> _redeem() async {
    final ok = _codeCtrl.text.trim().toUpperCase() == _ownerCode;
    if (ok) {
      await LocalStore.saveOwnerMode(true);
      if (!mounted) return;
      setState(() {
        _ownerMode = true;
        _codeCtrl.clear();
      });
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(AppLang.instance.t(ok ? 'shopRedeemOk' : 'shopRedeemBad')),
    ));
  }

  Future<void> _revoke() async {
    final ok = await PhotonApi.grantTier(widget.fipId, 'none');
    if (ok) VipCache.instance.invalidate(widget.fipId);
    if (!mounted) return;
    if (ok) await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(AppLang.instance.t(ok ? 'shopRevoked' : 'shopGrantFailed')),
    ));
  }

  Future<void> _pickColor(Color c) async {
    final ok = await PhotonApi.setTierPrefs(widget.fipId, color: c.value);
    if (ok) VipCache.instance.invalidate(widget.fipId);
    if (!mounted) return;
    if (ok) {
      setState(() => _status = VipStatus(
            tier: _status.tier,
            color: c,
            fakeName: _status.fakeName,
            fakeActive: _status.fakeActive,
            expiresAt: _status.expiresAt,
          ));
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(AppLang.instance
          .t(ok ? 'shopColorSaved' : 'shopColorFailed')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final active = _status.effectiveTier;
    return Scaffold(
      appBar: AppBar(title: Text(AppLang.instance.t('shopTitle'))),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: PhotonColors.accent))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _currentTierCard(active),
                const SizedBox(height: 16),
                _redeemSection(),
                if (active.coloredName) ...[
                  const SizedBox(height: 16),
                  _colorPicker(),
                ],
                const SizedBox(height: 20),
                ...VipTier.purchasable.map((t) => _tierRow(t, active)),
                const SizedBox(height: 22),
                Text(AppLang.instance.t('animSectionTitle'),
                    style: TextStyle(
                        color: PhotonColors.textDim,
                        fontSize: 10,
                        letterSpacing: 1.5)),
                const SizedBox(height: 10),
                ...ProfileAnim.purchasable.map((a) => _animRow(a, active)),
                _animRow(null, active),
                const SizedBox(height: 8),
                Text(AppLang.instance.t('animFreeNote'),
                    style: TextStyle(
                        color: PhotonColors.textDim,
                        fontSize: 11,
                        height: 1.5)),
              ],
            ),
    );
  }

  Widget _currentTierCard(VipTier active) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: PhotonColors.panel,
          border: Border.all(color: PhotonColors.line),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(AppLang.instance.t('shopCurrentTier'),
              style: TextStyle(color: PhotonColors.textDim, fontSize: 10, letterSpacing: 1.5)),
          const SizedBox(height: 6),
          Text(
            active == VipTier.none ? AppLang.instance.t('vipNone') : active.label,
            style: TextStyle(
              color: _status.color ?? PhotonColors.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ]),
      );

  /// TEMPORARY test-code panel. Delete with [_ownerMode].
  Widget _redeemSection() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: PhotonColors.panel,
          border: Border.all(
              color: _ownerMode ? PhotonColors.accent2 : PhotonColors.line),
          borderRadius: BorderRadius.circular(12),
        ),
        child: _ownerMode
            ? Row(children: [
                Icon(Icons.science, size: 18, color: PhotonColors.accent2),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(AppLang.instance.t('shopOwnerMode'),
                            style: TextStyle(
                                color: PhotonColors.accent2,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                        Text(AppLang.instance.t('shopOwnerModeDesc'),
                            style: TextStyle(
                                color: PhotonColors.textDim, fontSize: 11)),
                      ]),
                ),
                TextButton(
                  onPressed: _revoke,
                  child: Text(AppLang.instance.t('shopRevoke'),
                      style: TextStyle(
                          color: PhotonColors.danger, fontSize: 12)),
                ),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(AppLang.instance.t('shopRedeemTitle'),
                    style: TextStyle(
                        color: PhotonColors.textDim,
                        fontSize: 10,
                        letterSpacing: 1.5)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _codeCtrl,
                      textCapitalization: TextCapitalization.characters,
                      style: TextStyle(color: PhotonColors.text, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: AppLang.instance.t('shopRedeemHint'),
                        hintStyle: TextStyle(
                            color: PhotonColors.textDim, fontSize: 13),
                        isDense: true,
                        filled: true,
                        fillColor: PhotonColors.bg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: PhotonColors.line),
                        ),
                      ),
                      onSubmitted: (_) => _redeem(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: photonPrimaryButtonStyle(),
                    onPressed: _redeem,
                    child: Text(AppLang.instance.t('shopRedeemButton')),
                  ),
                ]),
              ]),
      );

  Widget _colorPicker() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: PhotonColors.panel,
          border: Border.all(color: PhotonColors.line),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(AppLang.instance.t('shopColorSection'),
              style: TextStyle(color: PhotonColors.textDim, fontSize: 10, letterSpacing: 1.5)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: kVipColors.map((c) {
              final selected = _status.color?.value == c.value;
              return GestureDetector(
                onTap: () => _pickColor(c),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? PhotonColors.text : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ]),
      );

  /// A single animation, or the five-pack when [anim] is null.
  Widget _animRow(ProfileAnim? anim, VipTier active) {
    final isBundle = anim == null;
    final owned = isBundle ? _anims.hasAll : _anims.owns(anim);
    final label = isBundle
        ? AppLang.instance.t('animBundle')
        : AppLang.instance.t(anim.nameKey);
    final desc = isBundle
        ? AppLang.instance.t('animBundleDesc')
        : AppLang.instance.t(anim.descKey);
    // The bundle is a flat price; the tier discount deliberately does not stack.
    final price = isBundle
        ? '$kAnimBundleTry₺'
        : _formatTry(animPriceFor(active));

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ShopAnimScreen(
                anim: anim,
                fipId: widget.fipId,
                tier: active,
                owned: _anims,
                accent: _status.color ?? PhotonColors.accent,
                ownerMode: _ownerMode,
              ),
            ),
          );
          if (mounted) _load();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: PhotonColors.panel,
            border: Border.all(
              color: owned ? PhotonColors.accent : PhotonColors.line,
              width: owned ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(label,
                            style: TextStyle(
                                color: PhotonColors.text,
                                fontSize: 14,
                                fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (owned) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: PhotonColors.accent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                              AppLang.instance.t(
                                  isBundle ? 'animBundleOwned' : 'animOwned'),
                              style: TextStyle(
                                  color: PhotonColors.accent,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    Text(desc,
                        style: TextStyle(
                            color: PhotonColors.textDim, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ]),
            ),
            if (!owned)
              Text(price,
                  style: TextStyle(
                      color: PhotonColors.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            Icon(Icons.chevron_right, color: PhotonColors.textDim, size: 18),
          ]),
        ),
      ),
    );
  }

  /// 25% off 50₺ is 37,50₺ — the only discount that lands off a whole lira.
  static String _formatTry(double v) => v == v.roundToDouble()
      ? '${v.toStringAsFixed(0)}₺'
      : '${v.toStringAsFixed(2).replaceAll('.', ',')}₺';

  Widget _tierRow(VipTier tier, VipTier active) {
    final isActive = tier == active;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ShopTierScreen(
                tier: tier,
                fipId: widget.fipId,
                currentTier: active,
                ownerMode: _ownerMode,
              ),
            ),
          );
          if (mounted) _load();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: PhotonColors.panel,
            border: Border.all(
              color: isActive ? PhotonColors.accent : PhotonColors.line,
              width: isActive ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(tier.label,
                      style: TextStyle(
                          color: PhotonColors.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  if (isActive) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: PhotonColors.accent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(AppLang.instance.t('shopActive'),
                          style: TextStyle(
                              color: PhotonColors.accent,
                              fontSize: 9,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ]),
                const SizedBox(height: 2),
                Text('+ ${AppLang.instance.t(tier.addsKey)}',
                    style: TextStyle(color: PhotonColors.textDim, fontSize: 11)),
              ]),
            ),
            Text('${tier.priceTry}₺${AppLang.instance.t('shopPerMonth')}',
                style: TextStyle(
                    color: PhotonColors.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            Icon(Icons.chevron_right, color: PhotonColors.textDim, size: 18),
          ]),
        ),
      ),
    );
  }
}
