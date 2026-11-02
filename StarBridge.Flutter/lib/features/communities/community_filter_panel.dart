import 'community_tag_localization.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_checkbox_tile.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_expansion_tile.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/interaction/starbridge_removable_chip_group.dart';
import 'community_tag_picker.dart';
import 'legacy_community_tag_catalog.dart';

const communityFilterGroups = <String, List<String>>{
  'join': ['direct', 'application', 'inviteOnly'],
  'status': ['recruiting', 'pending'],
  'scale': ['small', 'medium', 'large', 'veryLarge'],
  'targets': ['所有玩家', '新手友好', '战斗玩家', '工业玩家', '贸易与货运', '医疗与支援'],
  'cadence': ['休闲', '固定开黑', '周末行动', '高频组织', '大型行动前通知'],
  'period': ['night', 'morning', 'afternoon', 'evening'],
  'days': ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
  'ships': ['small', 'medium', 'large', 'veryLarge'],
  'roles': [
    'combat',
    'industrial',
    'transport',
    'exploration',
    'support',
    'utility',
  ],
  'systems': ['Stanton', 'Pyro', 'Nyx'],
};

class CommunityFilterPanel extends StatefulWidget {
  const CommunityFilterPanel({
    this.value,
    required this.onApply,
    this.invalidations,
    super.key,
  });
  final String? value;
  final ValueChanged<String> onApply;
  final Stream<void>? invalidations;
  @override
  State<CommunityFilterPanel> createState() => _CommunityFilterPanelState();
}

class _CommunityFilterPanelState extends State<CommunityFilterPanel> {
  final language = TextEditingController();
  Map<String, dynamic> draft = {};
  StreamSubscription<void>? subscription;
  StarBridgeDialogRoute<List<String>>? picker;
  final languageFocus = FocusNode(debugLabel: 'community-filter-language');
  InteractionSource? tagSource;
  bool invalidated = false;
  String t(String key) => AppStrings.of(context).text('communities.$key');
  @override
  void initState() {
    super.initState();
    draft = widget.value == null
        ? {}
        : Map<String, dynamic>.from(jsonDecode(widget.value!));
    language.text = draft['language'] as String? ?? '';
    subscription = widget.invalidations?.listen((_) {
      invalidated = true;
      closePicker();
    });
  }

  @override
  void dispose() {
    language.dispose();
    languageFocus.dispose();
    unawaited(subscription?.cancel());
    closePicker();
    super.dispose();
  }

  void apply() {
    if (invalidated) return;
    draft['language'] = language.text.trim();
    draft['offset'] = DateTime.now().timeZoneOffset.inMinutes;
    widget.onApply(jsonEncode(draft));
  }

  Future<void> chooseTags() async {
    if (invalidated || picker != null) return;
    final current = List<String>.from(draft['tags'] as List? ?? []);
    final selected = await showStarBridgeDialog<List<String>>(
      context,
      builder: (_) => CommunityTagPicker(
        options: LegacyCommunityTagCatalog.options,
        selected: [
          for (final tag in LegacyCommunityTagCatalog.tags)
            if (current.contains(tag.name) || current.contains(tag.id)) tag.id,
        ],
      ),
      onRouteCreated: (route) => picker = route,
    );
    picker = null;
    if (!mounted || invalidated || selected == null) return;
    // The existing directory wire contract filters public tag names, not IDs.
    tagSource = currentStarBridgeActivationSource;
    setState(
      () => draft['tags'] = [
        for (final tag in LegacyCommunityTagCatalog.tags)
          if (selected.contains(tag.id)) tag.name,
      ],
    );
  }

  void closePicker() {
    retireStarBridgeDialog(picker);
  }

  @override
  Widget build(BuildContext context) => Material(
    color: context.tokens.surfaces.panel.fill,
    shape: RoundedRectangleBorder(
      side: BorderSide(color: context.tokens.surfaces.panel.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  t('filters'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              StarBridgeActionButton(
                kind: StarBridgeActionKind.quiet,
                controlKey: const Key('community-filter-reset'),
                onActivate: (_) {
                  if (invalidated) return;
                  setState(() {
                    draft = {};
                    language.clear();
                  });
                  widget.onApply('{}');
                },
                child: Text(t('reset')),
              ),
              StarBridgeActionButton(
                kind: StarBridgeActionKind.primary,
                controlKey: const Key('community-filter-apply'),
                onActivate: (_) => apply(),
                child: Text(t('applyFilters')),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              for (final group in communityFilterGroups.entries)
                StarBridgeExpansionTile(
                  key: ValueKey('org-filter-${group.key}'),
                  initiallyExpanded: const [
                    'join',
                    'status',
                    'scale',
                  ].contains(group.key),
                  title: t('filter.${group.key}'),
                  titleStyle: Theme.of(context).textTheme.bodyMedium,
                  headerPadding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    if (group.key == 'period') ...[
                      StarBridgeCheckboxTile(
                        controlKey: const Key('community-filter-same-zone'),
                        label: t('sameZone'),
                        trailingControl: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                        dense: true,
                        titleWidget: Text(
                          t('sameZone'),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        value: draft['sameZone'] == true,
                        onChanged: (v) => setState(() => draft['sameZone'] = v),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          t('periodHint'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                    for (final option in group.value)
                      StarBridgeCheckboxTile(
                        controlKey: ValueKey(
                          'community-filter-${group.key}-$option',
                        ),
                        label: t('option.${group.key}.$option'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                        dense: true,
                        titleWidget: Text(
                          t('option.${group.key}.$option'),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        value: ((draft[group.key] as List?) ?? []).contains(
                          option,
                        ),
                        onChanged: (v) => setState(() {
                          final values = List<String>.from(
                            (draft[group.key] as List?) ?? [],
                          );
                          v == true
                              ? values.add(option)
                              : values.remove(option);
                          draft[group.key] = values;
                        }),
                      ),
                  ],
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    StarBridgeFieldFrame(
                      focusNode: languageFocus,
                      builder: (_, focus) => TextField(
                        focusNode: focus,
                        controller: language,
                        maxLength: 128,
                        decoration: InputDecoration(
                          labelText: t('language'),
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: StarBridgeActionButton(
                        controlKey: const ValueKey('choose-filter-tags'),
                        onActivate: (_) => chooseTags(),
                        child: Text(t('tagPicker.title')),
                      ),
                    ),
                    StarBridgeRemovableChipGroup(
                      fallbackFocus: languageFocus,
                      changeSource: tagSource,
                      onRemove: (id, source) => setState(() {
                        tagSource = source;
                        draft['tags'] = List<String>.from(draft['tags'] as List)
                          ..remove(id.substring('filter-tag-'.length));
                      }),
                      chips: [
                        for (final name in List<String>.from(
                          draft['tags'] as List? ?? [],
                        ))
                          SuiteChipData(
                            id: 'filter-tag-$name',
                            label: communityTagDisplayName(context, name),
                            removable: true,
                            removeLabel:
                                '${MaterialLocalizations.of(context).deleteButtonTooltip} ${communityTagDisplayName(context, name)}',
                          ),
                      ],
                    ),
                    StarBridgeCheckboxTile(
                      controlKey: const Key('community-filter-all-tags'),
                      label: t('allTags'),
                      trailingControl: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      dense: true,
                      titleWidget: Text(
                        t('allTags'),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      value: draft['allTags'] == true,
                      onChanged: (v) => setState(() => draft['allTags'] = v),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
