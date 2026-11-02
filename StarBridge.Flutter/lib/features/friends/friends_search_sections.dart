import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

/// One row of a search with the bands around it: friends the search also
/// applies to first, then everyone else.
final class FriendsSearchEntry extends StatelessWidget {
  const FriendsSearchEntry({
    super.key,
    required this.index,
    required this.matched,
    required this.total,
    required this.child,
  });

  final int index, matched, total;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    String t(String key) => AppStrings.of(context).text('friends.$key');
    final others = total - matched;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (index == 0 && matched > 0)
          _band(context, t('searchFriends'), matched, quiet: true),
        if (index == matched)
          _band(
            context,
            t(matched > 0 ? 'searchOthers' : 'searchResults'),
            others,
          ),
        child,
        if (matched > 0 && others == 0 && index == total - 1) ...[
          const SizedBox(height: 10),
          _band(context, t('searchOthers'), 0),
          Text(t('noOthers')),
          const SizedBox(height: 8),
          Text(t('searchRule'), style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }

  Widget _band(
    BuildContext context,
    String label,
    int count, {
    bool quiet = false,
  }) {
    final colors = context.tokens.colors;
    final color = quiet ? colors.textSecondary : colors.accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text('$label · $count', style: TextStyle(color: color)),
    );
  }
}

/// A search that found nobody: says so, and why someone may not be findable.
String friendsSearchEmptyMessage(AppStrings strings, String query) =>
    '${strings.text('friends.noneFound').replaceAll('{query}', query)}\n'
    '${strings.text('friends.searchRule')}';
