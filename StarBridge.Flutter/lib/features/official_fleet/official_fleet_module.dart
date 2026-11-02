import 'dart:async';

import 'package:flutter/foundation.dart';

import '../common/organization_communication.dart';
import '../common/organization_communication_port.dart';

import 'official_fleet_models.dart';
import 'official_fleet_members_module.dart';
import 'official_fleet_members_port.dart';
import 'official_fleet_overview_module.dart';
import 'official_fleet_overview_port.dart';
import 'official_fleet_port.dart';
import 'official_fleet_profile_port.dart';
import '../common/organization_governance_port.dart';
import 'official_fleet_auto_activation.dart';
import 'official_fleet_rally.dart';
import 'official_fleet_ships_module.dart';
import 'official_fleet_ships_port.dart';

abstract interface class OfficialFleetModule {
  ValueListenable<OfficialFleetProjection> get projection;

  /// Changes when the authorized viewer/source is invalidated, not on refresh.
  int get contextRevision;
  OfficialFleetOverviewModule get overview;
  OfficialFleetMembersModule get members;

  /// The roster port itself, for side reads with their own query (the chat's
  /// online column) that must not move the member list's page or filter.
  OfficialFleetMembersPort get membersPort;
  OfficialFleetShipsModule get ships;
  OrganizationCommunication get communication;
  OfficialFleetRallyController get rally;

  /// The main fleet page came on screen.
  void entered();

  bool get websiteAvailable;
  Future<bool> openWebsite();

  Future<void> initialize();
  Future<void> refresh();
  void dispose();

  /// Presentation memory for the page header, kept for the client run: true
  /// the first time it is asked on a calendar day, false after that.
  bool takeFirstVisitToday([DateTime? now]);
}

OfficialFleetModule createOfficialFleetModule(
  OfficialFleetPort port,
  OfficialFleetOverviewPort overviewPort,
  OfficialFleetMembersPort membersPort,
  OfficialFleetShipsPort shipsPort, {
  OrganizationCommunicationFactory? communicationFactory,
  OfficialFleetRallyController? rally,
}) => _DefaultOfficialFleetModule(
  port,
  overviewPort,
  membersPort,
  shipsPort,
  communicationFactory,
  rally ??
      OfficialFleetRallyController(const UnavailableOfficialFleetRallyPort()),
);

final class _DefaultOfficialFleetModule implements OfficialFleetModule {
  DateTime? _lastFirstVisit;

  /// When the last available read landed; an unexplained failure keeps that
  /// view for [_retainFor] at most.
  DateTime? _availableAt;
  static const _retainFor = Duration(minutes: 2);

  /// Rereads when an unexplained failure's retained view runs out, so an
  /// old view is never shown past [_retainFor] without a new read.
  Timer? _retainExpiry;

  @override
  bool takeFirstVisitToday([DateTime? now]) {
    final today = now ?? DateTime.now();
    final last = _lastFirstVisit;
    if (last != null &&
        last.year == today.year &&
        last.month == today.month &&
        last.day == today.day) {
      return false;
    }
    _lastFirstVisit = today;
    return true;
  }

  _DefaultOfficialFleetModule(
    this._port,
    OfficialFleetOverviewPort overviewPort,
    this.membersPort,
    OfficialFleetShipsPort shipsPort,
    OrganizationCommunicationFactory? communicationFactory,
    this.rally,
  ) : communication = OrganizationCommunication(communicationFactory),
      overview = createOfficialFleetOverviewModule(overviewPort),
      members = createOfficialFleetMembersModule(membersPort),
      ships = createOfficialFleetShipsModule(shipsPort) {
    _subscription = _port.invalidations.listen((_) {
      if (!_disposed) {
        _contextRevision++;
        unawaited(_refresh(discardContext: true));
      }
    });
    _projection.addListener(_bindRally);
  }

  void _bindRally() {
    final value = _projection.value;
    // A read in progress keeps the current binding; only a settled state moves it.
    if (value.availability == OfficialFleetAvailability.loading) return;
    final fleet = value.availability == OfficialFleetAvailability.available
        ? value.fleet
        : null;
    rally.bind(fleet?.sourceRef, fleetName: fleet?.name);
    if (_entered) unawaited(_autoActivation.enter());
  }

  /// The page is on screen. A fleet that settles later is entered then.
  bool _entered = false;
  @override
  void entered() {
    _entered = true;
    unawaited(_autoActivation.enter());
  }

  late final _autoActivation = OfficialFleetAutoActivation(
    port: () => communication.governance,
    context: () {
      final value = _projection.value;
      return (
        _contextRevision,
        value.availability == OfficialFleetAvailability.available
            ? value.fleet?.sourceRef
            : null,
      );
    },
    onActivated: (authority) {
      unawaited(rally.refresh(eligibility: true));
      unawaited(
        communication.recheckAnnouncementManagement(
          allowed: authority.capabilities.any(
            (d) =>
                d.key == 'announcements.manage' &&
                d.state == OrganizationDecisionState.allowed,
          ),
        ),
      );
    },
  );

  final OfficialFleetPort _port;
  int _contextRevision = 0;
  @override
  int get contextRevision => _contextRevision;
  @override
  final OfficialFleetOverviewModule overview;
  @override
  final OfficialFleetMembersModule members;
  @override
  final OfficialFleetMembersPort membersPort;
  @override
  final OfficialFleetShipsModule ships;
  @override
  final OrganizationCommunication communication;
  @override
  final OfficialFleetRallyController rally;
  final ValueNotifier<OfficialFleetProjection> _projection = ValueNotifier(
    const OfficialFleetProjection.loading(),
  );
  late final StreamSubscription<void> _subscription;
  bool _initialized = false;
  Future<void>? _readTask;
  int _requestRevision = 0;
  int _completedRevision = -1;
  bool _disposed = false;

  @override
  ValueListenable<OfficialFleetProjection> get projection => _projection;

  @override
  bool get websiteAvailable {
    final port = _port;
    return !_disposed &&
        _projection.value.fleet != null &&
        _projection.value.availability == OfficialFleetAvailability.available &&
        port is OfficialFleetWebsitePort &&
        (port as OfficialFleetWebsitePort).supportsWebsite;
  }

  @override
  Future<bool> openWebsite() async {
    if (!websiteAvailable) return false;
    final fleet = _projection.value.fleet!;
    final revision = _contextRevision;
    try {
      final opened = await (_port as OfficialFleetWebsitePort).openWebsite(
        fleet.sid,
      );
      return opened &&
          !_disposed &&
          revision == _contextRevision &&
          _projection.value.fleet?.sourceRef == fleet.sourceRef;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> initialize() async {
    if (_disposed || _initialized) {
      return;
    }
    _initialized = true;
    await refresh();
  }

  @override
  Future<void> refresh() => _refresh(discardContext: false);

  Future<void> _refresh({required bool discardContext}) {
    if (_disposed) {
      return Future<void>.value();
    }
    if (!discardContext && _readTask != null) return _readTask!;
    ++_requestRevision;
    unawaited(_cancelProfileRead());
    if (discardContext) {
      communication.reset();
      overview.reset();
      members.reset();
      ships.reset();
    }
    final previous = _projection.value;
    _projection.value =
        !discardContext &&
            previous.availability == OfficialFleetAvailability.available
        ? OfficialFleetProjection.refreshing(previous)
        : const OfficialFleetProjection.loading();
    if (_readTask != null) return _readTask!;
    final completion = Completer<void>();
    _readTask = completion.future;
    unawaited(_runReadLoop(completion));
    return completion.future;
  }

  Future<void> _runReadLoop(Completer<void> completion) async {
    Object? failure;
    StackTrace? trace;
    try {
      do {
        await _readLatest();
      } while (!_disposed && _completedRevision != _requestRevision);
    } on Object catch (error, stack) {
      failure = error;
      trace = stack;
    }
    if (identical(_readTask, completion.future)) _readTask = null;
    if (failure == null) {
      completion.complete();
    } else {
      completion.completeError(failure, trace);
    }
  }

  Future<void> _cancelProfileRead() async {
    final port = _port;
    if (port is! OfficialFleetProfilePort) return;
    try {
      await (port as OfficialFleetProfilePort).cancelProfileRead();
    } on Object {
      /* Read retirement is local and final. */
    }
  }

  Future<void> _readLatest() async {
    while (!_disposed) {
      final revision = _requestRevision;
      OfficialFleetSnapshot snapshot;
      try {
        snapshot = await _port.read();
      } on Object {
        snapshot = const OfficialFleetSnapshot.unavailable(
          failureKey: 'officialFleet.error.unavailable',
        );
      }
      if (_disposed) {
        return;
      }
      if (revision != _requestRevision) {
        continue;
      }
      final previous = _projection.value;
      final recent =
          _availableAt != null &&
          DateTime.now().difference(_availableAt!) < _retainFor;
      if (snapshot.availability == OfficialFleetAvailability.unavailable &&
          (snapshot.transientFailure || recent) &&
          !snapshot.discardContext &&
          previous.availability == OfficialFleetAvailability.available) {
        communication.retainReadOnly();
        _projection.value = OfficialFleetProjection.retained(
          previous,
          failureKey: snapshot.failureKey ?? 'officialFleet.error.transient',
        );
        _completedRevision = revision;
        if (!snapshot.transientFailure && _retainExpiry == null) {
          final left = _retainFor - DateTime.now().difference(_availableAt!);
          _retainExpiry = Timer(left.isNegative ? Duration.zero : left, () {
            _retainExpiry = null;
            _availableAt = null;
            if (!_disposed) unawaited(refresh());
          });
        }
        return;
      }
      if (snapshot.availability != OfficialFleetAvailability.available) {
        // Unknown reads hide the workspace but preserve a protected draft.
        // Explicit loss of membership/account drops the scope;
        // account invalidations already discard it before the request starts.
        if (snapshot.availability == OfficialFleetAvailability.signedOut ||
            snapshot.availability == OfficialFleetAvailability.notMember ||
            snapshot.discardContext) {
          communication.reset();
        } else {
          communication.retainReadOnly();
        }
        overview.reset();
        members.reset();
        ships.reset();
      }
      final previousSource = _projection.value.fleet?.sourceRef;
      final sourceRef = snapshot.fleet?.sourceRef;
      final sameSource = sourceRef != null && sourceRef == previousSource;
      if (sourceRef != null && !sameSource) {
        // A different fleet is a different read and collaboration context.
        // Keep an existing same-source draft after a failed identity read;
        // OrganizationCommunication.open itself checks the stable source.
        overview.reset();
        members.reset();
        ships.reset();
        if (previousSource != null) {
          ++_contextRevision;
          communication.reset();
        }
      }
      final profilePort = _port;
      final deferred =
          snapshot.availability == OfficialFleetAvailability.available &&
          snapshot.profileReadState == OfficialFleetProfileReadState.deferred &&
          profilePort is OfficialFleetProfilePort &&
          (profilePort as OfficialFleetProfilePort).supportsDeferredProfile;
      _projection.value = OfficialFleetProjection.fromSnapshot(
        snapshot,
        previous: sameSource ? previous : null,
        isProfileReading: deferred,
      );
      _availableAt =
          snapshot.availability == OfficialFleetAvailability.available
          ? DateTime.now()
          : null;
      _retainExpiry?.cancel();
      _retainExpiry = null;
      if (revision == _requestRevision &&
          !_disposed &&
          snapshot.fleet != null) {
        final sourceRef = snapshot.fleet!.sourceRef;
        unawaited(
          Future.wait([
            sameSource ? overview.refresh() : overview.open(sourceRef),
            sameSource ? members.refresh() : members.open(sourceRef),
            sameSource ? ships.refresh() : ships.open(sourceRef),
            sameSource
                ? communication.refresh(sourceRef)
                : communication.open(sourceRef),
          ]),
        );
        if (deferred) {
          unawaited(
            _readPublicProfile(
              profilePort as OfficialFleetProfilePort,
              revision,
              snapshot.fleet!.sourceRef,
              snapshot.fleet!.sid,
            ),
          );
        }
      }
      // A listener can invalidate the identity while processing this projection.
      if (revision == _requestRevision) {
        _completedRevision = revision;
        return;
      }
    }
  }

  Future<void> _readPublicProfile(
    OfficialFleetProfilePort port,
    int revision,
    String sourceRef,
    String sid,
  ) async {
    OfficialFleetPublicProfile result;
    try {
      result = await port.readProfile(sourceRef);
    } on Object {
      result = OfficialFleetPublicProfile(
        sourceRef: sourceRef,
        state: OfficialFleetProfileReadState.unavailable,
      );
    }
    if (_disposed || revision != _requestRevision) return;
    final previous = _projection.value;
    final fleet = previous.fleet;
    if (previous.availability != OfficialFleetAvailability.available ||
        fleet == null ||
        fleet.sourceRef != sourceRef ||
        fleet.sid != sid) {
      return;
    }
    if (result.discarded) {
      _projection.value = OfficialFleetProjection.retained(
        previous,
        failureKey: previous.failureKey,
      );
      return;
    }
    if (result.ownerUnavailable) {
      if (result.discardContext) {
        ++_contextRevision;
        communication.reset();
        overview.reset();
        members.reset();
        ships.reset();
        _projection.value = OfficialFleetProjection.fromSnapshot(
          const OfficialFleetSnapshot.signedOut(),
        );
      } else {
        communication.retainReadOnly();
        if (result.state == OfficialFleetProfileReadState.transientFailure) {
          _projection.value = OfficialFleetProjection.retained(
            previous,
            failureKey: result.failureKey ?? 'officialFleet.error.transient',
          );
        } else {
          overview.reset();
          members.reset();
          ships.reset();
          _projection.value = OfficialFleetProjection.fromSnapshot(
            OfficialFleetSnapshot.unavailable(
              failureKey:
                  result.failureKey ?? 'officialFleet.error.unavailable',
            ),
          );
        }
      }
      return;
    }
    var state = result.state;
    if (result.sourceRef != sourceRef ||
        result.sid != null && result.sid != sid ||
        state == OfficialFleetProfileReadState.available &&
            (result.profile == null || result.observedAtUtc == null) ||
        state == OfficialFleetProfileReadState.unknown ||
        state == OfficialFleetProfileReadState.deferred) {
      state = OfficialFleetProfileReadState.invalid;
    }
    _projection.value = OfficialFleetProjection.fromSnapshot(
      OfficialFleetSnapshot.available(
        fleet: OfficialFleetSummary.withProfile(
          fleet,
          state == OfficialFleetProfileReadState.available
              ? result.profile
              : null,
        ),
        freshness: previous.freshness,
        observedAtUtc: previous.observedAtUtc,
        resourceVersion: previous.resourceVersion,
        profileReadState: state,
        profileObservedAtUtc: state == OfficialFleetProfileReadState.available
            ? result.observedAtUtc
            : null,
      ),
      previous: previous,
    );
  }

  @override
  void dispose() {
    _autoActivation.close();
    if (_disposed) {
      return;
    }
    _disposed = true;
    _retainExpiry?.cancel();
    unawaited(_cancelProfileRead());
    unawaited(_subscription.cancel());
    _projection.dispose();
    overview.dispose();
    members.dispose();
    ships.dispose();
    communication.dispose();
    rally.dispose();
    unawaited(_port.close());
  }
}
