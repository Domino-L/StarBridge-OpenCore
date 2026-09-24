import 'party_rooms_module.dart';

// Example Adapter only; never used to optimistically patch real server data.
PartyRoom copyExampleRoom(
  PartyRoom room, {
  Map<String, Object?>? settings,
  List<RoomMember>? members,
  List<RoomApplication>? applications,
  bool? viewerIsHost,
  bool? passwordRequired,
  List<RoomTag>? tags,
}) {
  final now = DateTime.now().toUtc();
  return PartyRoom(
    id: room.id,
    roomCode: room.roomCode,
    title: settings?['title'] as String? ?? room.title,
    goal: settings?['goal'] as String? ?? room.goal,
    capacity: settings?['capacity'] as int? ?? room.capacity,
    isPublic: settings?['isPublic'] as bool? ?? room.isPublic,
    eligibility: settings?['eligibility'] as String? ?? room.eligibility,
    admissionMode: settings?['admissionMode'] as String? ?? room.admissionMode,
    passwordRequired: passwordRequired ?? room.passwordRequired,
    voice: settings?['voiceRequirement'] as String? ?? room.voice,
    language: settings?['language'] as String? ?? room.language,
    expiresAt: settings == null
        ? room.expiresAt
        : now.add(Duration(hours: settings['autoDisbandHours'] as int)),
    recruitmentClosesAt: settings == null
        ? room.recruitmentClosesAt
        : settings['recruitmentDurationMinutes'] == null
        ? null
        : now.add(
            Duration(minutes: settings['recruitmentDurationMinutes'] as int),
          ),
    viewerIsHost: viewerIsHost ?? room.viewerIsHost,
    members: members ?? room.members,
    tags: tags ?? room.tags,
    pendingApplications: applications ?? room.pendingApplications,
    leaderServerRegion: room.leaderServerRegion,
    leaderGameVersion: room.leaderGameVersion,
  );
}
