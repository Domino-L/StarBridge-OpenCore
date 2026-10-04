import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../features/communities/community_compact_header.dart';
import '../../features/communities/community_logo.dart';
import 'menu_feature_view.dart';

/// Uses the client header presentation without transporting service authority.
class MenuOrganizationHeader extends StatefulWidget {
  const MenuOrganizationHeader({
    super.key,
    required this.view,
    required this.onAction,
  });
  final MenuFeatureView view;
  final void Function(String, String) onAction;
  @override
  State<MenuOrganizationHeader> createState() => _MenuOrganizationHeaderState();
}

class _MenuOrganizationHeaderState extends State<MenuOrganizationHeader> {
  bool expanded = false;
  @override
  void didUpdateWidget(MenuOrganizationHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.organization?.identity !=
        widget.view.organization?.identity) {
      expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view, org = widget.view.organization!;
    final members = org.tab == 'members';
    final scoped =
        org.query.isNotEmpty || org.offset != 0 || org.rows.length != org.total;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: context.tokens.surfaces.raised.fill,
        border: Border.all(color: context.tokens.surfaces.panel.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => CommunityCompactHeader(
              name: view.title,
              code: org.code,
              logo: CommunityLogo(data: org.logo, size: 32, framed: false),
              narrow:
                  constraints.maxWidth /
                      MediaQuery.textScalerOf(context).scale(1) <
                  650,
              scoped: org.overview?.scoped ?? scoped,
              showUnknownMetrics: true,
              online: org.overview != null
                  ? org.overview!.online
                  : (members
                        ? org.rows
                              .where(
                                (r) => const {
                                  'online',
                                  'away',
                                  'inGame',
                                }.contains(r.presence),
                              )
                              .length
                        : null),
              gaming: org.overview != null
                  ? org.overview!.gaming
                  : (members
                        ? org.rows.where((r) => r.presence == 'inGame').length
                        : null),
              total: org.overview != null
                  ? org.overview!.total
                  : (members ? org.total : null),
              onDetails: org.description.isEmpty && org.activeTime.isEmpty
                  ? null
                  : () => setState(() => expanded = !expanded),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 24),
            if (org.description.isNotEmpty) Text(org.description),
            if (org.activeTime.isNotEmpty) Text('活动时间 · ${org.activeTime}'),
          ],
        ],
      ),
    );
  }
}
