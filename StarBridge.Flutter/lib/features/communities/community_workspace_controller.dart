import 'dart:async';

import 'package:flutter/foundation.dart';

import 'communities_module.dart';
import 'community_workspace_port.dart';
import 'community_avatar_cache.dart';
import 'community_announcements_controller.dart';
import 'community_announcements_port.dart';
import 'community_chat_controller.dart';
import 'community_chat_port.dart';
import 'community_ships_controller.dart';
import 'community_ships_port.dart';

final class CommunityWorkspaceController extends ChangeNotifier {
  CommunityWorkspaceController(
    this.port,
    this._targetRef, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _subscription = port.invalidations.listen((_) => invalidate());
  }
  final CommunityWorkspacePort port;
  final DateTime Function() _now;
  DateTime? _lastSuccessfulRead;
  String _targetRef;
  String get targetRef => _targetRef;
  String? _nextTargetRef;
  bool get renewingReference => _nextTargetRef != null;
  final avatars = CommunityAvatarCache();
  final _preparedSections = <String>{};
  String? _preparationTarget;
  bool _preparingSection = false;
  bool get needsSectionPreparation =>
      !_closed &&
      workspace != null &&
      error == null &&
      (_preparationTarget != targetRef || _preparedSections.length < 3);

  /// One bounded, low-priority read at a time. The visible view calls this only
  /// while foreground; foreground page entry never waits for this queue.
  Future<void> prepareNextSection(String culture) async {
    if (!needsSectionPreparation ||
        renewingReference ||
        busy ||
        selectedSection == 'manage' ||
        _preparingSection ||
        _pendingImages.isNotEmpty ||
        _chat?.loading == true ||
        _chat?.sending == true ||
        _announcements?.loading == true ||
        _announcements?.saving == true ||
        _ships?.busy == true ||
        _ships?.refreshing == true) {
      return;
    }
    if (_preparationTarget != targetRef) {
      _preparationTarget = targetRef;
      _preparedSections.clear();
    }
    final section = [
      'announcements',
      'chat',
      'ships',
    ].firstWhere((section) => !_preparedSections.contains(section));
    _preparedSections.add(
      section,
    ); // A failed speculative read is not a retry loop.
    _preparingSection = true;
    try {
      switch (section) {
        case 'announcements':
          await announcements?.enter();
        case 'chat':
          await chat?.enter();
        case 'ships':
          final current = ships;
          if (current != null && current.page == null && !current.invalidated) {
            await current.load(selection: CommunityShipQuery(culture: culture));
          }
      }
    } finally {
      _preparingSection = false;
    }
  }

  CommunityChatController? _chat;
  CommunityShipsController? _ships;
  CommunityChatController? get chat {
    final source = port;
    if (_closed ||
        workspace == null ||
        source is! CommunityChatPort ||
        !(source as CommunityChatPort).chatAvailable) {
      return null;
    }
    if (_chat != null && _chat!.targetRef != targetRef) {
      final previous = _chat!;
      _chat = null;
      scheduleMicrotask(previous.dispose);
    }
    return _chat ??= CommunityChatController(
      source as CommunityChatPort,
      targetRef,
      now: _now,
    );
  }

  CommunityShipsController? get ships {
    final source = port;
    if (_closed ||
        workspace == null ||
        source is! CommunityShipsPort ||
        !(source as CommunityShipsPort).shipsAvailable) {
      return null;
    }
    if (_ships != null && _ships!.targetRef != targetRef) {
      final previous = _ships!;
      _ships = null;
      scheduleMicrotask(previous.dispose);
    }
    return _ships ??= CommunityShipsController(
      source as CommunityShipsPort,
      targetRef,
      mediaPort: port,
      avatars: avatars,
      now: _now,
    );
  }

  CommunityAnnouncementsController? _announcements;
  CommunityAnnouncementsController? get announcements {
    final source = port;
    if (_closed ||
        workspace == null ||
        source is! CommunityAnnouncementsPort ||
        !(source as CommunityAnnouncementsPort).announcementsAvailable) {
      return null;
    }
    if (_announcements?.targetRef != targetRef) _clearAnnouncements();
    return _announcements ??= CommunityAnnouncementsController(
      source as CommunityAnnouncementsPort,
      targetRef,
      now: _now,
    );
  }

  void _clearAnnouncements() {
    final previous = _announcements;
    _announcements = null;
    if (previous != null) scheduleMicrotask(previous.dispose);
  }

  late final StreamSubscription<void> _subscription;
  CommunityWorkspace? workspace;
  List<CommunityWorkspaceMember> displayMembers = const [];
  bool _deferMemberOrder = false;

  void setMemberListHovered(bool hovered) {
    if (_closed || _deferMemberOrder == hovered) return;
    _deferMemberOrder = hovered;
    if (!hovered && workspace != null) {
      displayMembers = workspace!.members;
      notifyListeners();
    }
  }

  final Map<String, Uint8List> _images = {};
  final Set<String> _pendingImages = {}, _failedImages = {};
  Uint8List? image(String key) => _images[key];
  bool imageLoading(String key) => _pendingImages.contains(key);
  bool imageFailed(String key) => _failedImages.contains(key);
  String query = '';
  String selectedSection = 'members';
  String? error;
  bool busy = false, mediaFailed = false;
  bool _silentRead = false;
  bool _mediaRequestedByView = false;
  bool _deferredMedia = false;
  Future<void>? _mediaRead;
  int? _mediaReadEpoch;
  bool get showProgress => busy && !_silentRead;
  int _epoch = 0, _mediaEpoch = 0;
  bool _closed = false;

  void _clear() {
    _preparedSections.clear();
    _preparationTarget = null;
    selectedSection = 'members';
    _clearAnnouncements();
    final previousChat = _chat, previousShips = _ships;
    _chat = null;
    _ships = null;
    if (previousChat != null) scheduleMicrotask(previousChat.dispose);
    if (previousShips != null) scheduleMicrotask(previousShips.dispose);
    _deferredMedia = false;
    _lastSuccessfulRead = null;
    _mediaEpoch++;
    workspace = null;
    displayMembers = const [];
    _deferMemberOrder = false;
    _images.clear();
    _pendingImages.clear();
    _failedImages.clear();
    mediaFailed = false;
  }

  /// A containing workflow may also invalidate its organization context.
  void invalidate() {
    if (_closed) return;
    _epoch++;
    _nextTargetRef = null;
    avatars.clear();
    _clear();
    busy = false;
    error = 'identityUnavailable';
    query = '';
    notifyListeners();
  }

  bool _current(int epoch) => !_closed && epoch == _epoch;
  bool _mediaCurrent(int epoch) => !_closed && epoch == _mediaEpoch;
  void _checkMedia(int epoch) {
    if (!_mediaCurrent(epoch)) {
      throw const CommunityFailure('identityUnavailable');
    }
  }

  /// The view may call this only for a confirmed stable organization identity
  /// on the same account-scoped port. Keep the last picture read-only while
  /// revalidating; never transfer permissions or pending reads to the new ref.
  Future<void> renewReference(String next, {bool silent = false}) {
    if (_closed) return Future.value();
    _nextTargetRef = next;
    _mediaEpoch++;
    _pendingImages.clear();
    avatars.retainCompleted();
    return load(silent: silent);
  }

  /// A route return is not a manual refresh. Reuse a recent successful read;
  /// otherwise keep the picture while revalidating it without a loading bar.
  Future<void> enter(String target) async {
    if (_closed) return;
    _mediaRequestedByView = true;
    if (target != (_nextTargetRef ?? targetRef)) {
      await renewReference(target, silent: workspace != null);
      return;
    }
    if (busy) return;
    final age = _lastSuccessfulRead == null
        ? null
        : _now().difference(_lastSuccessfulRead!);
    if (workspace != null &&
        error == null &&
        age != null &&
        !age.isNegative &&
        age < const Duration(seconds: 10)) {
      if (_deferredMedia) {
        _deferredMedia = false;
        await _loadImages(workspace!, _mediaEpoch, const {});
      }
      return;
    }
    await load(silent: workspace != null);
  }

  Future<void> prefetch() async {
    if (_closed || busy || workspace != null) return;
    await load(silent: true, prepareMediaOnly: true);
  }

  bool get needsMediaPreparation =>
      !_closed && _deferredMedia && workspace != null && error == null;

  Future<void> prepareRemainingMedia() async {
    if (!needsMediaPreparation || busy || _pendingImages.isNotEmpty) return;
    _deferredMedia = false;
    await _loadImages(workspace!, _mediaEpoch, const {});
  }

  Future<void> load({
    bool silent = false,
    String? search,
    int? offset,
    Set<String> refreshImages = const {},
    bool prepareMediaOnly = false,
  }) async {
    if (_closed) return;
    final epoch = ++_epoch;
    _lastSuccessfulRead = null;
    final requestedTarget = _nextTargetRef ?? targetRef;
    final renewing = renewingReference;
    final page = offset ?? (search != null ? 0 : workspace?.offset ?? 0);
    query = (search ?? query).trim();
    // Keep the mounted page and its account-scoped media during metadata reads.
    // Authorization failures below still clear all private data immediately.
    // Media belongs to the displayed snapshot. A metadata read does not replace
    // that snapshot yet, so its in-flight images must continue to settle.
    error = null;
    _silentRead = silent && workspace != null;
    busy = true;
    notifyListeners();
    try {
      final result = await port.readWorkspace(requestedTarget, query, page);
      if (!_current(epoch)) return;
      final previousVersions = {
        for (final member in workspace?.members ?? <CommunityWorkspaceMember>[])
          member.memberRef: member.avatarVersion,
      };
      final retryImages = {
        ...refreshImages,
        ..._failedImages,
        if (renewing) ...[
          'logo',
          'banner',
          for (final member in result.members)
            if (member.avatarVersion == null) member.memberRef,
        ],
      };
      final changedImages = {
        for (final member in result.members)
          if (previousVersions.containsKey(member.memberRef) &&
              previousVersions[member.memberRef] != member.avatarVersion)
            member.memberRef,
      };
      final samePage =
          workspace?.query == result.query &&
          workspace?.offset == result.offset;
      if (_deferMemberOrder && samePage) {
        // Keep hit targets steady like WPF, but always use the newest rows.
        // Removed members disappear immediately; never match by display name.
        final remaining = {
          for (final member in result.members) member.memberRef: member,
        };
        displayMembers = List.unmodifiable([
          for (final old in displayMembers)
            if (remaining.containsKey(old.memberRef))
              remaining.remove(old.memberRef)!,
          ...remaining.values,
        ]);
      } else {
        displayMembers = result.members;
      }
      _targetRef = requestedTarget;
      _nextTargetRef = null;
      workspace = result;
      _lastSuccessfulRead = _now();
      final keys = _imageRequests(result).map((request) => request.$1).toSet();
      _images.removeWhere(
        (key, _) =>
            !keys.contains(key) ||
            retryImages.contains(key) ||
            changedImages.contains(key),
      );
      _failedImages.clear();
      mediaFailed = false;
      final mediaEpoch = ++_mediaEpoch;
      _pendingImages.clear();
      _deferredMedia = prepareMediaOnly && !_mediaRequestedByView;
      busy = false;
      notifyListeners();
      await _loadImages(result, mediaEpoch, retryImages);
    } catch (e) {
      if (!_current(epoch)) return;
      error = e is CommunityFailure ? e.code : 'unavailable';
      if (renewing || error != 'unavailable') {
        _epoch++;
        avatars.clear();
        _clear();
      }
      busy = false;
      notifyListeners();
    }
  }

  List<(String, String, String?)> _imageRequests(
    CommunityWorkspace result, {
    bool preparing = false,
  }) {
    // Self first allows the verified account portrait to be reused immediately.
    // Speculation is bounded to eight portraits from the already-read page;
    // never walk member pages or download banners before navigation.
    final members = [
      ...result.members.where((member) => member.hasAvatar && member.isSelf),
      ...result.members.where((member) => member.hasAvatar && !member.isSelf),
    ];
    final portraits = (preparing ? members.take(8) : members).toList();
    return [
      for (final member in portraits.where((member) => member.isSelf))
        (member.memberRef, 'avatar', member.memberRef),
      if (result.hasLogo) ('logo', 'logo', null),
      for (final member in portraits.where((member) => !member.isSelf))
        (member.memberRef, 'avatar', member.memberRef),
      if (!preparing && result.hasBanner) ('banner', 'banner', null),
    ];
  }

  Future<void> _loadImages(
    CommunityWorkspace result,
    int epoch,
    Set<String> retryImages,
  ) async {
    // Entering while warmup is reading images shares that work, then requests
    // only the remainder. Never run a second set of workers for the same epoch.
    final pending = _mediaRead;
    if (pending != null && _mediaReadEpoch == epoch) {
      await pending;
      if (!_mediaCurrent(epoch)) return;
      return _loadImages(result, epoch, retryImages);
    }
    if (!_mediaCurrent(epoch)) return;
    late final Future<void> reading;
    reading = _readImages(result, epoch, retryImages).whenComplete(() {
      if (identical(_mediaRead, reading)) {
        _mediaRead = null;
        _mediaReadEpoch = null;
      }
    });
    _mediaReadEpoch = epoch;
    _mediaRead = reading;
    await reading;
  }

  Future<void> _readImages(
    CommunityWorkspace result,
    int epoch,
    Set<String> retryImages,
  ) async {
    final requests = _imageRequests(result, preparing: _deferredMedia)
        .where(
          (request) =>
              !_images.containsKey(request.$1) &&
              !_failedImages.contains(request.$1),
        )
        .toList();
    _pendingImages.addAll(requests.map((request) => request.$1));
    // Three workers prevent one slow portrait blocking the entire member page.
    // Avatar reads also share a workspace-wide concurrency limit across tabs.
    Future<void> read((String, String, String?) request) async {
      final (key, kind, memberRef) = request;
      _checkMedia(epoch);
      if (_images.containsKey(key)) return;
      try {
        final member = result.members
            .where((v) => v.memberRef == memberRef)
            .firstOrNull;
        final image = member != null
            ? await avatars.member(
                port,
                targetRef,
                member,
                retry: retryImages.contains(key),
              )
            : await assembleCommunityMedia(
                (offset, version) => port.readMedia(
                  targetRef,
                  kind,
                  memberRef: memberRef,
                  offset: offset,
                  version: version,
                ),
                kind,
                memberRef: memberRef,
                checkCurrent: () => _checkMedia(epoch),
              );
        _checkMedia(epoch);
        if (image != null) _images[key] = image;
      } catch (e) {
        _checkMedia(epoch);
        if (e is CommunityFailure &&
            const {
              'notAllowed',
              'identityUnavailable',
              'refreshRequired',
            }.contains(e.code)) {
          rethrow;
        }
        mediaFailed = true;
        _failedImages.add(key);
      } finally {
        if (_mediaCurrent(epoch)) _pendingImages.remove(key);
      }
      notifyListeners();
    }

    var next = 0;
    Future<void> worker() async {
      while (next < requests.length) {
        await read(requests[next++]);
      }
    }

    try {
      await Future.wait(List.generate(3, (_) => worker()), eagerError: true);
    } catch (e) {
      if (!_mediaCurrent(epoch)) return;
      // Current media authorization loss also cancels pending metadata. A late
      // metadata success must not restore a workspace whose access was revoked.
      _epoch++;
      avatars.clear();
      _clear();
      error = e is CommunityFailure ? e.code : 'unavailable';
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _closed = true;
    avatars.dispose();
    _epoch++;
    _clear();
    unawaited(_subscription.cancel());
    // The directory owns the shared port; disposing a workspace must not close it.
    super.dispose();
  }
}
