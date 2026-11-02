import 'community_tag_localization.dart';
import '../../design_system/icons/standard_icon.dart';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import 'community_creation_port.dart';
import 'community_gameplay_tags.dart';
import 'community_profile_rules.dart';
import 'community_profile_copy.dart';

import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_checkbox_tile.dart';
import '../../design_system/interaction/starbridge_choice_chip.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/interaction/starbridge_removable_chip_group.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';

/// Edits a private selection copy. Only Apply returns values to the caller.
class CommunityTagPicker extends StatefulWidget {
  const CommunityTagPicker({
    required this.options,
    required this.selected,
    this.profileQuotas = false,
    super.key,
  });
  final CommunityCreationOptions options;
  final List<String> selected;
  final bool profileQuotas;
  @override
  State<CommunityTagPicker> createState() => _CommunityTagPickerState();
}

class _CommunityTagPickerState extends State<CommunityTagPicker> {
  late final Set<String> selected = widget.selected.toSet();
  String? category;
  String query = '';
  final _searchFocus = FocusNode();
  InteractionSource? _selectionSource;
  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  String t(String key) => AppStrings.of(context).text('communities.$key');

  Color accent(String categoryId) => Color(
    0xff000000 |
        int.parse(
          widget.options.categories
              .firstWhere((c) => c.id == categoryId)
              .accentHex
              .substring(1),
          radix: 16,
        ),
  );

  @override
  Widget build(BuildContext context) {
    final quota = CommunityTagQuota(selected, widget.options.tags);
    final tags = widget.options.tags.where(
      (tag) =>
          (category == null || tag.categoryId == category) &&
          (query.isEmpty ||
              '${tag.name} ${tag.description}'.toLowerCase().contains(query)),
    );
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t('tagPicker.title'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                widget.profileQuotas
                    ? '${profileText(context, 'quotaCore')} ${quota.core}/3 · '
                          '${profileText(context, 'quotaStyle')} ${quota.reservedStyle}/2 · '
                          '${profileText(context, 'quotaShared')} ${quota.shared}/5'
                    : '${t('tagPicker.selected')} ${selected.length} / ${widget.options.maxTags}',
              ),
              if (widget.profileQuotas) Text(profileText(context, 'quotaHelp')),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 110),
                child: SingleChildScrollView(
                  child: StarBridgeRemovableChipGroup(
                    fallbackFocus: _searchFocus,
                    changeSource: _selectionSource,
                    onRemove: (id, source) => setState(() {
                      _selectionSource = source;
                      selected.remove(id.substring('selected-'.length));
                    }),
                    chips: [
                      for (final tag in widget.options.tags.where(
                        (t) => selected.contains(t.id),
                      ))
                        SuiteChipData(
                          id: 'selected-${tag.id}',
                          label: tag.localizedName(context),
                          removable: true,
                          removeLabel:
                              '${MaterialLocalizations.of(context).deleteButtonTooltip} ${tag.localizedName(context)}',
                          side: BorderSide(color: accent(tag.categoryId)),
                          backgroundColor: accent(tag.categoryId)
                              .withValues(alpha: .14),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              StarBridgeFieldFrame(
                focusNode: _searchFocus,
                builder: (_, focus) => TextField(
                  key: const Key('community-tag-search'),
                  focusNode: focus,
                  maxLength: 128,
                  decoration: InputDecoration(
                    labelText: t('tagPicker.search'),
                    counterText: '',
                    prefixIcon: const StandardIcon(StandardIconSemantic.search),
                  ),
                  onChanged: (text) =>
                      setState(() => query = text.trim().toLowerCase()),
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      StarBridgeChoiceChip(
                        controlKey: const Key('community-tag-all'),
                        label: t('tagPicker.all'),
                        selected: category == null,
                        onSelected: (_) => setState(() => category = null),
                      ),
                      for (final item in widget.options.categories)
                        StarBridgeTooltip(
                          message: item.localizedDescription(context),
                          child: StarBridgeChoiceChip(
                            controlKey: ValueKey('category-${item.id}'),
                            label: item.localizedName(context),
                            side: BorderSide(color: accent(item.id)),
                            selected: category == item.id,
                            onSelected: (_) =>
                                setState(() => category = item.id),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: tags.isEmpty
                    ? Center(child: Text(t('tagPicker.empty')))
                    : ListView(
                        children: [
                          for (final tag in tags)
                            StarBridgeCheckboxTile(
                              key: ValueKey('tag-${tag.id}'),
                              controlKey: ValueKey('tag-${tag.id}-control'),
                              label: tag.localizedName(context),
                              dense: false,
                              trailingControl: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              activeColor: accent(tag.categoryId),
                              titleWidget: CommunityGameplayTags(
                                value: tag.name,
                                options: widget.options,
                              ),
                              subtitle: tag.localizedDescription(context),
                              value: selected.contains(tag.id),
                              onChanged:
                                  !selected.contains(tag.id) &&
                                      (widget.profileQuotas
                                          ? !CommunityTagQuota(
                                              {...selected, tag.id},
                                              widget.options.tags,
                                            ).withinCapacity
                                          : selected.length >=
                                                widget.options.maxTags)
                                  ? null
                                  : (checked) => setState(() {
                                      _selectionSource =
                                          currentStarBridgeActivationSource;
                                      if (checked == true) {
                                        selected.add(tag.id);
                                      } else {
                                        selected.remove(tag.id);
                                      }
                                    }),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              OverflowBar(
                spacing: 8,
                overflowSpacing: 8,
                alignment: MainAxisAlignment.end,
                children: [
                  StarBridgeActionButton(
                    kind: StarBridgeActionKind.quiet,
                    controlKey: const Key('community-tag-clear'),
                    onActivate: (source) => setState(() {
                      _selectionSource = source;
                      selected.clear();
                    }),
                    child: Text(t('tagPicker.clear')),
                  ),
                  StarBridgeActionButton(
                    kind: StarBridgeActionKind.quiet,
                    controlKey: const Key('community-tag-cancel'),
                    onActivate: (source) =>
                        dismissStarBridgeDialog(context, source: source),
                    child: Text(t('cancel')),
                  ),
                  StarBridgeActionButton(
                    kind: StarBridgeActionKind.primary,
                    controlKey: const Key('community-tag-apply'),
                    onActivate: widget.profileQuotas && !quota.valid
                        ? null
                        : (source) => dismissStarBridgeDialog(
                            context,
                            source: source,
                            result: List<String>.unmodifiable(
                              widget.options.tags
                                  .where((t) => selected.contains(t.id))
                                  .map((t) => t.id),
                            ),
                          ),
                    child: Text(t('applyFilters')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
