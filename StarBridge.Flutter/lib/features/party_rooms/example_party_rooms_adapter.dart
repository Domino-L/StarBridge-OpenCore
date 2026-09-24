import 'party_rooms_module.dart';
import 'room_tag_catalog.dart';
import 'room_commands.dart';
import 'example_room_copy.dart';
import 'room_invitations.dart';
import 'room_chat_module.dart';
import 'example_room_chat.dart';

/// Explicit example-mode data only. No Host, account, network or persistence.
final class ExamplePartyRoomsAdapter
    implements
        PartyRoomsPort,
        PartyRoomsPreviewControl,
        RoomCommandsPort,
        RoomManagementPort,
        RoomInvitationsPort,
        RoomChatProvider {
  @override
  final RoomChatPort roomChat = ExampleRoomChat();
  final _received = <RoomInvitation>[_sampleInvitation()];
  final _sent = <RoomInvitation>[];
  static RoomInvitation _sampleInvitation() => RoomInvitation(
    id: 'example-invitation',
    roomId: 'example-cargo',
    title: '示例 · 货运护航',
    inviter: '示例房主 (Example_Host)',
    recipient: '示例成员 (Example_Member)',
    expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
  );
  @override
  bool get supportsInvitations => true;
  PartyRoom? _created;
  String? _joinedId;
  String _password = '';
  @override
  bool get supportsCommands => true;
  @override
  bool get supportsManagement => true;
  @override
  String previewScene = 'directory';
  @override
  void selectPreviewScene(String scene) {
    previewScene = scene;
    _received
      ..clear()
      ..add(_sampleInvitation());
    _sent.clear();
    _joinedId = null;
    _created = null;
    _password = '';
    if (scene == 'host') {
      final now = DateTime.now().toUtc();
      _created = copyExampleRoom(
        _room('example-host', '示例 · 房主管理', '预览设置修改与申请处理。', 6, now, 2),
        viewerIsHost: true,
        applications: [
          RoomApplication(
            id: 'example-application-1',
            callsign: '示例申请者一',
            gameId: 'Example_Applicant_One',
            createdAt: now,
          ),
          RoomApplication(
            id: 'example-application-2',
            callsign: '示例申请者二',
            gameId: 'Example_Applicant_Two',
            createdAt: now,
          ),
        ],
      );
      _joinedId = _created!.id;
    }
  }

  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<void> close() async {}
  @override
  Future<RoomReadResult> read() async {
    if (previewScene == 'error') {
      return const RoomReadResult(RoomReadState.unavailable);
    }
    final now = DateTime.now().toUtc();
    final rooms = [
      ?_created,
      _room('example-cargo', '示例 · 货运护航', '一起完成短途货运，出发前确认路线与分工。', 4, now, 3),
      _room('example-exploration', '示例 · 探索与导航', '自由探索，欢迎一起规划航线。', 8, now, 2),
      _room('example-social', '示例 · 轻松组队', '没有固定目标，先集合再决定今天玩什么。', 16, now, 4),
    ];
    return RoomReadResult(
      RoomReadState.ready,
      directory: RoomDirectory(
        receivedInvitations: List.unmodifiable(_received),
        sentInvitations: List.unmodifiable(_sent),
        tagOptions: RoomTagCatalog.exampleOptions,
        serverTime: now,
        currentRoomId: const ['current', 'host'].contains(previewScene)
            ? (_joinedId ?? rooms.first.id)
            : null,
        rooms: switch (previewScene) {
          'empty' => [],
          'current' || 'host' => [
            rooms.firstWhere(
              (room) => room.id == (_joinedId ?? rooms.first.id),
            ),
          ],
          _ => rooms,
        },
      ),
    );
  }

  @override
  Future<RoomCommandResult> execute(RoomCommand command) async {
    if (command.operation.name.startsWith('invite')) {
      final data = command.data;
      if (command.operation == RoomOperation.inviteTargets) {
        return RoomCommandResult(
          'targets',
          directory: (await read()).directory,
          targets: [
            RoomInviteTarget(
              'example-friend',
              '示例好友 (Example_Friend)',
              alreadyInvited: _sent.isNotEmpty,
            ),
          ],
        );
      }
      if (command.operation == RoomOperation.invite) {
        if (_created?.viewerIsHost != true ||
            data['targetRef'] != 'example-friend') {
          return const RoomCommandResult('rejected', error: 'targetGone');
        }
        if (_sent.isEmpty) {
          _sent.add(
            RoomInvitation(
              id: 'example-sent',
              roomId: _created!.id,
              title: _created!.title,
              inviter: '示例房主 (Example_Host)',
              recipient: '示例好友 (Example_Friend)',
              expiresAt: _created!.expiresAt,
            ),
          );
        }
        return RoomCommandResult(
          'invited',
          directory: (await read()).directory,
        );
      }
      if (command.operation == RoomOperation.invitePreview) {
        final room = (await read()).directory?.rooms
            .where((r) => r.id == command.data['roomId'])
            .firstOrNull;
        return RoomCommandResult('resolved', preview: room);
      }
      final sent = command.operation == RoomOperation.inviteRevoke;
      final items = sent ? _sent : _received;
      final item = items
          .where(
            (item) =>
                item.id == data['invitationId'] &&
                item.roomId == data['roomId'],
          )
          .firstOrNull;
      if (item == null) {
        return const RoomCommandResult('rejected', error: 'invitationGone');
      }
      if (command.operation == RoomOperation.inviteJoin &&
          (await read()).directory!.currentRoomId != null) {
        return const RoomCommandResult('rejected', error: 'alreadyJoined');
      }
      items.remove(item);
      if (command.operation == RoomOperation.inviteJoin) {
        _joinedId = item.roomId;
        previewScene = 'current';
      }
      return RoomCommandResult(
        command.operation == RoomOperation.inviteJoin
            ? 'joined'
            : sent
            ? 'revoked'
            : 'declined',
        directory: (await read()).directory,
      );
    }
    if (command.operation == RoomOperation.leave) {
      _sent.clear();
      previewScene = 'directory';
      _joinedId = null;
      _created = null;
      _password = '';
      return RoomCommandResult('left', directory: (await read()).directory);
    }
    final before = (await read()).directory!;
    if (const [
      RoomOperation.update,
      RoomOperation.close,
      RoomOperation.decide,
    ].contains(command.operation)) {
      final room = before.rooms
          .where(
            (room) =>
                room.id == before.currentRoomId &&
                room.id == command.data['roomId'],
          )
          .firstOrNull;
      if (room?.viewerIsHost != true) {
        return const RoomCommandResult('rejected', error: 'notHost');
      }
      if (command.operation == RoomOperation.close) {
        _sent.clear();
        _created = null;
        _joinedId = null;
        previewScene = 'directory';
        _password = '';
        return RoomCommandResult('closed', directory: (await read()).directory);
      }
      if (command.operation == RoomOperation.update) {
        final data = command.data;
        if ((data['capacity'] as int) < room!.members.length) {
          return const RoomCommandResult('rejected', error: 'capacityTooSmall');
        }
        if (data['passwordMode'] == 'remove') _password = '';
        if (data['passwordMode'] == 'replace') {
          _password = data['password'] as String;
        }
        final ids = [
          ...data['gameplayTagNodeIds'] as List,
          ...data['contextTagIds'] as List,
        ];
        _created = copyExampleRoom(
          room,
          settings: data,
          passwordRequired: _password.isNotEmpty,
          tags: before.tagOptions.where((tag) => ids.contains(tag.id)).toList(),
        );
        return RoomCommandResult(
          'updated',
          directory: (await read()).directory,
        );
      }
      final applicant = room!.pendingApplications
          .where((item) => item.id == command.data['applicationId'])
          .firstOrNull;
      if (applicant == null) {
        return const RoomCommandResult('rejected', error: 'applicationGone');
      }
      final approved = command.data['approve'] == true;
      if (approved && room.members.length >= room.capacity) {
        return const RoomCommandResult('rejected', error: 'roomFull');
      }
      _created = copyExampleRoom(
        room,
        applications: room.pendingApplications
            .where((item) => item.id != applicant.id)
            .toList(),
        members: [
          ...room.members,
          if (approved)
            RoomMember(
              callsign: applicant.callsign,
              gameId: applicant.gameId,
              isHost: false,
              presence: '应用在线',
              presenceKey: 'presence.online',
              location: '',
              ship: '',
              shard: '',
            ),
        ],
      );
      return RoomCommandResult(
        approved ? 'approved' : 'declined',
        directory: (await read()).directory,
      );
    }
    if (command.operation == RoomOperation.create) {
      final data = command.data;
      final now = DateTime.now().toUtc();
      _password = data['passwordEnabled'] == true
          ? data['password'] as String
          : '';
      final ids = [
        ...data['gameplayTagNodeIds'] as List,
        ...data['contextTagIds'] as List,
      ];
      _created = PartyRoom(
        id: 'example-created',
        title: data['title'] as String,
        goal: data['goal'] as String,
        capacity: data['capacity'] as int,
        isPublic: data['isPublic'] as bool,
        eligibility: data['eligibility'] as String,
        admissionMode: data['admissionMode'] as String,
        passwordRequired: _password.isNotEmpty,
        voice: data['voiceRequirement'] as String,
        language: data['language'] as String,
        expiresAt: now.add(Duration(hours: data['autoDisbandHours'] as int)),
        recruitmentClosesAt: data['recruitmentDurationMinutes'] == null
            ? null
            : now.add(
                Duration(minutes: data['recruitmentDurationMinutes'] as int),
              ),
        viewerIsHost: true,
        roomCode: 'DEMO1234',
        tags: before.tagOptions.where((tag) => ids.contains(tag.id)).toList(),
        members: const [
          RoomMember(
            callsign: '示例房主',
            gameId: 'Example_Host',
            isHost: true,
            presence: '应用在线',
            presenceKey: 'presence.online',
            location: '',
            ship: '',
            shard: '',
          ),
        ],
      );
      _joinedId = _created!.id;
      previewScene = 'current';
      return RoomCommandResult('joined', directory: (await read()).directory);
    }
    if (command.operation == RoomOperation.resolve) {
      if (command.data['roomCode'] != 'DEMO1234') {
        return const RoomCommandResult('rejected', error: 'roomGone');
      }
      return RoomCommandResult('resolved', preview: before.rooms.first);
    }
    final target = before.rooms
        .where((room) => room.id == command.data['roomId'])
        .firstOrNull;
    if (target == null) {
      return const RoomCommandResult('rejected', error: 'roomGone');
    }
    if (target.passwordRequired && command.data['password'] != _password) {
      return const RoomCommandResult('rejected', error: 'passwordIncorrect');
    }
    if (target.admissionMode == 'approval') {
      return RoomCommandResult('pending', directory: before);
    }
    _joinedId = target.id;
    previewScene = 'current';
    return RoomCommandResult('joined', directory: (await read()).directory);
  }

  PartyRoom _room(
    String id,
    String title,
    String goal,
    int capacity,
    DateTime now,
    int count,
  ) => PartyRoom(
    id: id,
    title: title,
    goal: goal,
    capacity: capacity,
    isPublic: true,
    eligibility: 'everyone',
    admissionMode: capacity == 4 || id == 'example-host'
        ? 'approval'
        : 'direct',
    passwordRequired: false,
    voice: capacity == 4 ? 'recommended' : 'none',
    language: id == 'example-exploration' ? 'en' : 'bilingual',
    expiresAt: now.add(const Duration(hours: 4)),
    recruitmentClosesAt: now.add(const Duration(minutes: 40)),
    viewerIsHost: false,
    roomCode: const ['current', 'host'].contains(previewScene)
        ? 'DEMO1234'
        : '',
    leaderServerRegion: id == 'example-exploration' ? 'EU' : 'US',
    leaderGameVersion: id == 'example-exploration' ? 'EPTU' : 'LIVE',
    tags: switch (id) {
      'example-cargo' => const [
        RoomTag(
          id: 'support_cargo_escort',
          text: '救援与支援 · 护航安保 · 货运护航',
          isGameplay: true,
        ),
        RoomTag(id: 'need_escort', text: '缺护航', isGameplay: false),
      ],
      'example-exploration' => const [
        RoomTag(
          id: 'exploration_route_recon',
          text: '探索与调查 · 侦察 · 路线勘察',
          isGameplay: true,
        ),
        RoomTag(id: 'pace_casual', text: '休闲慢玩', isGameplay: false),
      ],
      _ => const [
        RoomTag(id: 'undecided', text: '不知道玩啥', isGameplay: true),
        RoomTag(
          id: 'experience_beginner_friendly',
          text: '新手友好',
          isGameplay: false,
        ),
      ],
    },
    members: [
      RoomMember(
        callsign: '示例房主',
        gameId: 'Example_Host',
        isHost: true,
        presence: id == 'example-exploration' ? '游戏中 · EPTU' : '游戏中 · LIVE',
        presenceKey: 'presence.inGame',
        serverRegion: id == 'example-exploration' ? 'EU' : 'US',
        location: '奥里森',
        ship: 'C2 Hercules',
        shard: id == 'example-exploration'
            ? 'pub_euw1a_00000000_001'
            : 'pub_use1b_00000000_001',
      ),
      const RoomMember(
        callsign: '示例成员',
        gameId: 'Example_Member',
        isHost: false,
        presence: '应用在线',
        presenceKey: 'presence.online',
        location: '',
        ship: '',
        shard: '',
      ),
      if (count >= 3)
        const RoomMember(
          callsign: '示例护航',
          gameId: 'Example_Escort',
          isHost: false,
          presence: '游戏中 · LIVE',
          presenceKey: 'presence.inGame',
          location: '奥里森',
          ship: 'F7C-M Super Hornet Mk II',
          shard: 'pub_use1b_00000000_001',
          serverRegion: 'US',
        ),
      if (count >= 4)
        const RoomMember(
          callsign: '示例暂离',
          gameId: 'Example_Away',
          isHost: false,
          presence: '暂离',
          presenceKey: 'presence.away',
          location: '',
          ship: '',
          shard: '',
        ),
      if (_joinedId == id)
        const RoomMember(
          callsign: '示例中的你',
          gameId: 'Example_Viewer',
          isHost: false,
          presence: '应用在线',
          presenceKey: 'presence.online',
          location: '',
          ship: '',
          shard: '',
        ),
    ],
  );
}
