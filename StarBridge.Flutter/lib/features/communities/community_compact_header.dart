import 'package:flutter/material.dart';

import '../common/organization_compact_header.dart';
import 'community_workspace_copy.dart';
import 'community_profile_copy.dart';

/// Compatibility adapter for the client and menu's existing community callers.
class CommunityCompactHeader extends StatelessWidget {
  const CommunityCompactHeader({
    super.key,
    required this.name,
    required this.code,
    required this.logo,
    required this.narrow,
    this.online,
    this.gaming,
    this.total,
    this.scoped = false,
    this.showUnknownMetrics = false,
    this.onDetails,
    this.onToggleExpansion,
  });
  final String name, code;
  final Widget logo;
  final int? online, gaming, total;
  final bool scoped, narrow, showUnknownMetrics;
  final VoidCallback? onDetails, onToggleExpansion;

  @override
  Widget build(BuildContext context) => OrganizationCompactHeader(
    name: name,
    code: code,
    logo: logo,
    narrow: narrow,
    online: online,
    gaming: gaming,
    total: total,
    scoped: scoped,
    showUnknownMetrics: showUnknownMetrics,
    onDetails: onDetails,
    onToggleExpansion: onToggleExpansion,
    keyPrefix: 'community',
    text: (key) => workspaceText(context, key),
    expandLabel: profileText(context, 'expandHeader'),
  );
}
