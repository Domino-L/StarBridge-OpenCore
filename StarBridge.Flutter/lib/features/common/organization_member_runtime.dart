import 'dart:ui' show Locale;

import 'runtime_name_labels.dart';
import 'organization_member_runtime_cells.dart';

/// Pure privacy-filtered presentation facts, with no member ID or permission.
/// Both directory domains use the exact same 0.7.1 runtime wording rules.
final class OrganizationMemberRuntimeFacts {
  const OrganizationMemberRuntimeFacts({
    required this.publicInGame,
    this.serverRegion,
    this.hasServerSession,
    this.ship,
    this.location,
    this.locationHiddenReason,
    this.arrivalPendingConfirmation = false,
    this.arrivalTargetCode,
    this.shipLabels = const {},
    this.locationLabels = const {},
    this.arrivalTargetLabels = const {},
  });
  final bool publicInGame, arrivalPendingConfirmation;
  final bool? hasServerSession;
  final String? serverRegion,
      ship,
      location,
      locationHiddenReason,
      arrivalTargetCode;
  final Map<String, String> shipLabels, locationLabels, arrivalTargetLabels;
}

MemberRuntimeCells organizationMemberRuntimeCells(
  OrganizationMemberRuntimeFacts member, {
  required String Function(String) text,
  required String Function(String) regionText,
  Locale locale = const Locale('en'),
}) {
  if (!member.publicInGame) {
    final value = MemberRuntimeCell.placeholder(text('notInGame'));
    return MemberRuntimeCells(server: value, ship: value, location: value);
  }
  final region = switch (member.serverRegion?.toUpperCase()) {
    'USA' => 'US',
    'EUROPE' => 'EU',
    'AUSTRALIA' => 'AU',
    final value => value,
  };
  final session =
      member.hasServerSession ??
      (recognizedCommunityRuntime(region) ? true : null);
  MemberRuntimeCell runtime(String? value, {bool location = false}) {
    // Null means withheld, not evidence of an unknown location or session.
    if (value == null) return MemberRuntimeCell.placeholder(text('hidden'));
    if (session == false) {
      return MemberRuntimeCell.placeholder(text('notInServer'));
    }
    if (location && member.arrivalPendingConfirmation) {
      final target = member.arrivalTargetCode;
      final pending = text('locationPending');
      return MemberRuntimeCell.placeholder(
        recognizedCommunityRuntime(target)
            ? '${runtimeNameLabel(target!, member.arrivalTargetLabels, locale)} · $pending'
            : pending,
      );
    }
    if (recognizedCommunityRuntime(value)) {
      return MemberRuntimeCell.value(
        location
            ? runtimeNameLabel(value.trim(), member.locationLabels, locale)
            : value.trim(),
      );
    }
    if (location &&
        member.locationHiddenReason == 'lowConfidence' &&
        value.trim().toLowerCase() == 'unknown') {
      return MemberRuntimeCell.placeholder(text('lowConfidenceLocation'));
    }
    return MemberRuntimeCell.placeholder(
      text(session == true ? 'waitingRecognition' : 'waitingServerSync'),
    );
  }

  return MemberRuntimeCells(
    server: region == null
        ? MemberRuntimeCell.placeholder(text('hidden'))
        : session == false
        ? MemberRuntimeCell.placeholder(text('notInServer'))
        : recognizedCommunityRuntime(region)
        ? MemberRuntimeCell.value(regionText(region))
        : MemberRuntimeCell.placeholder(text('waitingServerSync')),
    ship: runtime(
      member.ship == null || !recognizedCommunityRuntime(member.ship)
          ? member.ship
          : runtimeNameLabel(member.ship!, member.shipLabels, locale),
    ),
    location: runtime(member.location, location: true),
  );
}

bool recognizedCommunityRuntime(String? value) {
  final normalized = value?.trim().toLowerCase() ?? '';
  return !const {
        '',
        'unknown',
        'none',
        'n/a',
        '未知',
        '无',
        '未连接',
        '地点：未知星域',
        '飞船：未知',
        '未进入游戏',
        '未进入服务器',
      }.contains(normalized) &&
      !normalized.startsWith('等待');
}
