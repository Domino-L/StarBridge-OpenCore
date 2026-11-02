import 'package:flutter/material.dart';

import '../design_system/interaction/starbridge_select_form_field.dart';
import '../design_system/tokens/starbridge_tokens.dart';

/// The one way to pick a time of day (user decision 2026-10-22, "时和分应该
/// 分开"): an hour list and a minute list, never a text box. Minutes come in
/// quarter hours; a stored value off that grid stays as a "current" option so
/// opening and saving never moves it. Values are SCM's `HH:mm`.
const clockMinuteSteps = [0, 15, 30, 45];

/// Minutes since midnight for `HH:mm`, or -1 for anything else.
int clockMinutes(String? value) {
  final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$')
      .firstMatch(value?.trim() ?? '');
  return match == null ? -1 : int.parse(match[1]!) * 60 + int.parse(match[2]!);
}

String clockText(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

/// 12-hour lists only where the reader's locale and system use them.
bool clockUses12Hour(BuildContext context) =>
    Localizations.localeOf(context).languageCode != 'zh' &&
    !MediaQuery.alwaysUse24HourFormatOf(context) &&
    switch (MaterialLocalizations.of(context).timeOfDayFormat()) {
      TimeOfDayFormat.h_colon_mm_space_a ||
      TimeOfDayFormat.a_space_h_colon_mm => true,
      _ => false,
    };

int _language(BuildContext context) {
  final locale = Localizations.localeOf(context);
  if (locale.languageCode != 'zh') return 2;
  return locale.scriptCode == 'Hant' ||
          locale.countryCode == 'TW' ||
          locale.countryCode == 'HK'
      ? 1
      : 0;
}

const _copy = <String, List<String>>{
  'hour': ['时', '時', 'Hour'],
  'minute': ['分', '分', 'Min'],
  'nextDay': ['次日', '次日', 'next day'],
  'nextDayShort': ['次日', '次日', '+1'],
  'current': ['当前', '目前', 'current'],
  'total': ['共 {d}', '共 {d}', '{d} total'],
  'overnight': ['，跨天', '，跨日', ', overnight'],
  'under': ['不足 {d}', '不足 {d}', 'under {d}'],
  'hours': ['{h} 小时', '{h} 小時', '{h} h'],
  'minutes': ['{m} 分钟', '{m} 分鐘', '{m} min'],
};

String clockCopy(
  BuildContext context,
  String key, [
  Map<String, String> args = const {},
]) {
  var text = _copy[key]![_language(context)];
  for (final entry in args.entries) {
    text = text.replaceAll('{${entry.key}}', entry.value);
  }
  return text;
}

/// "1 小时 15 分钟" / "1 h 15 min"; also used for duration presets.
String clockDuration(BuildContext context, int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  return [
    if (h > 0) clockCopy(context, 'hours', {'h': '$h'}),
    if (m > 0 || h == 0) clockCopy(context, 'minutes', {'m': '$m'}),
  ].join(' ');
}

/// How one candidate time shows in a range's end lists.
typedef ClockOption = ({bool nextDay, String? note, bool enabled});

/// An hour list and a minute list for one `HH:mm` value.
/// An unreadable value shows empty lists with 时 / 分 hints; the form decides
/// whether that may be saved.
class StarBridgeClockField extends StatelessWidget {
  const StarBridgeClockField({
    required this.value,
    required this.onChanged,
    required this.keyPrefix,
    this.describe,
    super.key,
  });
  final String value;

  /// Null disables the field.
  final ValueChanged<String>? onChanged;

  /// The lists are keyed '$keyPrefix-hour' and '$keyPrefix-minute' (their
  /// tap targets add '-control'; menu rows are `(identity, value)`).
  final String keyPrefix;

  /// For a range end: marks next-day times, notes the length and greys out
  /// times the range does not allow.
  final ClockOption Function(int minutes)? describe;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final clock = clockMinutes(value);
    final hour = clock < 0 ? null : clock ~/ 60;
    final minute = clock < 0 ? null : clock % 60;
    final twelve = clockUses12Hour(context);
    final minutes = [
      if (minute != null && !clockMinuteSteps.contains(minute)) minute,
      ...clockMinuteSteps,
    ];
    ClockOption option(int at) =>
        describe?.call(at) ?? (nextDay: false, note: null, enabled: true);
    // An hour is open when any listed minute fits; its note uses the current
    // minute when that fits, else the first minute that does.
    int? fitting(int h) {
      for (final m in [?minute, ...minutes]) {
        if (option(h * 60 + m).enabled) return m;
      }
      return null;
    }

    void pick(int h, int? m) {
      final keep = m ?? minute ?? 0;
      final next = option(h * 60 + keep).enabled ? keep : fitting(h) ?? keep;
      onChanged?.call(clockText(h * 60 + next));
    }

    Widget tag(String text) => Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        border: Border.all(color: t.colors.warning.withValues(alpha: .55)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(fontSize: 10.5, color: t.colors.warning, height: 1.5),
      ),
    );
    Widget row(String label, ClockOption o, {String? extra}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(color: o.enabled ? null : t.colors.textDisabled),
        ),
        if (o.nextDay) tag(clockCopy(context, 'nextDay')),
        if (extra != null || o.note != null) ...[
          const SizedBox(width: 14),
          Text(
            extra ?? o.note!,
            style: TextStyle(
              fontSize: 11.5,
              color: o.enabled ? t.colors.textSecondary : t.colors.textDisabled,
            ),
          ),
        ],
      ],
    );
    String two(int n) => n.toString().padLeft(2, '0');
    // 12-hour locales read the period in the hour list itself ("01 PM"), so a
    // time is always two lists and fits narrow forms.
    final period = MaterialLocalizations.of(context);
    String hourLabel(int h) => twelve
        ? '${h % 12 == 0 ? 12 : h % 12} ${h < 12 ? period.anteMeridiemAbbreviation : period.postMeridiemAbbreviation}'
        : two(h);
    ClockOption hourOption(int h) {
      final m = fitting(h);
      final o = option(h * 60 + (m ?? minute ?? 0));
      return (nextDay: o.nextDay, note: o.note, enabled: m != null);
    }

    Widget select<V>({
      required String list,
      required V? current,
      required List<V> values,
      required String Function(V) label,
      required ClockOption Function(V) describeValue,
      required ValueChanged<V> onPick,
      String? hint,
    }) => StarBridgeSelectFormField<V>(
      identity: '$keyPrefix-$list',
      controlKey: ValueKey('$keyPrefix-$list-control'),
      key: ValueKey('$keyPrefix-$list'),
      semanticLabel: hint,
      initialValue: current,
      isExpanded: true,
      menuFitsContent: true,
      hint: hint == null ? null : Text(hint),
      decoration: const InputDecoration(isDense: true),
      optionLabel: (item) => label(item.value as V),
      selectedItemBuilder: (_) => [
        for (final v in values)
          Row(
            children: [
              Flexible(
                child: Text(
                  label(v),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                ),
              ),
              if (describeValue(v).nextDay)
                tag(clockCopy(context, 'nextDayShort')),
            ],
          ),
      ],
      items: [
        for (final v in values)
          DropdownMenuItem(
            value: v,
            enabled: describeValue(v).enabled,
            child: row(
              label(v),
              describeValue(v),
              extra:
                  list == 'minute' &&
                      v == minute &&
                      minutes.first == v &&
                      !clockMinuteSteps.contains(v)
                  ? clockCopy(context, 'current')
                  : null,
            ),
          ),
      ],
      onChanged: onChanged == null
          ? null
          : (v) {
              if (v != null) onPick(v);
            },
    );

    return Row(
      children: [
        Expanded(
          child: select<int>(
            list: 'hour',
            current: hour,
            values: [for (var h = 0; h < 24; h++) h],
            label: hourLabel,
            describeValue: hourOption,
            onPick: (h) => pick(h, null),
            hint: clockCopy(context, 'hour'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Text(
            ':',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: t.colors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: select<int>(
            list: 'minute',
            current: minute,
            values: minutes,
            label: two,
            describeValue: (m) => hour == null
                ? (nextDay: false, note: null, enabled: true)
                : (() {
                    final o = option(hour * 60 + m);
                    return (nextDay: false, note: o.note, enabled: o.enabled);
                  })(),
            onPick: (m) => pick(hour ?? 0, m),
            hint: clockCopy(context, 'minute'),
          ),
        ),
      ],
    );
  }
}

/// A start–end pair. Ends at or before the start run into the next day
/// (marked 次日); ends that leave the range shorter than [minMinutes] are
/// greyed out. Equal times mean a full day only where [allowFullDay].
class StarBridgeTimeRangeField extends StatelessWidget {
  const StarBridgeTimeRangeField({
    required this.start,
    required this.end,
    required this.onChanged,
    required this.keyPrefix,
    required this.startLabel,
    required this.endLabel,
    this.minMinutes = 1,
    this.allowFullDay = true,
    this.showSummary = true,
    super.key,
  });
  final String start, end, startLabel, endLabel, keyPrefix;
  final void Function(String start, String end)? onChanged;
  final int minMinutes;
  final bool allowFullDay, showSummary;

  /// Length of [start]–[end] in minutes, or null when either is unreadable.
  static int? length(String start, String end, {bool allowFullDay = true}) {
    final s = clockMinutes(start), e = clockMinutes(end);
    if (s < 0 || e < 0) return null;
    if (e == s) return allowFullDay ? 1440 : 0;
    return (e - s + 1440) % 1440;
  }

  @override
  Widget build(BuildContext context) {
    final s = clockMinutes(start);
    final total = length(start, end, allowFullDay: allowFullDay);
    final label = TextStyle(
      fontSize: 12,
      color: context.tokens.colors.textSecondary,
    );
    Widget side(String text, Widget field) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(text, style: label),
        const SizedBox(height: 4),
        field,
      ],
    );
    final from = side(
      startLabel,
      StarBridgeClockField(
        value: start,
        keyPrefix: '$keyPrefix-start',
        onChanged: onChanged == null ? null : (v) => onChanged!(v, end),
      ),
    );
    final to = side(
      endLabel,
      StarBridgeClockField(
        value: end,
        keyPrefix: '$keyPrefix-end',
        onChanged: onChanged == null ? null : (v) => onChanged!(start, v),
        describe: s < 0
            ? null
            : (at) {
                final d = length(
                  start,
                  clockText(at),
                  allowFullDay: allowFullDay,
                )!;
                final ok = d >= minMinutes;
                return (
                  nextDay: at <= s,
                  note: ok
                      ? clockCopy(context, 'total', {
                          'd': clockDuration(context, d),
                        })
                      : clockCopy(context, 'under', {
                          'd': clockDuration(context, minMinutes),
                        }),
                  enabled: ok,
                );
              },
      ),
    );
    return LayoutBuilder(
      builder: (context, box) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (box.maxWidth < 360) ...[
            from,
            const SizedBox(height: 10),
            to,
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: from),
                const SizedBox(width: 14),
                Expanded(child: to),
              ],
            ),
          if (showSummary && total != null && total >= minMinutes) ...[
            const SizedBox(height: 6),
            Text(
              '${clockCopy(context, 'total', {'d': clockDuration(context, total)})}'
              '${clockMinutes(end) <= s ? clockCopy(context, 'overnight') : ''}',
              key: ValueKey('$keyPrefix-summary'),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}
