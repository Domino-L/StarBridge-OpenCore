import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'community_workspace_copy.dart';

// Header and rows share the same widths so the WPF directory columns align.
const _memberColumns = [
  'member',
  'role',
  'server',
  'ship',
  'location',
  'status',
];
const _memberFlex = [28, 14, 14, 18, 16, 14];
const _wideMemberWidth = 800.0;

/// Shared member chrome for the client and presentation-only menu surface.
class CommunityMemberCard extends StatelessWidget {
  const CommunityMemberCard({super.key, required this.child, this.status});
  final Widget child;
  final Color? status;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.tokens.surfaces.raised.fill,
      border: Border.all(color: context.tokens.surfaces.panel.border),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Stack(
      children: [
        if (status != null)
          PositionedDirectional(
            start: 0,
            top: 8,
            bottom: 8,
            width: 3,
            child: ColoredBox(color: status!),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Material(color: Colors.transparent, child: child),
        ),
      ],
    ),
  );
}

class CommunityRoleBadge extends StatelessWidget {
  const CommunityRoleBadge({
    super.key,
    required this.label,
    required this.color,
  });
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        border: Border.all(color: color.withValues(alpha: .6)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
      ),
    ),
  );
}

Widget _columns(List<Widget> cells, Widget? actions) => Row(
  children: [
    for (var i = 0; i < cells.length; i++)
      Expanded(
        flex: _memberFlex[i],
        child: Padding(
          padding: const EdgeInsetsDirectional.only(end: 12),
          child: cells[i],
        ),
      ),
    if (actions != null) SizedBox(width: 40, child: actions),
  ],
);

class CommunityMemberHeader extends StatelessWidget {
  const CommunityMemberHeader({required this.showActions, super.key});

  final bool showActions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _wideMemberWidth) return const SizedBox();
        final style = Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: context.tokens.colors.textSecondary);
        return Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: _columns(
            [
              for (final column in _memberColumns)
                Text(workspaceText(context, column), style: style),
            ],
            showActions
                ? Text(workspaceText(context, 'actions'), style: style)
                : null,
          ),
        );
      },
    ),
  );
}

class CommunityMemberBanner extends StatelessWidget {
  const CommunityMemberBanner({
    required this.identity,
    required this.role,
    required this.server,
    required this.ship,
    required this.location,
    required this.status,
    required this.actions,
    super.key,
  });

  final Widget identity, role, status;
  final Widget? actions;
  final String server, ship, location;

  @override
  Widget build(BuildContext context) {
    final values = [
      identity,
      role,
      Text(server),
      Text(ship),
      Text(location),
      status,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _wideMemberWidth) {
          return _columns(values, actions);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: identity),
                ?actions,
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                for (var i = 1; i < values.length; i++)
                  SizedBox(
                    width: ((constraints.maxWidth - 16) / 2).clamp(0, 180),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          workspaceText(context, _memberColumns[i]),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: context.tokens.colors.textSecondary,
                              ),
                        ),
                        const SizedBox(height: 4),
                        values[i],
                      ],
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
