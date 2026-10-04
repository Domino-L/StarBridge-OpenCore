import 'party_rooms_module.dart';

bool canRemoveRoomMember(PartyRoom room, RoomMember member) =>
    room.viewerIsHost &&
    !member.isHost &&
    !member.isSelf &&
    member.removalToken?.isNotEmpty == true;

bool roomRecruitmentClosed(PartyRoom room, DateTime serverTime) =>
    !room.expiresAt.isAfter(serverTime) ||
    (room.recruitmentClosesAt != null &&
        !room.recruitmentClosesAt!.isAfter(serverTime));
