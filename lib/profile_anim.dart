import 'vip.dart';

/// Intro animations that play when someone's profile is opened.
///
/// The animation belongs to the profile's OWNER, not the viewer: whoever opens
/// A's profile sees A's animation, including A themselves.
///
/// Unlike tier perks these are bought outright, so ownership is tracked
/// separately on the bridge and survives a subscription lapsing.
enum ProfileAnim {
  none(''),
  pixelFace('pixelFace'),
  wave('wave'),
  balloon('balloon'),
  shatter('shatter'),
  spiral('spiral');

  const ProfileAnim(this.id);

  /// Wire value stored on the bridge. Must match ANIM_NAMES in server/index.js.
  final String id;

  /// Everything that can be bought — [none] is the absence of a purchase.
  static List<ProfileAnim> get purchasable =>
      ProfileAnim.values.where((a) => a != ProfileAnim.none).toList();

  static ProfileAnim fromId(String? id) => ProfileAnim.values.firstWhere(
        (a) => a.id == id,
        orElse: () => ProfileAnim.none,
      );

  /// i18n key for the display name.
  ///
  /// Built from [id] rather than listed, matching the `language_*` keys —
  /// tool/verify.js knows this prefix is reached by computed lookup.
  String get nameKey => 'animName_${id.isEmpty ? 'none' : id}';

  /// i18n key for the one-line description shown in the shop.
  String get descKey => 'animDesc_${id.isEmpty ? 'none' : id}';

  /// How long the intro runs before the profile is readable.
  ///
  /// Balloon is the outlier: it waits for a tap and only pops then, so this is
  /// the point at which it gives up waiting and pops by itself.
  Duration get duration => switch (this) {
        ProfileAnim.none => Duration.zero,
        ProfileAnim.pixelFace => const Duration(seconds: 3),
        ProfileAnim.wave => const Duration(seconds: 3),
        ProfileAnim.balloon => const Duration(seconds: 5),
        ProfileAnim.shatter => const Duration(milliseconds: 2500),
        ProfileAnim.spiral => const Duration(seconds: 4),
      };

  /// Balloon waits for the viewer instead of playing straight through.
  bool get waitsForTap => this == ProfileAnim.balloon;

  /// Shatter deliberately never heals: the cracks stay over the profile for as
  /// long as it is open.
  bool get leavesResidue => this == ProfileAnim.shatter;
}

/// Full price of a single animation, in Turkish lira.
const int kAnimPriceTry = 50;

/// All five together. A flat price — the tier discount does not stack on top.
const int kAnimBundleTry = 225;

/// Percentage off a single animation, by subscription tier.
///
/// Deliberately stops at PVip+: Photon and above get a free animation instead
/// of a discount. That does mean a Photon subscriber pays more per animation
/// than a PVip+ one — it is the pricing that was asked for.
int animDiscountPercent(VipTier tier) => switch (tier) {
      VipTier.vip => 10,
      VipTier.vipPlus => 15,
      VipTier.pvip => 20,
      VipTier.pvipPlus => 25,
      _ => 0,
    };

/// Price of one animation for a given tier, in lira.
///
/// Returned in kuruş-free lira as a double because 25% off 50₺ is 37,50₺ — the
/// only tier that lands off a whole number.
double animPriceFor(VipTier tier) =>
    kAnimPriceTry * (100 - animDiscountPercent(tier)) / 100;

/// Tiers from Photon upward come with one animation included.
bool tierIncludesFreeAnim(VipTier tier) => tier.rank >= VipTier.photon.rank;

/// What a user owns and which one they have selected.
class AnimOwnership {
  final Set<ProfileAnim> owned;
  final ProfileAnim active;

  const AnimOwnership({this.owned = const {}, this.active = ProfileAnim.none});

  static const empty = AnimOwnership();

  bool owns(ProfileAnim a) => owned.contains(a);

  bool get hasAll => owned.length >= ProfileAnim.purchasable.length;

  factory AnimOwnership.fromJson(Map<String, dynamic> j) {
    final list = (j['owned'] as List?) ?? const [];
    return AnimOwnership(
      owned: list
          .map((e) => ProfileAnim.fromId(e as String?))
          .where((a) => a != ProfileAnim.none)
          .toSet(),
      active: ProfileAnim.fromId(j['active'] as String?),
    );
  }
}
