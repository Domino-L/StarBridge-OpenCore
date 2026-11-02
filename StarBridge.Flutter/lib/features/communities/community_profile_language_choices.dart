import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_choice_chip.dart';
import 'community_profile_copy.dart';

/// Choices only. Permission and persistence remain with the original editor.
class CommunityProfileLanguageChoices extends StatelessWidget {
  const CommunityProfileLanguageChoices({
    required this.value,
    required this.enabled,
    required this.onChanged,
    super.key,
  });
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    String t(String key) => profileText(context, key);
    final chosen = value
        .split(RegExp(r'\s*[/,，;；、]\s*'))
        .where((v) => v.isNotEmpty)
        .toSet();
    final choices = {
      ...const [
        '中文',
        'English',
        '日本語',
        '한국어',
        'Deutsch',
        'Français',
        'Español',
        'Русский',
        'Português',
      ],
      ...chosen,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('language'), style: Theme.of(context).textTheme.titleMedium),
          Text(
            t('languagesHint'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in choices)
                StarBridgeChoiceChip.filter(
                  controlKey: ValueKey('profile-language-$value'),
                  label: value,
                  selected: chosen.contains(value),
                  onSelected: !enabled
                      ? null
                      : (yes) {
                          yes ? chosen.add(value) : chosen.remove(value);
                          onChanged(chosen.join(' / '));
                        },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
