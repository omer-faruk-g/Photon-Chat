import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Paid tiers, cheapest first. Each tier includes every feature of the ones
/// below it, so capability checks compare rank rather than listing tiers.
///
/// Tier data lives on the bridge, never on a user's own server: every user runs
/// their own `server/index.js`, so a self-hosted tier field could be granted for
/// free with a one-line edit and the subscriptions would be worthless.
enum VipTier {
  none(0, 0, ''),
  vip(1, 25, 'VIP'),
  vipPlus(2, 50, 'VIP+'),
  pvip(3, 100, 'PVip'),
  pvipPlus(4, 175, 'PVip+'),
  photon(5, 250, 'Photon'),
  photonPlus(6, 300, 'Photon+'),
  photonPulse(7, 400, 'PhotonPulse'),
  photonPulseVip(8, 500, 'PhotonPulseVİP');

  const VipTier(this.rank, this.priceTry, this.label);

  /// Position in the ladder. Capability checks use this, not the enum index.
  final int rank;

  /// Monthly price in Turkish lira.
  final int priceTry;

  /// Product name. A brand, so it is not translated.
  final String label;

  /// i18n key describing what THIS tier adds on top of the previous one.
  String get addsKey => switch (this) {
        VipTier.none => 'vipNone',
        VipTier.vip => 'vipAddsColoredName',
        VipTier.vipPlus => 'vipAddsColoredText',
        VipTier.pvip => 'vipAddsBold',
        VipTier.pvipPlus => 'vipAddsTag',
        VipTier.photon => 'vipAddsBigFiles',
        VipTier.photonPlus => 'vipAddsRender',
        VipTier.photonPulse => 'vipAddsEncryption',
        VipTier.photonPulseVip => 'vipAddsFakeName',
      };

  bool get coloredName => rank >= VipTier.vip.rank;
  bool get coloredText => rank >= VipTier.vipPlus.rank;
  bool get boldMessages => rank >= VipTier.pvip.rank;
  bool get premiumTag => rank >= VipTier.pvipPlus.rank;
  bool get biggerFiles => rank >= VipTier.photon.rank;
  bool get betterRender => rank >= VipTier.photonPlus.rank;
  bool get localEncryption => rank >= VipTier.photonPulse.rank;
  bool get fakeName => rank >= VipTier.photonPulseVip.rank;

  /// Every purchasable tier, cheapest first.
  static List<VipTier> get purchasable =>
      VipTier.values.where((t) => t != VipTier.none).toList();

  static VipTier fromName(String? name) => VipTier.values.firstWhere(
        (t) => t.name == name,
        orElse: () => VipTier.none,
      );
}

/// Upload ceiling in bytes. Photon and above get 30 MB on top of the base 50 MB.
///
/// NOTE: base64 inflates payloads by ~33%, so these must stay under the
/// server's `bigBody` limit or the upload fails with 413.
int maxFileBytesFor(VipTier tier) =>
    (tier.biggerFiles ? 80 : 50) * 1024 * 1024;

/// Longest edge images are downscaled to before sending.
int imageEdgeFor(VipTier tier) => tier.betterRender ? 1440 : 800;

/// JPEG quality used when recompressing outgoing images.
int imageQualityFor(VipTier tier) => tier.betterRender ? 90 : 70;

/// A user's tier plus the presentation choices that come with it.
class VipStatus {
  final VipTier tier;

  /// Chosen accent, applied to both the display name and message text.
  /// Null means "use the default theme colour".
  final Color? color;

  final String fakeName;
  final bool fakeActive;

  /// Epoch millis the subscription lapses. Zero for [VipTier.none].
  final int expiresAt;

  const VipStatus({
    this.tier = VipTier.none,
    this.color,
    this.fakeName = '',
    this.fakeActive = false,
    this.expiresAt = 0,
  });

  static const none = VipStatus();

  bool get isActive =>
      tier != VipTier.none &&
      (expiresAt == 0 || DateTime.now().millisecondsSinceEpoch < expiresAt);

  /// Tier to render with — lapsed subscriptions fall back to none so expiry
  /// needs no scheduled job on either side.
  VipTier get effectiveTier => isActive ? tier : VipTier.none;

  factory VipStatus.fromJson(Map<String, dynamic> j) {
    final rawColor = (j['color'] as num?)?.toInt();
    return VipStatus(
      tier: VipTier.fromName(j['tier'] as String?),
      color: rawColor == null || rawColor == 0 ? null : Color(rawColor),
      fakeName: (j['fakeName'] as String?) ?? '',
      fakeActive: j['fakeActive'] == true,
      expiresAt: (j['expiresAt'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'tier': tier.name,
        if (color != null) 'color': color!.value,
        'fakeName': fakeName,
        'fakeActive': fakeActive,
        'expiresAt': expiresAt,
      };
}

/// Colours offered to subscribers. Picked to stay readable on both themes.
const List<Color> kVipColors = [
  Color(0xFF3DDC97), // photon green
  Color(0xFF4FC3F7), // sky
  Color(0xFF9C7BFF), // violet
  Color(0xFFFF7BC2), // pink
  Color(0xFFF2A33D), // amber
  Color(0xFFFF6B5B), // coral
  Color(0xFFFFD54F), // gold
  Color(0xFF00E5C0), // teal
];

/// Short-lived cache of other people's tiers.
///
/// Badges are decoration: when the bridge is asleep (Render free tier) a lookup
/// fails and the last known status keeps rendering rather than flickering off.
class VipCache {
  VipCache._();
  static final VipCache instance = VipCache._();

  static const _ttl = Duration(minutes: 5);
  static const _maxEntries = 512;

  final Map<String, ({VipStatus status, DateTime at})> _entries = {};

  VipStatus? peek(String fipId) => _entries[fipId]?.status;

  bool _isFresh(String fipId) {
    final e = _entries[fipId];
    return e != null && DateTime.now().difference(e.at) < _ttl;
  }

  void put(String fipId, VipStatus status) {
    if (_entries.length >= _maxEntries && !_entries.containsKey(fipId)) {
      _entries.remove(_entries.keys.first); // insertion order == oldest first
    }
    _entries[fipId] = (status: status, at: DateTime.now());
  }

  /// Drop a cached entry so the next refresh re-reads it. Needed after you
  /// change your own tier, colour or alias: otherwise your own screens keep
  /// showing the previous state for up to the TTL and the change looks lost.
  void invalidate(String fipId) => _entries.remove(fipId);

  /// Fetch any ids whose cached status has gone stale. One request for the
  /// whole batch — a contact list of N people must not become N round-trips.
  Future<void> refresh(String bridgeUrl, Iterable<String> fipIds) async {
    final stale = fipIds.where((id) => id.isNotEmpty && !_isFresh(id)).toSet();
    if (stale.isEmpty) return;
    try {
      final base = bridgeUrl.endsWith('/')
          ? bridgeUrl.substring(0, bridgeUrl.length - 1)
          : bridgeUrl;
      final r = await http
          .post(Uri.parse('$base/tiers/batch'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'fipIds': stale.toList()}))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return;
      final data = (jsonDecode(r.body) as Map).cast<String, dynamic>();
      for (final id in stale) {
        final raw = data[id];
        put(id, raw is Map ? VipStatus.fromJson(raw.cast<String, dynamic>()) : VipStatus.none);
      }
    } catch (_) {
      // Keep whatever is cached; decoration must never break the screen.
    }
  }
}
