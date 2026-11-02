import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../common/user_interaction.dart';
import '../common/user_profile_page.dart';
import 'marketplace_copy.dart';
import 'marketplace_diagonal.dart'
    show MarketParallelogramPainter, MarketSlantTag;
import 'marketplace_quality.dart';
import 'marketplace_port.dart';

String? marketQuality(MarketRow row) {
  final raw =
      marketRows(row['items']).firstOrNull?['qualityData'] ??
      row['qualityData'];
  try {
    final data = raw is String ? jsonDecode(raw) : raw;
    if (data is! Map || data['type'] != 'material') return null;
    final value = marketNumber(data['qualityMin'] ?? data['quality']);
    return value == null
        ? null
        : '${data['qualityMin'] != null ? '≥' : ''}${value.toStringAsFixed(0)}';
  } on FormatException {
    return null;
  }
}

/// SCM time zone id -> minutes east of UTC currently in force (Host applies DST).
final marketZoneOffsets = <int, int>{};

/// Order numbers of the signed-in account's own listings (read from 我的挂单),
/// so every list marks them and never offers a trade with oneself. Holds no
/// account id; cleared when the account changes.
final marketMyOrders = <String>{};

/// A 我的挂单 row in the shape the hall's listing cards read. No 'id' key:
/// card taps resolve the item through items[0].itemId.
MarketRow marketOwnListingCard(MarketRow r) => {
  'orderNumber': r['id'],
  'itemName': r['name'],
  'items': [
    {'itemId': r['itemId'], 'qualityData': r['qualityData']},
  ],
  'thumbnailUrl': r['image'],
  'unitPrice': r['price'],
  'creatorType': r['side'] == 'buy' ? 0 : 1,
  if (r['side'] == 'barter') 'displayType': 3,
  if (r['side'] != 'barter' && r['checklist'] == true) 'displayType': 2,
  'remainingQuantity': r['quantity'],
  'availableQuantity': r['quantity'],
  'locationId': r['location'],
  'locationName': r['locationName'],
  'timezoneId': r['timezoneId'],
  // Marks it as a listing card; MarketTrader shows 我 + tag, never a name.
  'seller': '',
};

bool marketIsMine(MarketRow row) {
  final number = row['orderNumber'];
  return number != null && marketMyOrders.contains('$number');
}

class MarketMineTag extends StatelessWidget {
  const MarketMineTag({super.key});
  @override
  Widget build(BuildContext context) {
    final accent = context.tokens.colors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        marketText(context, 'mineListing'),
        style: TextStyle(
          fontSize: 10.5,
          color: accent,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

void marketRememberZones(List<MarketRow> rows) {
  for (final row in rows) {
    final id = marketNumber(row['id'])?.toInt();
    final offset = marketNumber(
      row['currentOffsetMinutes'] ?? row['offsetMinutes'],
    )?.toInt();
    if (id != null && offset != null) marketZoneOffsets[id] = offset;
  }
}

int? _minutes(String? hhmm) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(hhmm ?? '');
  if (match == null) return null;
  final h = int.parse(match.group(1)!), m = int.parse(match.group(2)!);
  return h < 24 && m < 60 ? h * 60 + m : null;
}

String _clock(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

/// Moves a weekly trade window from its owner's zone into the viewer's zone.
/// Days are Monday-first flags; a window that crosses midnight moves its days too.
({List<int> days, String start, String end})? marketShiftWindow(
  List<int> days,
  String start,
  String end, {
  required int ownerOffset,
  required int localOffset,
}) {
  final s = _minutes(start), e = _minutes(end);
  if (s == null || e == null || days.length != 7) return null;
  final delta = localOffset - ownerOffset;
  if (delta == 0) return (days: days, start: start, end: end);
  final shifted = s + delta;
  final carry = (shifted / 1440).floor();
  final moved = List.filled(7, 0);
  for (var i = 0; i < 7; i++) {
    if (days[i] == 1) moved[(i + carry) % 7] = 1;
  }
  return (
    days: moved,
    start: _clock(shifted % 1440),
    end: _clock((e + delta) % 1440),
  );
}

/// Trade window in the viewer's local time. [localOffset] is for tests.
/// Whether a trader's SCM window (stored in their own time zone, Mon..Sun)
/// is open at [now]. Null when the zone or window is unknown.
bool? marketTradeOpenNow(MarketRow row, {DateTime? now}) {
  final owner = marketZoneOffsets[marketNumber(row['timezoneId'])?.toInt()];
  int? minutes(Object? v) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(v?.toString() ?? '');
    return m == null ? null : int.parse(m[1]!) * 60 + int.parse(m[2]!);
  }

  final start = minutes(row['tradeStartTime']),
      end = minutes(row['tradeEndTime']);
  Object? raw = row['tradeTime'];
  try {
    raw = raw is String ? jsonDecode(raw) : raw;
  } on FormatException {
    return null;
  }
  if (owner == null ||
      start == null ||
      end == null ||
      raw is! List ||
      raw.length != 7) {
    return null;
  }
  final days = [for (final v in raw) v == 1];
  final at = (now ?? DateTime.now()).toUtc().add(Duration(minutes: owner));
  final day = at.weekday - 1, t = at.hour * 60 + at.minute;
  if (start < end) return days[day] && t >= start && t < end;
  // Crosses midnight: today's evening part or yesterday's early-morning part.
  return (days[day] && t >= start) || (days[(day + 6) % 7] && t < end);
}

String marketTradeTime(
  BuildContext context,
  MarketRow row, {
  Duration? localOffset,
}) {
  var start = row['tradeStartTime']?.toString(),
      end = row['tradeEndTime']?.toString();
  final time = row['tradeTime'];
  Object? days;
  try {
    days = time is String ? jsonDecode(time) : time;
  } on FormatException {
    days = null;
  }
  final owner = marketZoneOffsets[marketNumber(row['timezoneId'])?.toInt()];
  final allDay =
      (start?.startsWith('00:00') ?? false) &&
      (end?.startsWith('23:59') ?? false);
  if (owner != null &&
      start != null &&
      end != null &&
      days is List &&
      days.length == 7 &&
      days.every((v) => v == 0 || v == 1) &&
      !(allDay && days.every((v) => v == 1))) {
    final shifted = marketShiftWindow(
      [for (final v in days) v as int],
      start,
      end,
      ownerOffset: owner,
      localOffset: (localOffset ?? DateTime.now().timeZoneOffset).inMinutes,
    );
    if (shifted != null) {
      days = shifted.days;
      start = shifted.start;
      end = shifted.end;
    }
  }
  final english = marketLocale(context) == 'en';
  final labels = english
      ? ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
      : ['一', '二', '三', '四', '五', '六', '日'];
  final selected =
      days is List && days.length == 7 && days.every((v) => v == 0 || v == 1)
      ? [
          for (var i = 0; i < 7; i++)
            if (days[i] == 1) i,
        ]
      : <int>[];
  String day(int index) => '${english ? '' : '周'}${labels[index]}';
  String? dayLabel;
  if (selected.length == 7) {
    dayLabel = english ? 'Every day' : '每天';
  } else if (selected.join(',') == '0,1,2,3,4') {
    dayLabel = english ? 'Weekdays' : '工作日';
  } else if (selected.join(',') == '5,6') {
    dayLabel = english ? 'Weekends' : '周末';
  } else if (selected.isNotEmpty) {
    final ranges = <String>[];
    for (var i = 0; i < selected.length; i++) {
      final first = selected[i];
      var last = first;
      while (i + 1 < selected.length && selected[i + 1] == last + 1) {
        last = selected[++i];
      }
      ranges.add(
        first == last
            ? day(first)
            : '${day(first)}${english ? '–' : '至'}${day(last)}',
      );
    }
    dayLabel = ranges.join(english ? ', ' : '、');
  }
  final hours = start?.isNotEmpty == true && end?.isNotEmpty == true
      ? start!.startsWith('00:00') && end!.startsWith('23:59')
            ? (english ? 'All day' : '全天')
            : '$start–$end'
      : null;
  if (selected.isEmpty && hours == null) return marketText(context, 'notSet');
  return [?dayLabel, ?hours].join(' ');
}

String marketLocation(BuildContext context, MarketRow row) {
  final value =
      row[marketLocale(context) == 'hant'
          ? 'locationNameHant'
          : 'locationName'] ??
      row['locationName'];
  return value is String && value.isNotEmpty
      ? value
      : marketText(context, 'notFilled');
}

/// The trader's avatar or name opens their personal page (user 10-30). It needs
/// the Host's reference: names and avatars never identify a person. Without one
/// (your own listing, signed out, an older Host) the child stays plain.
class MarketTraderProfileLink extends StatelessWidget {
  const MarketTraderProfileLink(this.row, {required this.child, super.key});
  final MarketRow row;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final reference = row['traderRef'];
    final scope = UserInteractionScope.maybeOf(context);
    final port = scope?.port;
    final open = scope?.navigation.open;
    if (reference is! String ||
        reference.isEmpty ||
        port == null ||
        open == null ||
        marketIsMine(row)) {
      return child;
    }
    final label = marketText(context, 'traderProfile');
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      heightFactor: 1,
      child: StarBridgeTooltip(
        message: label,
        excludeFromSemantics: true,
        child: StarBridgeActionRow(
          controlKey: ValueKey(('market-trader-profile', reference)),
          semanticLabel: label,
          inheritContentStyle: true,
          baseRadius: 6,
          onActivate: (activation, _) => unawaited(
            open(
              activation,
              (_) => UserProfilePage(
                port: port,
                target: UserTarget('market', reference),
              ),
              'navigation.profile',
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class MarketTrader extends StatelessWidget {
  const MarketTrader(this.row, {this.compact = false, super.key});
  final bool compact;
  final MarketRow row;
  @override
  Widget build(BuildContext context) {
    final presence = row['presence'] as String? ?? 'unknown';
    final colors = context.tokens.colors;
    // Your own listing: say so plainly instead of showing your masked name.
    if (marketIsMine(row)) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            marketText(context, 'me'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 6),
          const MarketMineTag(),
        ],
      );
    }
    if (compact) {
      return Row(
        children: [
          Tooltip(
            message: marketText(context, presence),
            child: Semantics(
              label: marketText(context, presence),
              child: Text(
                '●',
                style: TextStyle(
                  color: presence == 'online' || presence == 'game'
                      ? colors.success
                      : colors.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              row['seller'] as String? ?? '',
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
            ),
          ),
          if (row['point'] != null) Text(' ★ ${row['point']}'),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MarketTraderProfileLink(
          row,
          child: Text(
            row['seller'] as String? ?? '—',
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
          ),
        ),
        Text(
          '● ${marketText(context, presence)}${row['point'] == null ? '' : ' · ★ ${row['point']}'}',
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: TextStyle(
            fontSize: context.tokens.typography.label,
            color: presence == 'online' || presence == 'game'
                ? colors.success
                : colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class MarketQualityBadge extends StatelessWidget {
  const MarketQualityBadge(this.row, {this.prefixed = false, super.key});
  final MarketRow row;
  final bool prefixed;
  @override
  Widget build(BuildContext context) {
    final quality = marketQuality(row);
    if (quality == null) return const SizedBox.shrink();
    final value = num.tryParse(quality.replaceAll('≥', ''))!;
    final t = context.tokens;
    final tier = MarketQualityTier.of(value).name;
    if (tier == 'legendary') {
      return Tooltip(
        message: marketText(context, tier),
        child: Semantics(
          label: '${marketText(context, tier)} $quality',
          excludeSemantics: true,
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: MarketSlantTag(
              prefixed ? marketText(context, 'quality') : '',
              color: t.domainColors.industry.foreground,
              mono: quality,
              foil: true,
            ),
          ),
        ),
      );
    }
    final fg = value >= 800
        ? t.domainColors.industry.foreground
        : value >= 600
        ? t.domainColors.recon.foreground
        : value >= 400
        ? t.colors.textSecondary
        : t.colors.textDisabled;
    final bg = value >= 800
        ? t.domainColors.industry.soft
        : value >= 600
        ? t.domainColors.recon.soft
        : t.surfaces.raised.fill;
    final label =
        '${prefixed ? '${marketText(context, 'quality')} ' : ''}$quality${value < 200 ? ' ${marketText(context, tier)}' : ''}';
    return Tooltip(
      message: marketText(context, tier),
      child: Semantics(
        label: '${marketText(context, tier)} $quality',
        excludeSemantics: true,
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          // The hall's slanted tag; tier colours unchanged.
          child: CustomPaint(
            painter: MarketParallelogramPainter(
              fill: Color.alphaBlend(fg.withValues(alpha: .1), bg),
              border: fg.withValues(alpha: .55),
            ),
            // Sized by its text: a Container with an alignment would fill
            // every loose width it is given (a Wrap row, a name column).
            child: Container(
              height: 20,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontFamily: t.typography.monoFamily,
                    fontSize: t.typography.label,
                    fontWeight: t.typography.emphasisWeight,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MarketPublished extends StatelessWidget {
  const MarketPublished(this.value, {super.key});
  final Object? value;
  @override
  Widget build(BuildContext context) {
    final milliseconds = value is num
        ? (value as num).toInt()
        : int.tryParse(value?.toString() ?? '');
    final date =
        milliseconds != null &&
            milliseconds >= 0 &&
            milliseconds < 8640000000000000
        ? DateTime.fromMillisecondsSinceEpoch(milliseconds)
        : DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return const SizedBox.shrink();
    final age = DateTime.now().difference(date).inMinutes.clamp(0, 52560000);
    final en = marketLocale(context) == 'en';
    final text = age < 1
        ? (en ? 'Just now' : '刚刚')
        : age < 60
        ? (en ? '${age}m ago' : '$age 分钟前')
        : age < 1440
        ? (en ? '${age ~/ 60}h ago' : '${age ~/ 60} 小时前')
        : (en ? '${age ~/ 1440}d ago' : '${age ~/ 1440} 天前');
    return Tooltip(
      message: date.toLocal().toString(),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
        style: TextStyle(
          fontSize: context.tokens.typography.label,
          color: context.tokens.colors.textSecondary,
        ),
      ),
    );
  }
}
