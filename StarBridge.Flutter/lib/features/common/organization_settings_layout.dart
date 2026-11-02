import 'package:flutter/material.dart';

import '../../design_system/icons/standard_icon.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_compact_select.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

typedef OrganizationSettingsSection = ({
  String id,
  StandardIconSemantic icon,
  String? group,
});

/// The existing settings navigation and surfaces, with no business authority.
class OrganizationSettingsLayout extends StatelessWidget {
  const OrganizationSettingsLayout({
    required this.sections,
    required this.label,
    required this.selected,
    required this.onSelected,
    required this.content,
    this.identity = 'community-settings',
    super.key,
  });
  final List<OrganizationSettingsSection> sections;
  final String Function(String) label;
  final String selected, identity;
  final Future<void> Function(String) onSelected;
  final Widget content;
  String get keyPrefix =>
      identity == 'community-settings' ? 'settings' : identity;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final content = ClipRect(
          child: Material(
            color: context.tokens.surfaces.panel.fill,
            child: this.content,
          ),
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: label('title'),
                    isDense: true,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: StarBridgeCompactSelect<String>(
                      key: ValueKey('$keyPrefix-category'),
                      identity: '$identity-category',
                      controlKey: ValueKey('$identity-category-control'),
                      semanticLabel: label('title'),
                      value: selected,
                      isExpanded: true,
                      isDense: true,
                      style: Theme.of(context).textTheme.bodyMedium,
                      options: [
                        for (final entry in sections)
                          StarBridgeSelectOption(
                            value: entry.id,
                            label: label(entry.id),
                          ),
                      ],
                      onSelected: (value, _) => onSelected(value),
                    ),
                  ),
                ),
              ),
              Expanded(child: content),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 220,
              decoration: BoxDecoration(
                color: context.tokens.surfaces.panel.fill,
                border: Border(
                  right: BorderSide(
                    color: context.tokens.surfaces.panel.border,
                  ),
                ),
              ),
              child: SingleChildScrollView(
                primary: false,
                key: ValueKey('$keyPrefix-navigation-scroll'),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < sections.length; index++) ...[
                      if (sections[index].group != null &&
                          (index == 0 ||
                              sections[index].group !=
                                  sections[index - 1].group))
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                          child: Text(
                            label(sections[index].group!),
                            style: TextStyle(
                              color: context.tokens.colors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      Padding(
                        padding: EdgeInsets.zero,
                        child: Material(
                          type: MaterialType.transparency,
                          child: StarBridgeActionRow(
                            controlKey: ValueKey(
                              '$keyPrefix-nav-${sections[index].id}',
                            ),
                            semanticLabel: label(sections[index].id),
                            semanticSelected: selected == sections[index].id,
                            onActivate: (_, _) =>
                                onSelected(sections[index].id),
                            child: ListTile(
                              dense: true,
                              visualDensity: const VisualDensity(vertical: -2),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              minLeadingWidth: 18,
                              horizontalTitleGap: 10,
                              leading: StandardIcon(
                                sections[index].icon,
                                size: 18,
                              ),
                              title: Text(
                                label(sections[index].id),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              selected: selected == sections[index].id,
                              selectedTileColor: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: .12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                ),
                clipBehavior: Clip.antiAlias,
                child: content,
              ),
            ),
          ],
        );
      },
    );
  }
}
