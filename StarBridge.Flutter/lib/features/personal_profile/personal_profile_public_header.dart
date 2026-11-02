import 'package:flutter/foundation.dart';

import '../../platform/bridge/bridge_envelope.dart' show BridgeFormatException;
import 'personal_profile_models.dart';
import 'personal_profile_trade_strip.dart';

/// The owner's always-public trade window, as the profile service returns it
/// to a visitor outside the profile's visibility (DEPLOY-QUEUE §4, 2026-10-21).
/// Days are Monday first in the owner's own time zone.
@immutable
final class PersonalProfilePublicTradeWindow {
  const PersonalProfilePublicTradeWindow({
    required this.days,
    required this.start,
    required this.end,
    this.ownerOffsetMinutes,
  });

  final List<bool> days;
  final String start;
  final String end;

  /// The owner's UTC offset now, resolved by the Host; null when unknown, in
  /// which case the window is shown as the owner set it.
  final int? ownerOffsetMinutes;

  static int? _minutes(String value) {
    final m = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
    return m == null ? null : int.parse(m[1]!) * 60 + int.parse(m[2]!);
  }

  static String _clock(int minutes) {
    final m = minutes % 1440;
    return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  }

  /// "UTC+08:00".
  static String utcLabel(int offset) {
    final sign = offset < 0 ? '-' : '+';
    final a = offset.abs();
    return 'UTC$sign${(a ~/ 60).toString().padLeft(2, '0')}:${(a % 60).toString().padLeft(2, '0')}';
  }

  /// The strip a visitor sees: converted to [localOffset] (the viewer's) when
  /// the owner's offset is known, with the owner's own setting beside it.
  ProfileTradeStripData toStripData({Duration? localOffset, DateTime? now}) {
    final clock = now ?? DateTime.now();
    final local = (localOffset ?? clock.timeZoneOffset).inMinutes;
    final s = _minutes(start), e = _minutes(end);
    final owner = ownerOffsetMinutes;
    var localDays = days;
    var window = '$start–$end';
    bool? openNow;
    if (owner != null && s != null && e != null) {
      final delta = local - owner;
      final shifted = s + delta;
      final carry = (shifted / 1440).floor();
      localDays = List.filled(7, false);
      for (var i = 0; i < 7; i++) {
        if (days[i]) localDays[(i + carry) % 7] = true;
      }
      window = '${_clock(shifted)}–${_clock(e + delta)}';
      // Is the owner's window open right now, in the owner's own time?
      final at = clock.toUtc().add(Duration(minutes: owner));
      final day = at.weekday - 1, t = at.hour * 60 + at.minute;
      openNow = s < e
          ? days[day] && t >= s && t < e
          : (days[day] && t >= s) || (days[(day + 6) % 7] && t < e);
    }
    return ProfileTradeStripData(
      localDays: localDays,
      localWindow: window,
      openNow: openNow,
      ownerWindow: owner == null || owner == local
          ? null
          : '$start–$end · ${utcLabel(owner)}',
    );
  }
}

/// SCM's public trade facts about someone who never chose a page visibility
/// (user rules 2026-10-30). Every value may be null: unknown, so not shown.
@immutable
final class PersonalProfilePublicFacts {
  const PersonalProfilePublicFacts({
    this.reputation,
    this.completedTrades,
    this.sellOrders,
    this.buyOrders,
    this.lastOnlineDay,
    this.siteRegisteredDay,
    this.gameRegisteredDay,
    this.language,
    this.utcOffsetMinutes,
    this.banned,
    this.banCount,
  });

  final int? reputation;
  final int? completedTrades;
  final int? sellOrders;
  final int? buyOrders;

  /// ISO dates. A last-online time of day never reaches the client.
  final String? lastOnlineDay;
  final String? siteRegisteredDay;
  final String? gameRegisteredDay;

  /// "zh" or "en".
  final String? language;
  final int? utcOffsetMinutes;
  final bool? banned;
  final int? banCount;

  static const _keys = {
    'reputation',
    'completedTrades',
    'sellOrders',
    'buyOrders',
    'lastOnlineDay',
    'siteRegisteredDay',
    'gameRegisteredDay',
    'language',
    'utcOffsetMinutes',
    'banned',
    'banCount',
  };

  static PersonalProfilePublicFacts parse(Map<String, Object?> value) {
    if (value.keys.any((key) => !_keys.contains(key))) {
      throw const BridgeFormatException('Unknown public fact.');
    }
    int? whole(String key, int min, int max) {
      final number = value[key];
      if (number != null && (number is! int || number < min || number > max)) {
        throw BridgeFormatException('$key is not a valid number.');
      }
      return number as int?;
    }

    const limit = 1000000000;
    final isoDay = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    String? day(String key) {
      final text = value[key];
      if (text == null) return null;
      final parsed = text is String && isoDay.hasMatch(text)
          ? DateTime.tryParse('${text}T00:00:00Z')
          : null;
      // tryParse rolls 2026-02-31 over to March instead of refusing it.
      if (parsed == null ||
          parsed.toIso8601String().substring(0, 10) != text) {
        throw BridgeFormatException('$key must be a date.');
      }
      return text as String;
    }

    final language = value['language'];
    if (language != null && language != 'zh' && language != 'en') {
      throw const BridgeFormatException('Invalid public language.');
    }
    final banned = value['banned'];
    if (banned != null && banned is! bool) {
      throw const BridgeFormatException('banned must be a boolean.');
    }
    return PersonalProfilePublicFacts(
      reputation: whole('reputation', -limit, limit),
      completedTrades: whole('completedTrades', 0, limit),
      sellOrders: whole('sellOrders', 0, limit),
      buyOrders: whole('buyOrders', 0, limit),
      lastOnlineDay: day('lastOnlineDay'),
      siteRegisteredDay: day('siteRegisteredDay'),
      gameRegisteredDay: day('gameRegisteredDay'),
      language: language as String?,
      utcOffsetMinutes: whole('utcOffsetMinutes', -14 * 60, 14 * 60),
      banned: banned as bool?,
      banCount: whole('banCount', 0, limit),
    );
  }
}

/// Parses a restricted visitor payload: only the always-public header arrives
/// (callsign, avatar, trade window); everything else stays empty, never
/// guessed. [avatar] is the adapter's inline-image validation.
PersonalProfileSnapshot parseRestrictedProfile(
  Map<String, Object?> payload, {
  required String? Function(String? value) avatar,
}) {
  String text(Map<String, Object?> source, String key) {
    final value = source[key];
    if (value is! String) throw BridgeFormatException('$key must be a string.');
    return value;
  }

  final header = payload['publicHeader'];
  if (header is! Map<String, Object?>) {
    throw const BridgeFormatException('publicHeader must be an object.');
  }
  final window = header['tradeWindow'];
  final clock = RegExp(r'^\d{2}:\d{2}$');
  PersonalProfilePublicTradeWindow? trade;
  if (window != null) {
    if (window is! Map<String, Object?>) {
      throw const BridgeFormatException('Invalid public trade window.');
    }
    final days = window['days'];
    final start = text(window, 'start');
    final end = text(window, 'end');
    final offset = window['ownerOffsetMinutes'];
    if (days is! List ||
        days.length != 7 ||
        days.any((d) => d != 0 && d != 1) ||
        !clock.hasMatch(start) ||
        !clock.hasMatch(end) ||
        (offset != null && offset is! int)) {
      throw const BridgeFormatException('Invalid public trade window.');
    }
    trade = PersonalProfilePublicTradeWindow(
      days: [for (final d in days) d == 1],
      start: start,
      end: end,
      ownerOffsetMinutes: offset as int?,
    );
  }
  final image = header['avatarAssetId'];
  if (image != null && image is! String) {
    throw const BridgeFormatException('avatarAssetId must be a string.');
  }
  bool flag(String key) {
    final value = header[key];
    if (value != null && value is! bool) {
      throw BridgeFormatException('$key must be a boolean.');
    }
    return value == true;
  }

  final facts = header['facts'];
  // Only someone who never chose a visibility has these facts.
  if (facts != null && (facts is! Map<String, Object?> || !flag('defaulted'))) {
    throw const BridgeFormatException('Invalid public facts.');
  }
  return PersonalProfileSnapshot.available(
    callSign: text(header, 'callSign'),
    gameHandle: '',
    about: '',
    avatarStyle: 0,
    avatarImageData: avatar(image as String?),
    wallpaperId: 'none',
    visibility: PersonalProfileVisibility.fromBridgeValue(
      text(payload, 'visibility'),
    ),
    presenceIntent: PersonalProfilePresenceIntent.none,
    affiliations: const [],
    availabilityWindows: const [],
    timeZoneLabel: '',
    gameplayMinutes: null,
    activityRhythm: PersonalProfileActivityRhythm.casual,
    roles: const [],
    participationInterests: const [],
    supportCapabilities: const [],
    shipWishlist: const [],
    favoriteShips: const [],
    hangarSummary: const PersonalProfileHangarSummary.empty(),
    moduleLayout: const [],
    allowEditing: false,
    restricted: true,
    publicTradeWindow: trade,
    defaultedPage: flag('defaulted'),
    nameMasked: flag('nameMasked'),
    publicFacts: facts == null
        ? null
        : PersonalProfilePublicFacts.parse(facts as Map<String, Object?>),
    affiliationStatus: 'hidden',
  );
}
