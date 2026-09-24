import 'dart:convert';

import '../../features/personal_profile/personal_profile_models.dart';

/// Display-only schema shared by the main broker and auxiliary renderer.
/// No account context, target refs, grants, URLs, local state or edit capability.
final class MenuProfileView {
  const MenuProfileView(this.state, {this.snapshot});
  final String state;
  final PersonalProfileSnapshot? snapshot;

  static Map<String, Object?> encode(
    PersonalProfileSnapshot p, {
    String? avatar,
  }) {
    if (p.allowEditing || p.local != null) throw const FormatException();
    return encodeSelf(p, avatar: avatar);
  }

  /// Called only for the authenticated local owner's read. The same display
  /// whitelist strips edit leases, local state and all account authority.
  static Map<String, Object?> encodeSelf(
    PersonalProfileSnapshot p, {
    String? avatar,
  }) {
    if (p.availability != PersonalProfileAvailability.available) {
      return {
        'state': p.failureKey == 'profile.visitor.notVisible'
            ? 'notVisible'
            : 'unavailable',
      };
    }
    Map<String, Object?> tag(PersonalProfileTagValue t) => {
      'label': t.labelKey,
      'category': t.category.name,
      'primary': t.isPrimary,
      'display': t.displayLabel,
    };
    Map<String, Object?> identity(PersonalProfileShipIdentity i) => {
      'id': i.runtimeId,
      'en': i.englishName,
      'zh': i.simplifiedChineseName,
      'tw': i.traditionalChineseName,
      'catalog': i.catalogId,
    };
    final h = p.hangarSummary;
    final result = <String, Object?>{
      'state': 'ready',
      'name': p.callSign,
      'handle': p.gameHandle,
      'about': p.about,
      'avatar': inlineImage(p.avatarImageData) ?? inlineImage(avatar),
      'avatarStyle': p.avatarStyle,
      'wallpaper': p.wallpaperId,
      'visibility': p.visibility.name,
      'intent': p.presenceIntent.name,
      'affiliations': [
        for (final a in p.affiliations)
          {
            'kind': a.kind.name,
            'name': a.name,
            'code': a.code,
            'position': a.positionLabelKey,
            'image': inlineImage(a.logoImageData),
          },
      ],
      'windows': [for (final w in p.availabilityWindows) w.toJson()],
      'timezone': p.timeZoneLabel,
      'minutes': p.gameplayMinutes,
      'rhythm': p.activityRhythm.name,
      'roles': p.roles.map(tag).toList(),
      'interests': p.participationInterests.map(tag).toList(),
      'support': p.supportCapabilities.map(tag).toList(),
      'wishlist': p.shipWishlist.map(tag).toList(),
      'ships': [
        for (final s in p.favoriteShips)
          {
            'identity': identity(s.identity),
            'manufacturer': s.manufacturer,
            'image': asset(s.imageAsset),
            'thumbnail': asset(s.thumbnailAsset),
            'role': s.roleKey,
            'crew': s.crewLabel,
            'size': s.sizeKey,
            'value': s.valueLabel,
            'valueKey': s.valueLabelKey,
            'icon': s.catalogIconKey,
            'former': s.formerlyOwned,
          },
      ],
      'hangar': {
        'available': h.isAvailable,
        'ships': h.shipCount,
        'manufacturers': h.manufacturerCount,
        'role': h.primaryRoleKey,
        'value': h.estimatedValueLabel,
        'unresolved': h.unresolvedFavoriteCount,
        'unpriced': h.unpricedCount,
        'categories': [
          for (final c in h.categories)
            {
              'label': c.labelKey,
              'count': c.count,
              'category': c.category.name,
            },
        ],
        'recent': h.recentlyAddedShip == null
            ? null
            : identity(h.recentlyAddedShip!),
        'image': asset(h.recentlyAddedShipImageAsset),
        'added': h.recentlyAddedAtLabel,
        'source': h.sourceLabelKey,
        'synced': h.syncedAtLabel,
      },
      'modules': [
        for (final m in p.moduleLayout)
          {
            'id': m.moduleId,
            'size': m.size.name,
            'visible': m.isVisible,
            'position': m.position,
            'favorites': m.favoriteShipIds,
          },
      ],
    };
    if (utf8.encode(jsonEncode(result)).length > 900000 ||
        parse(result).state != 'ready') {
      throw const FormatException();
    }
    return result;
  }

  static String? inlineImage(Object? value) {
    if (value is! String ||
        value.length > 131072 ||
        !RegExp(r'^data:image/(png|jpeg);base64,[A-Za-z0-9+/]+={0,2}$')
            .hasMatch(value)) {
      return null;
    }
    return value;
  }

  static String asset(Object? value) =>
      value is String &&
          RegExp(r'^assets/[A-Za-z0-9_./-]+$').hasMatch(value) &&
          !value.contains('..')
      ? value
      : '';

  static MenuProfileView parse(Object? value) {
    try {
      final d = _map(value);
      final state = _text(d, 'state');
      if (state != 'ready') {
        return MenuProfileView(
          const [
                'loading',
                'unavailable',
                'notVisible',
                'revoked',
              ].contains(state)
              ? state
              : 'unavailable',
        );
      }
      PersonalProfileTagValue tag(Map d) => PersonalProfileTagValue(
        labelKey: _text(d, 'label'),
        category: _enum(PersonalProfileTagCategory.values, d['category']),
        isPrimary: _bool(d, 'primary'),
        displayLabel: _optional(d, 'display'),
      );
      PersonalProfileShipIdentity identity(Object? value) {
        final i = _map(value);
        return PersonalProfileShipIdentity(
          runtimeId: _text(i, 'id'),
          englishName: _text(i, 'en'),
          simplifiedChineseName: _text(i, 'zh'),
          traditionalChineseName: _text(i, 'tw'),
          catalogId: _optional(i, 'catalog'),
        );
      }

      final h = _map(d['hangar']);
      return MenuProfileView(
        'ready',
        snapshot: PersonalProfileSnapshot.available(
          allowEditing: false,
          callSign: _text(d, 'name'),
          gameHandle: _text(d, 'handle'),
          about: _text(d, 'about', max: 16000),
          avatarStyle: _int(d, 'avatarStyle'),
          avatarImageData: inlineImage(d['avatar']),
          wallpaperId: _text(d, 'wallpaper'),
          visibility: _enum(PersonalProfileVisibility.values, d['visibility']),
          presenceIntent: _enum(
            PersonalProfilePresenceIntent.values,
            d['intent'],
          ),
          affiliations: [
            for (final a in _list(d, 'affiliations', 16))
              PersonalProfileAffiliationSummary(
                kind: _enum(PersonalProfileAffiliationKind.values, a['kind']),
                name: _text(a, 'name'),
                code: _text(a, 'code'),
                positionLabelKey: _text(a, 'position'),
                logoImageData: inlineImage(a['image']),
              ),
          ],
          availabilityWindows: [
            for (final w in _list(d, 'windows', 32))
              PersonalProfileAvailabilityWindow(
                days: _days(w['days']),
                startTime: _text(w, 'startTime', max: 5),
                endTime: _text(w, 'endTime', max: 5),
              ),
          ],
          timeZoneLabel: _text(d, 'timezone'),
          gameplayMinutes: _int(d, 'minutes'),
          activityRhythm: _enum(
            PersonalProfileActivityRhythm.values,
            d['rhythm'],
          ),
          roles: _list(d, 'roles', 64).map(tag).toList(),
          participationInterests: _list(d, 'interests', 64).map(tag).toList(),
          supportCapabilities: _list(d, 'support', 64).map(tag).toList(),
          shipWishlist: _list(d, 'wishlist', 64).map(tag).toList(),
          favoriteShips: [
            for (final s in _list(d, 'ships', 64))
              PersonalProfileShipSummary(
                identity: identity(s['identity']),
                manufacturer: _text(s, 'manufacturer'),
                imageAsset: asset(s['image']),
                thumbnailAsset: asset(s['thumbnail']),
                roleKey: _text(s, 'role'),
                crewLabel: _text(s, 'crew'),
                sizeKey: _text(s, 'size'),
                valueLabel: _text(s, 'value'),
                valueLabelKey: _text(s, 'valueKey'),
                catalogIconKey: _optional(s, 'icon'),
                formerlyOwned: _bool(s, 'former'),
              ),
          ],
          hangarSummary: PersonalProfileHangarSummary(
            isAvailable: _bool(h, 'available'),
            shipCount: _int(h, 'ships'),
            manufacturerCount: _int(h, 'manufacturers'),
            primaryRoleKey: _text(h, 'role'),
            estimatedValueLabel: _text(h, 'value'),
            unresolvedFavoriteCount: _int(h, 'unresolved'),
            unpricedCount: h['unpriced'] == null ? null : _int(h, 'unpriced'),
            categories: [
              for (final c in _list(h, 'categories', 64))
                PersonalProfileHangarCategorySlice(
                  labelKey: _text(c, 'label'),
                  count: _int(c, 'count'),
                  category: _enum(
                    PersonalProfileTagCategory.values,
                    c['category'],
                  ),
                ),
            ],
            recentlyAddedShip: h['recent'] == null
                ? null
                : identity(h['recent']),
            recentlyAddedShipImageAsset: asset(h['image']),
            recentlyAddedAtLabel: _text(h, 'added'),
            sourceLabelKey: _text(h, 'source'),
            syncedAtLabel: _text(h, 'synced'),
          ),
          moduleLayout: [
            for (final m in _list(d, 'modules', 64))
              PersonalProfileModuleLayoutItem(
                moduleId: _text(m, 'id'),
                size: _enum(PersonalProfileModuleSize.values, m['size']),
                isVisible: _bool(m, 'visible'),
                position: _int(m, 'position'),
                favoriteShipIds: _strings(m['favorites']),
              ),
          ],
        ),
      );
    } on Object {
      return const MenuProfileView('unavailable');
    }
  }
}

Map _map(Object? v) => v is Map ? v : throw const FormatException();
String _text(Map d, String key, {int max = 512}) {
  final v = d[key];
  if (v is! String || v.length > max) throw const FormatException();
  return v;
}

String? _optional(Map d, String key) => d[key] == null ? null : _text(d, key);
int _int(Map d, String key) {
  final v = d[key];
  if (v is! int || v < 0 || v > 1000000000) throw const FormatException();
  return v;
}

bool _bool(Map d, String key) =>
    d[key] is bool ? d[key] as bool : throw const FormatException();
T _enum<T extends Enum>(List<T> options, Object? v) =>
    options.firstWhere((e) => e.name == v);
List<Map> _list(Map d, String key, int max) {
  final v = d[key];
  if (v is! List || v.length > max) throw const FormatException();
  return v.map(_map).toList();
}

List<int> _days(Object? v) {
  if (v is! List || v.length > 7 || v.any((e) => e is! int || e < 0 || e > 6)) {
    throw const FormatException();
  }
  return v.cast<int>();
}

List<String>? _strings(Object? v) {
  if (v == null) return null;
  if (v is! List ||
      v.length > 64 ||
      v.any((e) => e is! String || e.length > 512)) {
    throw const FormatException();
  }
  return v.cast<String>();
}
