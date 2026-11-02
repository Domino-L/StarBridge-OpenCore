import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../design_system/icons/native_dropdown_indicator_icon.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_choice_chip.dart';
import '../../design_system/interaction/starbridge_expansion_tile.dart';
import '../../design_system/interaction/starbridge_select_form_field.dart';

import 'marketplace_controller.dart';
import 'marketplace_details.dart';
import 'marketplace_port.dart';
import 'marketplace_trade_feedback.dart';
import 'marketplace_trade_profile_copy.dart';
import 'marketplace_trade_profile_model.dart';
import 'marketplace_states.dart' show marketButtonAction;
import '../../shared/clock_field.dart';

Future<MarketRow?> editTradeProfile(
  BuildContext context,
  MarketplaceController market, {
  String? missing,
}) async {
  final port = market.port;
  if (port is! MarketplaceTradeProfilePort) return null;
  final revision = market.contextRevision;
  return tradeMotionDialog<MarketRow>(
    context,
    (_) => TradeProfileForm(
      read: () => (port as MarketplaceTradeProfilePort).tradeProfile(),
      write: (changes) =>
          (port as MarketplaceTradeProfilePort).tradeProfile(changes),
      zones: () async => (await port.read('timezones')).rows,
      current: () => market.contextRevision == revision,
      login: market.login == null ? null : () => market.login!(context),
      missing: missing,
    ),
  );
}

class TradeProfileForm extends StatefulWidget {
  const TradeProfileForm({
    super.key,
    required this.read,
    required this.write,
    required this.zones,
    required this.current,
    this.login,
    this.missing,
  });
  final Future<MarketRow> Function() read;
  final Future<MarketRow> Function(MarketRow) write;
  final Future<List<MarketRow>> Function() zones;
  final bool Function() current;
  final Future<void> Function()? login;
  final String? missing;
  @override
  State<TradeProfileForm> createState() => _TradeProfileFormState();
}

class _TradeProfileFormState extends State<TradeProfileForm> {
  final contact = TextEditingController(), mark = TextEditingController();
  String start = '', end = '';
  MarketRow original = {};
  List<int> days = List.filled(7, 0);
  List<MarketRow> zones = [];
  int? zone;
  String? language, error;
  bool loading = true, saving = false, saved = false, uncertain = false;
  bool readFailed = false;
  bool get current => mounted && widget.current();
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    for (final c in [contact, mark]) {
      c.dispose();
    }
    super.dispose();
  }

  void apply(MarketRow row) {
    original = row;
    days =
        (row['tradeTime'] as List?)?.map((v) => v == 1 ? 1 : 0).toList() ??
        List.filled(7, 0);
    start = row['tradeStartTime']?.toString() ?? '';
    end = row['tradeEndTime']?.toString() ?? '';
    contact.text = row['userMobile']?.toString() ?? '';
    mark.text = row['mark']?.toString() ?? '';
    zone = marketNumber(row['timezoneId'])?.toInt();
    language = row['language']?.toString();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
      readFailed = false;
    });
    try {
      final value = await widget.read();
      final choices = await widget.zones();
      if (!current) return;
      setState(() {
        apply(value);
        zones = choices;
        marketRememberZones(choices);
        uncertain = false;
      });
    } catch (e) {
      if (current) {
        setState(
          () {
            error = e is MarketplaceTradeError ? e.code : 'marketplace.unavailable';
            readFailed = true;
          },
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
          if (!widget.current()) error = 'marketplace.context_changed';
        });
      }
    }
  }

  MarketRow get draft => {
    'tradeTime': days,
    'tradeStartTime': start,
    'tradeEndTime': end,
    'timezoneId': zone,
    'userMobile': contact.text,
    'mark': mark.text,
    if (language != null) 'language': language,
  };
  Future<void> save() async {
    if (saving || uncertain || !current) return;
    final problem = tradeProfileValidation(draft);
    if (problem != null) {
      setState(() => error = problem);
      return;
    }
    setState(() {
      saving = true;
      error = null;
      readFailed = false;
    });
    try {
      final result = await widget.write(tradeProfileChanges(original, draft));
      if (!current) return;
      final actual = result['profile'];
      if (actual is! Map) {
        throw const MarketplaceTradeError('trade_profile.unknown');
      }
      setState(() {
        apply(Map<String, Object?>.from(actual));
        saved = result['confirmed'] == true;
        uncertain = !saved;
        if (uncertain) error = 'trade_profile.unknown';
      });
    } catch (e) {
      if (current) {
        setState(() {
          error = e is MarketplaceTradeError ? e.code : 'trade_profile.unknown';
          uncertain =
              error == 'trade_profile.unknown' ||
              error == 'marketplace.unavailable';
          if (uncertain) error = 'trade_profile.unknown';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          saving = false;
          if (!widget.current()) error = 'marketplace.context_changed';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    String text(String key) => tradeProfileText(context, key);
    Widget field(String key, TextEditingController controller) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(text(key)),
        const SizedBox(height: 6),
        TextField(
          key: ValueKey('trade-profile-$key'),
          controller: controller,
          enabled: !saving && !saved,
          decoration: InputDecoration(hintText: text(key)),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
    final scheme = Theme.of(context).colorScheme;
    // Primary fill keeps picked days obvious in both themes.
    Widget dayChip(String label, bool selected, ValueChanged<bool>? onSelected) =>
        StarBridgeChoiceChip.filter(
          controlKey: ValueKey(('trade-profile-day', label)),
          showCheckmark: false,
          label: label,
          foregroundColor: selected ? scheme.onPrimary : null,
          selectedColor: scheme.primary,
          selected: selected,
          onSelected: onSelected,
        );
    final hours = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(text('days')),
        Wrap(
          spacing: 4,
          children: [
            dayChip(
              text('daily'),
              days.every((v) => v == 1),
              saving || saved
                  ? null
                  : (v) => setState(() => days = List.filled(7, v ? 1 : 0)),
            ),
            for (final (i, day) in [
              'mon',
              'tue',
              'wed',
              'thu',
              'fri',
              'sat',
              'sun',
            ].indexed)
              dayChip(
                text(day),
                days[i] == 1,
                saving || saved
                    ? null
                    : (v) => setState(() => days[i] = v ? 1 : 0),
              ),
          ],
        ),
        const SizedBox(height: 10),
        // Picked, never typed (user decision 2026-10-22); SCM's rules stay:
        // at least an hour, overnight allowed.
        StarBridgeTimeRangeField(
          keyPrefix: 'trade-profile-time',
          start: start,
          end: end,
          startLabel: text('start'),
          endLabel: text('end'),
          minMinutes: 60,
          allowFullDay: false,
          onChanged: saving || saved
              ? null
              : (s, e) => setState(() {
                  start = s;
                  end = e;
                }),
        ),
        const SizedBox(height: 6),
        Text(text('duration'), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 14),
        Text(text('zone')),
        const SizedBox(height: 6),
        StarBridgeSelectFormField<int>(
          identity: 'trade-profile-zone',
          controlKey: const Key('trade-profile-zone'),
          initialValue: zones.any((r) => r['id'] == zone) ? zone : null,
          key: ValueKey('zone-$zone-${zones.length}'),
          isExpanded: true,
          decoration: InputDecoration(hintText: text('zone')),
          items: [
            for (final r in zones)
              if (marketNumber(r['id']) != null)
                DropdownMenuItem(
                  value: marketNumber(r['id'])!.toInt(),
                  child: Text(
                    '${r['name'] ?? r['label'] ?? r['id']}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
          ],
          onChanged: saving || saved ? null : (v) => setState(() => zone = v),
        ),
        const SizedBox(height: 6),
        Text(
          '${text('local')}: ${marketZoneOffsets.containsKey(zone) ? marketTradeTime(context, draft) : text('zoneUnknown')}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
    final contacts = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        field('contact', contact),
        const SizedBox(height: 6),
        Text(text('public'), style: Theme.of(context).textTheme.bodySmall),
      ],
    );
    final blocked = widget.missing != null;
    // Keeps the native ExpansionTile face: ListTile header, trailing turning
    // indicator and the 1px edge above and below.
    Widget fold(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: StarBridgeExpansionTile(
        title: title,
        headerMinHeight: 0,
        headerBuilder: (context, _, open) => ListTile(
          title: Text(title),
          trailing: Transform.rotate(
            angle: math.pi * open,
            child: const NativeDropdownIndicatorIcon.expandMore(),
          ),
        ),
        children: children,
      ),
    );
    // SCM reports one missing item at a time (hours before contact), so open
    // every section the read-back profile shows as incomplete, plus the one
    // a validation error points at; otherwise a save fails inside a folded tile.
    final contactIncomplete =
        (original['userMobile']?.toString().trim().length ?? 0) < 5;
    final hoursIncomplete =
        tradeProfileValidation({...original, 'userMobile': '-----'}) != null;
    final showHours =
        !blocked ||
        widget.missing == 'marketplace.trade_time_required' ||
        hoursIncomplete ||
        const {
          'trade_profile.no_day',
          'trade_profile.time_range',
          'trade_profile.timezone_invalid',
        }.contains(error);
    final showContact =
        !blocked ||
        widget.missing == 'marketplace.contact_required' ||
        contactIncomplete ||
        error == 'trade_profile.contact_invalid';
    return PopScope(
      canPop: !saving,
      child: AlertDialog(
        title: Text(text(blocked ? 'prepare' : 'title')),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading) const LinearProgressIndicator(),
                if (!loading && original.isNotEmpty) ...[
                  if (blocked) Text(text('noAutoTrade')),
                  if (saved) Text(text('saved')),
                  if (showHours)
                    hours
                  else
                    fold(text('days'), [hours]),
                  if (showContact)
                    contacts
                  else
                    fold(text('contact'), [contacts]),
                  fold(text('more'), [
                    field('mark', mark),
                    StarBridgeSelectFormField<String>(
                      identity: 'trade-profile-language',
                      controlKey: const Key('trade-profile-language'),
                      initialValue: ['0', '1'].contains(language)
                          ? language
                          : null,
                      decoration: InputDecoration(
                        labelText: text('language'),
                      ),
                      items: [
                        DropdownMenuItem(value: '0', child: Text(text('zh'))),
                        DropdownMenuItem(value: '1', child: Text(text('en'))),
                      ],
                      onChanged: saving || saved
                          ? null
                          : (v) => setState(() => language = v),
                    ),
                  ]),
                ],
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      tradeProfileErrorText(context, error!, reading: readFailed),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (tradeProfileNeedsReauthorize(error))
                  marketButtonAction(TextButton(
                    onPressed: saving ? null : widget.login,
                    child: Text(text('reauthorize')),
                  ), key: const Key('market-trade-profile-login')),
              ],
            ),
          ),
        ),
        actions: [
          marketButtonAction(TextButton(
            onPressed: saving
                ? null
                : () => dismissStarBridgeDialog<MarketRow>(
                    context,
                    source: StarBridgeActivationOrigin.sourceOf(context),
                    result: saved && widget.current() ? original : null,
                  ),
            child: Text(text(saved ? 'done' : 'cancel')),
          ), key: const Key('market-trade-profile-close')),
          if (!saved)
            marketButtonAction(TextButton(
              onPressed: loading || saving || !widget.current() ? null : load,
              child: Text(text('retry')),
            ), key: const Key('market-trade-profile-reload')),
          if (!saved)
            marketButtonAction(FilledButton(
              onPressed:
                  loading ||
                      saving ||
                      uncertain ||
                      original.isEmpty ||
                      !widget.current()
                  ? null
                  : save,
              child: Text(text(saving ? 'saving' : 'save')),
            ), key: const Key('market-trade-profile-save')),
        ],
      ),
    );
  }
}
