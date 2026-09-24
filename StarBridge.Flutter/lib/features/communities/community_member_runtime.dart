import 'community_workspace_port.dart';

/// WPF S2 PlayerSessionStatePresentation / GameServerRegionPresentation
/// semantics, applied only to the privacy-filtered workspace projection.
({String server, String ship, String location}) communityMemberRuntime(
  CommunityWorkspaceMember member, {
  required String Function(String) text,
  required String Function(String) regionText,
}) {
  final status = member.liveStatus.toLowerCase();
  if (const {'paused', 'hidden', 'unknown', ''}.contains(status)) {
    final hidden = text('hidden');
    return (server: hidden, ship: hidden, location: hidden);
  }
  if (!member.online || status != 'ingame') {
    final value = text('notInGame');
    return (server: value, ship: value, location: value);
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
  String runtime(String? value, {bool location = false}) {
    // Null means withheld, not evidence of an unknown location or session.
    if (value == null) return text('hidden');
    if (session == false) return text('notInServer');
    if (recognizedCommunityRuntime(value)) return value.trim();
    if (location && member.arrivalPendingConfirmation) {
      return text('locationPending');
    }
    return text(session == true ? 'waitingRecognition' : 'waitingServerSync');
  }

  return (
    server: region == null
        ? text('hidden')
        : recognizedCommunityRuntime(region) && session != false
        ? regionText(region)
        : '—',
    ship: runtime(member.ship),
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
