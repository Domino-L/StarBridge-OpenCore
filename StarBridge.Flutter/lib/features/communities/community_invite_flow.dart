import 'package:flutter/material.dart';

import '../settings/local_privacy_port.dart';
import 'communities_module.dart';
import 'community_invite_dialog.dart';
import 'community_invite_port.dart';
import 'example_communities.dart';

/// Shares the existing authoritative preview and privacy confirmation flow.
Future<void> openCommunityInvitation(
  BuildContext context,
  CommunitiesModule module,
  String code, {
  LocalPrivacyPort Function()? createPrivacy,
}) async {
  final port = module.port;
  if (port is! CommunityInvitePort) return;
  final revision = module.accountRevision;
  final example = port is ExampleCommunities;
  final privacy = example
      ? port.createAdmissionPrivacy()
      : createPrivacy?.call();
  await showDialog<CommunityInviteOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (_) => CommunityInviteDialog(
      port: port as CommunityInvitePort,
      initialCode: code,
      example: example,
      privacy: privacy,
    ),
  );
  if (!context.mounted || revision != module.accountRevision) return;
  await module.refreshJoined();
}
