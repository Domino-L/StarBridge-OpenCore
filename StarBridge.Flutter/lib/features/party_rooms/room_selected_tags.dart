import '../../app/localization/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart'
    show SuiteChipData;

import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/interaction/starbridge_removable_chip_group.dart';
import 'party_rooms_module.dart';
import 'room_tag_catalog.dart';
import 'room_tag_colors.dart';

/// Presentation only. Consumers retain their distinct raw/normalised ID rules.
class RoomSelectedTags extends StatelessWidget {
  const RoomSelectedTags({
    required this.tags,
    required this.onRemove,
    this.changeSource,
    this.fallbackFocus,
    super.key,
  });
  final Iterable<RoomTag> tags;
  final void Function(String id, InteractionSource source) onRemove;
  final InteractionSource? changeSource;
  final FocusNode? fallbackFocus;
  static const _prefix = 'selected-tag-';

  @override
  Widget build(BuildContext context) => StarBridgeRemovableChipGroup(
    changeSource: changeSource,
    fallbackFocus: fallbackFocus,
    onRemove: (id, source) => onRemove(id.substring(_prefix.length), source),
    chips: [
      for (final tag in RoomTagCatalog.ordered(tags))
        SuiteChipData(
          id: '$_prefix${tag.id}',
          label: RoomTagCatalog.fullText(tag, strings: AppStrings.of(context)),
          removable: true,
          backgroundColor: roomTagColors(context, tag.id).soft,
          foregroundColor: roomTagColors(context, tag.id).foreground,
          removeLabel:
              '${MaterialLocalizations.of(context).deleteButtonTooltip} ${RoomTagCatalog.fullText(tag, strings: AppStrings.of(context))}',
        ),
    ],
  );
}
