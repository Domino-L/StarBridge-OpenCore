import 'community_workspace_port.dart';

import 'dart:ui' show Locale;

import '../common/organization_member_runtime.dart';
export '../common/organization_member_runtime.dart'
    show recognizedCommunityRuntime;
import '../common/organization_member_runtime_cells.dart';

/// WPF S2 PlayerSessionStatePresentation / GameServerRegionPresentation
/// semantics, applied only to the privacy-filtered workspace projection.
MemberRuntimeCells communityMemberRuntimeCells(
  CommunityWorkspaceMember member, {
  required String Function(String) text,
  required String Function(String) regionText,
  Locale locale = const Locale('en'),
}) {
  return organizationMemberRuntimeCells(
    OrganizationMemberRuntimeFacts(
      publicInGame: member.publicInGame,
      serverRegion: member.serverRegion,
      hasServerSession: member.hasServerSession,
      ship: member.ship,
      location: member.location,
      locationHiddenReason: member.locationHiddenReason,
      arrivalPendingConfirmation: member.arrivalPendingConfirmation,
      arrivalTargetCode: member.arrivalTargetCode,
      shipLabels: member.shipLabels,
      locationLabels: member.locationLabels,
      arrivalTargetLabels: member.arrivalTargetLabels,
    ),
    text: text,
    regionText: regionText,
    locale: locale,
  );
}

/// Compatibility record for older consumers. Both representations use the same
/// runtime mapping, so privacy, factual state and localized wording cannot drift.
({String server, String ship, String location}) communityMemberRuntime(
  CommunityWorkspaceMember member, {
  required String Function(String) text,
  required String Function(String) regionText,
  Locale locale = const Locale('en'),
}) {
  final cells = communityMemberRuntimeCells(
    member,
    text: text,
    regionText: regionText,
    locale: locale,
  );
  return (
    server: cells.server.text,
    ship: cells.ship.text,
    location: cells.location.text,
  );
}
