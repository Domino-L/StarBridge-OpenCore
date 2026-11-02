import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_choice_chip.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

/// Who sees the main-fleet fields (user option A, 2026-10-28): every member,
/// or members at or above a star level. Values are SCM rank values (1 is the
/// leader; stars = 6 - value), null for everyone.
class OfficialFleetAudiencePicker extends StatelessWidget {
  const OfficialFleetAudiencePicker({
    required this.value,
    required this.onChanged,
    this.keyPrefix = 'official-fleet-audience',
    super.key,
  });

  final int? value;
  final ValueChanged<int?>? onChanged;
  final String keyPrefix;

  static const values = <int?>[null, 4, 3, 2, 1];

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    String label(int? rank) {
      if (rank == null) return strings.text('privacy.official.audience.all');
      final stars = '★' * (6 - rank);
      return strings
          .text(
            rank == 1
                ? 'privacy.official.audience.leader'
                : 'privacy.official.audience.atLeast',
          )
          .replaceAll('{stars}', stars);
    }

    return Wrap(
      spacing: tokens.space.sm,
      runSpacing: tokens.space.xs,
      children: [
        for (final rank in values)
          StarBridgeChoiceChip(
            controlKey: Key('$keyPrefix-${rank ?? 'all'}'),
            label: label(rank),
            selected: value == rank,
            onSelected: onChanged == null ? null : (_) => onChanged!(rank),
          ),
      ],
    );
  }
}
