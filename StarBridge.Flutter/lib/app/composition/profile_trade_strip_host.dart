import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../../features/marketplace/marketplace_controller.dart';
import '../../features/marketplace/marketplace_copy.dart';
import '../../features/marketplace/marketplace_details.dart';
import '../../features/marketplace/marketplace_port.dart';
import '../../features/marketplace/marketplace_trade_profile.dart';
import '../../features/personal_profile/personal_profile_trade_strip.dart';

/// Owner's trade strip on the personal profile. Reads the hall's trade
/// profile (and the time-zone table it needs to convert the window to local
/// time) through the shared [MarketplaceController]; editing reuses the
/// accepted trade profile dialog. Unknown state shows nothing rather than a
/// false "not set up".
class ProfileTradeStripHost extends StatefulWidget {
  const ProfileTradeStripHost(
    this.market, {
    this.view = ProfileTradeStripView.owner,
    super.key,
  });
  final MarketplaceController market;

  /// The owner's own view, or the owner previewing what visitors see.
  final ProfileTradeStripView view;
  @override
  State<ProfileTradeStripHost> createState() => _ProfileTradeStripHostState();
}

class _ProfileTradeStripHostState extends State<ProfileTradeStripHost> {
  MarketplaceController get c => widget.market;
  bool _read = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    await Future.wait([
      if (c.tradeProfile == null) c.loadTradeProfile(),
      if (c.blocks['timezones'] == null) c.load('timezones', 'timezones'),
    ]);
    if (mounted) setState(() => _read = true);
  }

  Future<void> _edit() async {
    await editTradeProfile(context, c);
    if (mounted) await c.loadTradeProfile();
  }

  @override
  Widget build(BuildContext context) {
    if (c.port is! MarketplaceTradeProfilePort) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final profile = c.tradeProfile;
        // Still reading, or the read failed: say nothing rather than claim
        // the owner never set a trade profile.
        if (profile == null) return const SizedBox.shrink();
        if (!_read && c.blocks['timezones'] == null) {
          return const SizedBox.shrink();
        }
        final data = profileTradeStripData(context, c, profile);
        return switch (widget.view) {
          ProfileTradeStripView.owner => ProfileTradeStrip(
            data: data,
            isSelf: true,
            onEdit: () => unawaited(_edit()),
          ),
          ProfileTradeStripView.visitor => ProfileTradeStrip(
            data: data,
            isSelf: false,
          ),
          // Outside the visibility only the days and window stay public.
          ProfileTradeStripView.restrictedVisitor => ProfileTradeStrip(
            data: data == null
                ? null
                : ProfileTradeStripData(
                    localDays: data.localDays,
                    localWindow: data.localWindow,
                    openNow: data.openNow,
                    ownerWindow: data.ownerWindow,
                  ),
            isSelf: false,
          ),
        };
      },
    );
  }
}

/// Maps the SCM trade profile to the strip, in the viewer's local time.
/// Null when the profile has no valid window (the owner should set it up).
ProfileTradeStripData? profileTradeStripData(
  BuildContext context,
  MarketplaceController c,
  MarketRow profile, {
  DateTime? now,
}) {
  Object? raw = profile['tradeTime'];
  try {
    raw = raw is String ? jsonDecode(raw) : raw;
  } on FormatException {
    raw = null;
  }
  String? hhmm(Object? v) {
    final match = RegExp(r'^(\d{2}:\d{2})').firstMatch('${v ?? ''}');
    return match?[1];
  }

  final start = hhmm(profile['tradeStartTime']);
  final end = hhmm(profile['tradeEndTime']);
  if (raw is! List ||
      raw.length != 7 ||
      !raw.contains(1) ||
      start == null ||
      end == null) {
    return null;
  }
  var days = [for (final v in raw) v == 1 ? 1 : 0];
  var localStart = start, localEnd = end;
  final owner = marketZoneOffsets[marketNumber(profile['timezoneId'])?.toInt()];
  if (owner != null) {
    final shifted = marketShiftWindow(
      days,
      start,
      end,
      ownerOffset: owner,
      localOffset: (now ?? DateTime.now()).timeZoneOffset.inMinutes,
    );
    if (shifted != null) {
      days = shifted.days;
      localStart = shifted.start;
      localEnd = shifted.end;
    }
  }
  final point = c.failures.contains('reputation')
      ? null
      : c.blocks['reputation']?.data['point'] ?? profile['point'];
  final done = marketNumber(profile['completedTransactionCount']);
  return ProfileTradeStripData(
    localDays: [for (final d in days) d == 1],
    localWindow: '$localStart–$localEnd',
    openNow: marketTradeOpenNow(profile, now: now),
    contact: profileContactChannel(context, profile['userMobile']?.toString()),
    reputation: point == null
        ? null
        : [
            '★ $point',
            if (done != null) marketTextN(context, 'bannerDone', done),
          ].join(' · '),
  );
}

/// The profile names only the contact channel ("QQ", "微信", "Discord"…),
/// never the account itself: the full contact stays in the trade profile
/// dialog and in SCM's trade flow. SCM stores contact as free text, so the
/// channel is recognised from it; anything else reads as "set".
String? profileContactChannel(BuildContext context, String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return null;
  final lower = text.toLowerCase();
  final locale = Localizations.maybeLocaleOf(context);
  final en = locale?.languageCode == 'en';
  final hant =
      locale?.scriptCode == 'Hant' ||
      const {'TW', 'HK', 'MO'}.contains(locale?.countryCode);
  String pick(String hans, String hantText, String english) =>
      en ? english : (hant ? hantText : hans);
  if (lower.contains('discord') || RegExp(r'\S#\d{4}\b').hasMatch(text)) {
    return 'Discord';
  }
  if (lower.contains('kook') || text.contains('开黑啦') || text.contains('開黑啦')) {
    return 'KOOK';
  }
  if (text.contains('微信') ||
      RegExp(r'\b(wx|vx|wechat|weixin)\b').hasMatch(lower)) {
    return pick('微信', '微信', 'WeChat');
  }
  if (lower.contains('qq') || RegExp(r'^\d{5,11}$').hasMatch(text)) {
    if (RegExp(r'^1\d{10}$').hasMatch(text)) return pick('手机', '手機', 'Phone');
    return 'QQ';
  }
  if (RegExp(r'^\S+@\S+\.\S+$').hasMatch(text)) {
    return pick('邮箱', '郵箱', 'Email');
  }
  return pick('已填写', '已填寫', 'Provided');
}
