import 'dart:async';
import 'dart:convert';
import 'dart:math' show Random;

import 'package:flutter/foundation.dart' show Listenable;
import 'package:flutter/services.dart';

import '../../features/account/account_models.dart';
import '../../features/onboarding/connection_mode_port.dart';
import '../bridge/bridge_client_session.dart';
import '../bridge/bridge_envelope.dart';
import '../../shared/bounded_inline_avatar.dart';

/// Lets client pages shown in the menu engine reach the primary Host session.
/// The Host pipe has one client, so the menu engine sends here. Only the listed
/// names pass; the Host still validates the owner and generation of each one.
final class MenuBridgeRelay {
  MenuBridgeRelay(
    this.session, {
    required this.mode,
    this.ownProfile,
    this.ownProfileChanges,
    this.countedOnline,
    this.scmOnly,
    this.presenceChanges,
    this.channel = const MethodChannel('starbridge/menu-primary'),
  }) {
    _accountWork = session.events
        .where(
          (event) =>
              event.name == 'account.changed' ||
              event.name == 'bootstrap.invalidated',
        )
        .listen((_) => _forgetOwners());
    _removeGenerationWork = session.observeGenerationChanges(
      (_, _) => _forgetOwners(),
    );
  }
  late final StreamSubscription<BridgeEnvelope> _accountWork;
  late final void Function() _removeGenerationWork;

  final BridgeClientSession session;

  /// Borrowed lazily: the connection mode owner is composed after this relay.
  final ConnectionModeControl? Function() mode;

  /// The user's own name and avatar, for the menu's fleet and organization
  /// pages (their own rows, their own chat lines). Nothing else of the account.
  final AccountProfile? Function()? ownProfile;
  final Listenable? ownProfileChanges;

  /// Whether the user counts as online for a rally (not invisible or offline),
  /// as the client decides it. Its owner is composed after this relay.
  final bool Function()? countedOnline;

  /// Whether the account is SCM-only (no linked legacy account), so the menu's
  /// organization pages hide the entries the relay cannot serve, as the client
  /// does. A single yes or no; nothing else of the account is sent.
  final bool Function()? scmOnly;
  final Listenable? Function()? presenceChanges;
  Listenable? _presenceListened;
  Listenable? _profileListened;
  final MethodChannel channel;
  ConnectionModeControl? _listened;
  void Function()? _removeModeWork;

  /// Pending pause questions: true when the menu answered, false when it hid
  /// (or greeted again) first.
  final _pauses = <int, Completer<bool>>{};
  int _pauseSerial = 0;

  /// The trading hall's reads and writes, and its trade chat. `tradeProfile.write`
  /// stays out: the contact number is edited in the client, not in the game.
  static const hallRequests = {
    'account.getCurrent',
    'marketplace.read',
    'marketplace.trade',
    'marketplace.records',
    'marketplace.contracts',
    'marketplace.warehouse',
    'marketplace.notices',
    'marketplace.listings',
    'marketplace.preferences',
    'marketplace.chat',
    'tradeProfile.read',
    'helpSupport.openScm',
    'imageCache.open',
    'imageCache.read',
    'imageCache.beginWrite',
    'imageCache.append',
    'imageCache.commit',
    'imageCache.reject',
    'imageCache.close',
  };

  /// The main fleet page as in the client: reads, fleet chat, and the writes the
  /// scheduler approved 11-05 (roles, announcements, own hangar sharing,
  /// rallies, image reports). Host and Java still check every right. The first
  /// sharing choice and RSI refresh stay in the client ([clientOnly]).
  static const fleetRequests = {
    'officialFleet.getCurrent',
    'officialFleet.getIdentity',
    'officialFleet.getPublicProfile',
    'officialFleet.getMembers',
    'officialFleet.getRuntimeMembers',
    // No 'officialFleet.waitRuntimeActivity': the Host holds one such wait at
    // a time and the client's page may hold it. Without its capability the
    // menu's member list rereads every 15 s instead (CommunityActivity).
    'officialFleet.ships',
    'officialFleet.shipImage',
    'officialFleet.shipImageReportStatus',
    'officialFleet.hangarSharing',
    'officialFleet.hangarSharingPage',
    'officialFleet.readGovernanceContext',
    'officialFleet.readAnnouncementEditor',
    'officialFleet.readAnnouncementOutcome',
    'officialFleet.communication',
    'officialFleet.governanceRole',
    'officialFleet.manageAnnouncements',
    'officialFleet.saveHangarSharing',
    'officialFleet.rally',
    'officialFleet.rallyStarter',
    'officialFleet.reportShipImage',
    'communities.ships',
    'communities.shipImage',
    'communities.reportShipImage',
    'helpSupport.openRsiOrganization',
  };

  /// The organization page as in the client: reads, chat, and the management
  /// writes the scheduler approved 11-05. What is irreversible for the whole
  /// organization, opens a Windows file dialog over the game, changes overlay
  /// presets or refreshes RSI data stays in the client ([clientOnly]).
  static const communityRequests = {
    'communities.read',
    'communities.readTransient',
    'communities.workspace',
    'communities.profile',
    'communities.roles',
    'communities.logs',
    'communities.admissions',
    'communities.invitationOutbox',
    'communities.previewInvite',
    'communities.memberPersonalProfile',
    'communities.announcements',
    'communities.announcementDetail',
    'communities.chat',
    'communities.chatDetail',
    'communities.sendChat',
    'communities.markChatRead',
    'communities.media',
    'communities.logo',
    'communities.wideImage',
    'communities.hangarSharing',
    'communities.saveHangarSharing',
    'communities.saveProfile',
    'communities.saveRoles',
    'communities.memberRole',
    'communities.saveMemberRole',
    'communities.memberRemoval',
    'communities.removeMember',
    'communities.manageAdmissions',
    'communities.manageAnnouncements',
    'communities.sendInvite',
    'communities.resumeInvite',
    'communities.acceptInvite',
    'communities.execute',
    'communities.deleteLog',
    'officialFleet.read',
    'officialFleet.readMemberRoles',
    'officialFleet.readRoleTemplates',
    'officialFleet.readRoleTemplateOutcome',
    'officialFleet.readRankPolicy',
    'officialFleet.readGovernanceAudit',
    'officialFleet.assignRole',
    'officialFleet.revokeRole',
    'officialFleet.updateRolePermissions',
    'officialFleet.writeRankPolicy',
    'officialFleet.manageRoleTemplates',
  };

  /// Offered to the pages so their buttons look as in the client, but never
  /// relayed: the menu answers them with "do this in the client".
  static const clientOnly = {
    'communities.create',
    'communities.creationOptions',
    'communities.disband',
    'communities.disbandPreview',
    'communities.transferOwnership',
    'communities.ownershipTransfer',
    'communities.leaveWithSuccessor',
    'communities.ownershipExit',
    'communities.pickLogo',
    'communities.pickWideImage',
    'communities.cropLogo',
    'communities.cropWideImage',
    'communities.clearLogo',
    'communities.clearWideImage',
    'overlay.getWorkspace',
    'overlay.updateWorkspace',
    'account.refreshRsiData',
    'officialFleet.governance.activate',
    'officialFleet.governance.revokeActivation',
  };
  static const requests = {
    ...hallRequests,
    ...fleetRequests,
    ...communityRequests,
  };
  static const _capabilities = {
    ...requests,
    ...clientOnly,
    'communities.commands',
    'communities.invites',
    'overlay.presetSharing',
    'imageCache.resources.v1',
    'officialFleet.deferredProfile',
    'officialFleet.runtimeMembers',
    'officialFleet.communication.authorIdentities',
    'officialFleet.communication.previewAuthors',
    'officialFleet.communication.chatAuthorRenewal',
    'communities.chatAuthorRenewal',
    'communities.announcementsChanged',
    'communities.mediaChanged',
    'communities.shipsChanged',
  };
  static const _events = {
    'marketplace.changed',
    'marketplace.chatPushed',
    'account.changed',
    'account.avatarChanged',
    'account.presentationChanged',
    'hangarReader.changed',
    'bootstrap.invalidated',
  };

  /// Names that only read (images included), cancelled when the menu hides.
  /// Anything that may write is left to finish, so a done write never reads
  /// as a failure; a name missing here only keeps running as before.
  static const _readOnly = {
    'account.getCurrent',
    'marketplace.read',
    'marketplace.records',
    'tradeProfile.read',
    'imageCache.open',
    'imageCache.read',
    'imageCache.beginWrite',
    'imageCache.append',
    'imageCache.commit',
    'imageCache.reject',
    'imageCache.close',
    'officialFleet.getCurrent',
    'officialFleet.getIdentity',
    'officialFleet.getPublicProfile',
    'officialFleet.getMembers',
    'officialFleet.getRuntimeMembers',
    'officialFleet.ships',
    'officialFleet.shipImage',
    'officialFleet.shipImageReportStatus',
    'officialFleet.hangarSharing',
    'officialFleet.hangarSharingPage',
    'officialFleet.readGovernanceContext',
    'officialFleet.readAnnouncementEditor',
    'officialFleet.readAnnouncementOutcome',
    'officialFleet.read',
    'officialFleet.readMemberRoles',
    'officialFleet.readRoleTemplates',
    'officialFleet.readRoleTemplateOutcome',
    'officialFleet.readRankPolicy',
    'officialFleet.readGovernanceAudit',
    'communities.ships',
    'communities.shipImage',
    'communities.read',
    'communities.readTransient',
    'communities.workspace',
    'communities.profile',
    'communities.roles',
    'communities.logs',
    'communities.admissions',
    'communities.invitationOutbox',
    'communities.previewInvite',
    'communities.memberPersonalProfile',
    'communities.announcements',
    'communities.announcementDetail',
    'communities.chat',
    'communities.chatDetail',
    'communities.media',
    'communities.logo',
    'communities.wideImage',
    'communities.hangarSharing',
    'communities.memberRole',
    'communities.memberRemoval',
  };

  /// A profile save that sets or clears the logo, banner or background image
  /// is done in the client too (like `communities.pickLogo`), though its name
  /// is relayed for the rest of the profile.
  static bool changesImages(String name, Map<String, Object?> payload) {
    if (name != 'communities.saveProfile') return false;
    final changes = payload['changes'];
    if (changes is! Map) return false;
    return changes.entries.any(
      (entry) =>
          const {
            'logoImageData',
            'bannerImageData',
            'backgroundImageData',
          }.contains(entry.key) ||
          const {
                'clearLogoImage',
                'clearBannerImage',
                'clearBackgroundImage',
              }.contains(entry.key) &&
              entry.value != false,
    );
  }

  static const _deadline = Duration(seconds: 25);
  static const _pauseWait = Duration(seconds: 3);

  final _open = <String, (String, BridgeRequestOperation)>{};
  StreamSubscription<BridgeEnvelope>? _eventWork;
  StreamSubscription<void>? _capabilityWork;
  int? _opening;
  int _revision = 0;

  /// Each opening that hid, until the menu engine says its cancelled work has
  /// exited. Another hide never stands in for that word.
  final _exits = <int, Completer<void>>{};

  static bool accepts(String method) => method == 'bridgeRelay';

  Map<String, Object?> get presentation => {'pageRelay': !session.isClosed};

  Future<Object?> handle(
    Object? arguments, {
    required int? opening,
    required bool Function() isCurrent,
  }) async {
    // The only word a hidden menu may still send: it carries nothing but the
    // opening that hid, and only ends a wait.
    if (arguments is Map && arguments['action'] == 'exited') {
      if (arguments['opening'] case final int opening) _exited(opening);
      return null;
    }
    if (arguments is! Map ||
        arguments['opening'] != opening ||
        opening == null ||
        !isCurrent() ||
        session.isClosed) {
      throw PlatformException(code: 'menu.closed');
    }
    return switch (arguments['action']) {
      'hello' => _hello(opening),
      'request' => _request(arguments['payload']),
      'cancel' => _cancel(arguments['payload']),
      'paused' => _paused(arguments['payload']),
      _ => throw PlatformException(code: 'menu.invalidRelay'),
    };
  }

  /// The menu was hidden. Requests already sent still finish and answer, so a
  /// trade write never reports a false failure; no new events are forwarded.
  /// Reads already relayed are cancelled now: a hidden menu shows none of them,
  /// and a mode change must not find them still running at the Host.
  void retire() {
    if (_opening case final opening?) {
      _exits[opening] ??= Completer<void>();
      // A menu engine that never answers must not grow this without end.
      while (_exits.length > 4) {
        _exits.remove(_exits.keys.first);
      }
    }
    for (final (name, operation) in _open.values.toList()) {
      if (_readOnly.contains(name)) unawaited(operation.cancel());
    }
    _unsubscribe();
  }

  /// [endPauses] is false for another page greeting the same opening: a
  /// pause question in flight still waits for this engine's answer.
  void _unsubscribe({bool endPauses = true}) {
    _opening = null;
    unawaited(_eventWork?.cancel());
    unawaited(_capabilityWork?.cancel());
    for (final pause in _pauses.values) {
      if (endPauses && !pause.isCompleted) pause.complete(false);
    }
    _listened?.removeListener(_publishState);
    _listened = null;
    _profileListened?.removeListener(_publishState);
    _profileListened = null;
    _presenceListened?.removeListener(_publishState);
    _presenceListened = null;
    _eventWork = null;
    _capabilityWork = null;
  }

  /// The menu sees an opaque owner per account, never the Host's subject
  /// (for a legacy account that is its account id). Requests map it back.
  /// Forgotten when the account or session changes.
  final _owners = <String, BridgeAccountContext>{};
  final _ownerTokens = <(String, String, String), String>{};
  final _random = Random.secure();

  BridgeAccountContext? _toMenu(BridgeAccountContext? real) {
    if (real == null) return null;
    final key = (real.environment, real.authority, real.subject);
    final token = _ownerTokens[key] ??= List.generate(
      16,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    _owners[token] = real;
    return BridgeAccountContext(
      environment: real.environment,
      authority: real.authority,
      subject: token,
    );
  }

  void _forgetOwners() {
    _owners.clear();
    _ownerTokens.clear();
  }

  void _exited(int opening) {
    final exit = _exits.remove(opening);
    if (exit != null && !exit.isCompleted) exit.complete();
  }

  /// A paused menu engine has drained all its work, hidden openings' included.
  void _allExited() {
    for (final exit in _exits.values) {
      if (!exit.isCompleted) exit.complete();
    }
    _exits.clear();
  }

  /// The window owner is gone: nothing may stay subscribed to this session.
  void dispose() {
    retire();
    _allExited();
    unawaited(_accountWork.cancel());
    _removeGenerationWork();
    _forgetOwners();
    _removeModeWork?.call();
    _removeModeWork = null;
  }

  Map<String, Object?> get _state => {
    'kind': 'state',
    'relay': identityHashCode(this),
    'generation': session.activeGeneration,
    'capabilities': [
      for (final name in session.hostCapabilities)
        if (_capabilities.contains(name)) name,
    ],
    'online':
        !session.connectionModeChanging && mode()?.allowsOnlineTraffic == true,
    'self': _self(),
    'countedOnline': countedOnline?.call() ?? true,
    'scmOnly': scmOnly?.call() ?? false,
  };

  String _hello(int opening) {
    // Each page greets; their reads in flight for this opening carry on, and
    // so does a pause question asked of it. A new opening ends that question,
    // but a hidden opening's exit is still awaited (within the same 3 s): its
    // cancelled work may not have exited yet. The next hide replaces it.
    _unsubscribe(endPauses: _opening != opening);
    _opening = opening;
    _eventWork = session.events
        .where((event) => _events.contains(event.name))
        .listen(_publishEvent);
    _capabilityWork = session.capabilitiesChanged.listen(
      (_) => _publishState(),
    );
    _listened = mode()?..addListener(_publishState);
    _profileListened = ownProfileChanges?..addListener(_publishState);
    _presenceListened = presenceChanges?.call()?..addListener(_publishState);
    _removeModeWork ??= session.registerConnectionModeNetworkWork(
      ConnectionModeNetworkWork(
        pause: _pauseMenu,
        reconcile: () async {
          _publish(const {'kind': 'resume'});
          _publishState();
        },
      ),
    );
    return jsonEncode(_state);
  }

  void _publishState() => _publish(_state);

  /// Exactly two fields: no email, contact, token or account id ever leaves.
  Map<String, Object?>? _self() {
    final profile = ownProfile?.call();
    if (profile == null) return null;
    return {
      'displayName': ?profile.displayName,
      'avatarImageData': ?boundedInlineAvatar(profile.avatarImageData),
    };
  }

  /// A mode change waits until the open menu's network work has really stopped.
  /// A hidden menu already aborted its work when it hid, so it is not asked.
  /// An open menu is asked to pause; a hidden one already cancelled its work
  /// and is waited for until it has exited. A menu that hides while being
  /// asked is then waited for the same way. 3 s in all: a stuck menu engine
  /// must not hold the mode change forever.
  Future<void> _pauseMenu() async {
    final clock = Stopwatch()..start();
    Future<T?> bounded<T>(Future<T> work) async {
      final left = _pauseWait - clock.elapsed;
      if (left <= Duration.zero) return null;
      try {
        return await work.timeout(left);
      } on TimeoutException {
        return null;
      }
    }

    if (_opening != null) {
      final id = ++_pauseSerial;
      final done = _pauses[id] = Completer<bool>();
      _publish({'kind': 'pause', 'id': id});
      try {
        if (await bounded(done.future) != false) return;
      } finally {
        _pauses.remove(id);
      }
    }
    // Every hidden opening, including one that hides while this waits.
    while (_exits.isNotEmpty) {
      final pending = [for (final exit in _exits.values) exit.future];
      if (await bounded(Future.wait(pending)) == null) return;
    }
  }

  String? _paused(Object? payload) {
    final pause = payload is String ? _pauses[int.tryParse(payload)] : null;
    if (pause != null && !pause.isCompleted) {
      _allExited();
      pause.complete(true);
    }
    return null;
  }

  void _publishEvent(BridgeEnvelope event) => _publish({
    'kind': 'event',
    'envelope': BridgeEnvelope(
      protocolVersion: event.protocolVersion,
      messageType: event.messageType,
      name: event.name,
      sessionGeneration: event.sessionGeneration,
      sequence: event.sequence,
      // An account event only moves the generation; its body stays here.
      payload: switch (event.name) {
        'marketplace.changed' =>
          _withoutContact(event.payload) as Map<String, Object?>,
        'marketplace.chatPushed' =>
          _withoutContact(event.payload) as Map<String, Object?>,
        _ => const {},
      },
    ).toJson(),
  });

  void _publish(Map<String, Object?> message) {
    final opening = _opening;
    if (opening == null) return;
    unawaited(
      channel
          .invokeMethod<void>('bridgeEvent', {
            'opening': opening,
            'revision': ++_revision,
            'payload': jsonEncode(message),
          })
          .catchError((Object _) {}),
    );
  }

  Future<String> _request(Object? payload) async {
    if (payload is! String) throw PlatformException(code: 'menu.invalidRelay');
    final request = BridgeEnvelope.fromJson(
      (jsonDecode(payload) as Map).cast<String, Object?>(),
    );
    final id = request.correlationId!;
    // One answer per id: a reused id would hide the first one from cancel.
    if (_open.containsKey(id)) {
      return jsonEncode(_error(request, id, 'menu.duplicate_request').toJson());
    }
    if (request.messageType != 'request' ||
        !requests.contains(request.name) ||
        changesImages(request.name, request.payload)) {
      return jsonEncode(_error(request, id, 'menu.relay_not_allowed').toJson());
    }
    if (request.sessionGeneration != session.activeGeneration) {
      return jsonEncode(_answer(request, id, status: 'cancelled').toJson());
    }
    final owner = request.accountContext;
    final realOwner = owner == null ? null : _owners[owner.subject];
    if (owner != null &&
        (realOwner == null ||
            realOwner.environment != owner.environment ||
            realOwner.authority != owner.authority)) {
      // An owner this relay never handed out, or one from before an account
      // change: the page reads the account again.
      return jsonEncode(
        _error(
          request,
          id,
          request.name.startsWith('marketplace.')
              ? 'marketplace.context_changed'
              : request.name.startsWith('communities.') ||
                    request.name.startsWith('officialFleet.')
              ? 'communities.refreshRequired'
              : 'bridge.account_context_required',
        ).toJson(),
      );
    }
    if (session.connectionModeChanging) {
      return jsonEncode(
        _error(request, id, 'bridge.mode_changing', retryable: true).toJson(),
      );
    }
    final operation = session.beginRequest(
      request.name,
      payload: request.payload,
      accountContext: realOwner,
      timeout: _deadline,
    );
    _open[id] = (request.name, operation);
    try {
      final response = await operation.future;
      return jsonEncode(
        _answer(
          request,
          id,
          status: response.status ?? 'ok',
          generation: response.sessionGeneration,
          payload: _visiblePayload(request.name, response.payload),
          owner: _toMenu(response.accountContext),
        ).toJson(),
      );
    } on BridgeRemoteException catch (error) {
      return jsonEncode(
        _error(request, id, error.code, retryable: error.retryable).toJson(),
      );
    } on BridgeCancelledException {
      return jsonEncode(_answer(request, id, status: 'cancelled').toJson());
    } on BridgeStaleGenerationException {
      return jsonEncode(_answer(request, id, status: 'cancelled').toJson());
    } on BridgeTimeoutException {
      return jsonEncode(
        _error(request, id, 'bridge.timeout', retryable: true).toJson(),
      );
    } finally {
      _open.remove(id);
    }
  }

  String? _cancel(Object? payload) {
    if (payload is String) unawaited(_open.remove(payload)?.$2.cancel());
    return null;
  }

  /// Two reads carry more than the hall shows: the account read needs only its
  /// state and owner, and the contact number stays out of this engine.
  static Map<String, Object?> _visiblePayload(
    String name,
    Map<String, Object?> payload,
  ) => switch (name) {
    'account.getCurrent' => {
      'schemaVersion': payload['schemaVersion'],
      'state': payload['state'],
    },
    // Image bytes carry no person; everything else loses the private keys.
    _
        when name.startsWith('imageCache.') ||
            _images.contains(name.split('.').last) =>
      payload,
    _ => _withoutContact(payload) as Map<String, Object?>,
  };

  /// Contact details and account ids (a legacy account's id included) never
  /// enter the menu engine, wherever they sit in a reply or push. None of the
  /// three pages reads these keys.
  static const _contactKeys = {
    'userMobile',
    'email',
    'accountId',
    'legacyAccountId',
    'userId',
    'scmUserId',
    'scmMemberId',
    'memberId',
  };
  static const _images = {'shipImage', 'logo', 'wideImage', 'media'};

  static Object? _withoutContact(Object? value) => switch (value) {
    final Map<dynamic, dynamic> row => <String, Object?>{
      for (final entry in row.entries)
        if (!_contactKeys.contains(entry.key))
          entry.key as String: _withoutContact(entry.value),
    },
    final List<dynamic> rows => [for (final row in rows) _withoutContact(row)],
    _ => value,
  };

  BridgeEnvelope _error(
    BridgeEnvelope request,
    String id,
    String code, {
    bool retryable = false,
  }) => BridgeEnvelope(
    protocolVersion: request.protocolVersion,
    messageType: 'response',
    name: request.name,
    correlationId: id,
    sessionGeneration: request.sessionGeneration,
    payload: const {},
    status: 'error',
    error: BridgeErrorBody(code: code, message: code, retryable: retryable),
  );

  BridgeEnvelope _answer(
    BridgeEnvelope request,
    String id, {
    required String status,
    int? generation,
    Map<String, Object?> payload = const {},
    BridgeAccountContext? owner,
  }) => BridgeEnvelope(
    protocolVersion: request.protocolVersion,
    messageType: 'response',
    name: request.name,
    correlationId: id,
    sessionGeneration: generation ?? request.sessionGeneration,
    accountContext: owner,
    payload: payload,
    status: status,
  );
}
