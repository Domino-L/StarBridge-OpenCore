import 'dart:async';

const loadingMetricsZoneKey = #starBridgeLoadingMetrics;
const _backgroundReadZoneKey = #starBridgeLoadingBackgroundRead;

enum LoadingReadRetirement { cancelled, invalidated, disposed }

typedef LoadingReadRelease = void Function(LoadingReadRetirement reason);

/// Only fixed source labels and numeric measurements may enter this recorder.
/// Never pass payloads, errors, identities, URLs, paths or correlation IDs.
final class LoadingMetrics {
  static LoadingMetrics? get current =>
      Zone.current[loadingMetricsZoneKey] as LoadingMetrics?;
  LoadingMetrics({
    required this.nowUs,
    required this.write,
    this.maxEvents = 50000,
  });
  final int Function() nowUs;
  final void Function(Map<String, Object> event) write;
  final int maxEvents;
  int _events = 0, _nextSpan = 0;
  int _nextImageTransfer = 0;
  bool _imageTransferRecorderPresent = false;
  int _visit = 0;
  String? _activeRoute;
  final _routeHistory = <({int us, String route, int visit})>[];
  final _pendingContent = <Map<String, Object>>[];
  final _pendingVisual = <Map<String, Object>>[];
  final _rendered = <(String, int), LoadingRenderedContent>{};
  final _transports = <int, int?>{};
  final _pageReads = <int, int>{};
  Map<String, Object>? _menuDrag;
  final _pendingMenuDrag = <Map<String, Object>>[];
  bool _stopped = false;
  bool get stopped => _stopped;
  void stop() {
    _stopped = true;
    _pendingContent.clear();
    _pendingVisual.clear();
    _transports.clear();
    _pageReads.clear();
    _menuDrag = null;
    _pendingMenuDrag.clear();
  }

  void _record(Map<String, Object> event) {
    if (_stopped) return;
    if (_events++ >= maxEvents) {
      _stopped = true;
      return;
    }
    try {
      write({'us': nowUs(), ...event});
    } catch (_) {
      // Measurement must never affect product startup or a request result.
      _stopped = true;
    }
  }

  /// A community image already shown in this process fell back to loading
  /// ('redecode') or to its placeholder ('cleared'). Fixed labels only.
  void imageRegressed(
    LoadingImageSurface surface,
    LoadingImageRegression cause,
  ) => _record({
    'kind': 'imageRegressed',
    'route': _activeRoute ?? '',
    'visit': _visit,
    'surface': surface.name,
    'cause': cause.name,
  });

  void mark(LoadingMilestone milestone, {int? wallUtcUs, int? clockOriginUs}) =>
      _record({
        'kind': milestone.name,
        'wallUtcUs': ?wallUtcUs,
        'clockOriginUs': ?clockOriginUs,
      });

  /// Numeric presentation generations only, never the snapshot's scope or keys.
  /// The entry's monotonic clock origin aligns independent Flutter engines.
  void auxiliaryOpening(
    LoadingAuxiliarySurface surface,
    LoadingAuxiliaryPhase phase,
    int opening,
  ) {
    if (opening <= 0) return;
    _record({
      'kind': 'auxiliaryOpening',
      'surface': surface.name,
      'route': surface.route,
      'phase': phase.name,
      'opening': opening,
      'visit': ?(phase == LoadingAuxiliaryPhase.snapshot
          ? visitFor(surface.route)
          : null),
    });
  }

  /// Native window + engine creation (first opening only), wall-clock µs.
  void auxiliaryEngine(LoadingAuxiliarySurface surface, int from, int to) {
    if (from <= 0 || to < from) return;
    _record({
      'kind': 'auxiliaryEngine',
      'surface': surface.name,
      'beginWallUs': from,
      'endWallUs': to,
    });
  }

  void auxiliaryLifecycle(
    LoadingAuxiliarySurface surface, {
    required String? state,
    required bool framesEnabled,
  }) {
    if (state != null &&
        !const {
          'resumed',
          'inactive',
          'hidden',
          'paused',
          'detached',
        }.contains(state)) {
      return;
    }
    _record({
      'kind': 'auxiliaryLifecycle',
      'surface': surface.name,
      'state': state ?? 'unknown',
      'framesEnabled': framesEnabled,
    });
  }

  void menuOpening(
    LoadingMenuPhase phase,
    int request, {
    int? opening,
    bool? visible,
    LoadingMenuHideReason? reason,
  }) {
    if (request <= 0) return;
    _record({
      'kind': 'menuOpening',
      'phase': phase.name,
      'request': request,
      'opening': ?opening,
      'visible': ?visible,
      'reason': ?reason?.name,
    });
  }

  void menuSurface({required int opening, required bool wanted}) {
    if (opening < 0) return;
    _menuDrag = null;
    _pendingMenuDrag.clear();
    _record({'kind': 'menuSurface', 'opening': opening, 'wanted': wanted});
  }

  /// Coalesced handler timestamps, never device timestamps or coordinates.
  /// This measures framework/raster work, not physical pointer-to-pixel latency.
  void menuDragUpdate({required bool resize}) {
    if (_stopped || _activeRoute != '/menu') return;
    final us = nowUs();
    final mark = _menuDrag ??= {
      'visit': _visit,
      'firstHandledUs': us,
      'updates': 0,
      'resizeUpdates': 0,
    };
    mark['lastHandledUs'] = us;
    mark['updates'] = (mark['updates']! as int) + 1;
    if (resize) mark['resizeUpdates'] = (mark['resizeUpdates']! as int) + 1;
  }

  void menuDragBuilt() {
    final mark = _menuDrag;
    _menuDrag = null;
    if (mark == null || _stopped || mark['visit'] != visitFor('/menu')) return;
    mark['builtUs'] = nowUs();
    _record({'kind': 'menuDragBuild', ...mark});
    _pendingMenuDrag.add(mark);
    if (_pendingMenuDrag.length > 128) _pendingMenuDrag.removeAt(0);
  }

  void _menuDragRaster(
    int buildStartUs,
    int buildFinishUs,
    int rasterFinishUs,
  ) {
    if (_pendingMenuDrag.isEmpty || _stopped) return;
    for (final mark in _pendingMenuDrag.toList()) {
      final built = mark['builtUs']! as int;
      if (built < buildStartUs) {
        _pendingMenuDrag.remove(mark);
      } else if (built <= buildFinishUs) {
        _record({
          'kind': 'menuDragRaster',
          ...mark,
          'us': rasterFinishUs,
          'firstHandledToRasterUs':
              rasterFinishUs - (mark['firstHandledUs']! as int),
          'lastHandledToRasterUs':
              rasterFinishUs - (mark['lastHandledUs']! as int),
        });
        _pendingMenuDrag.remove(mark);
      }
    }
  }

  void stage(String value) {
    if (_stages.contains(value)) _record({'kind': 'startup', 'stage': value});
  }

  void route(String value) {
    // Parameterized/deep-link strings are not safe diagnostic labels.
    if (!_routes.contains(value) || _stopped) return;
    _activeRoute = value;
    _visit++;
    _routeHistory.add((us: nowUs(), route: value, visit: _visit));
    if (_routeHistory.length > 256) _routeHistory.removeAt(0);
    _record({'kind': 'route', 'route': value, 'visit': _visit});
  }

  /// Numeric facts at the existing account readiness boundary. No identity or
  /// failure detail is retained and this observer never advances readiness.
  void accountState({
    required int generation,
    required bool busy,
    required bool refreshing,
    required bool resolved,
    required bool failed,
    required bool cached,
    required bool scm,
    required bool legacy,
  }) => _record({
    'kind': 'accountState',
    'generation': generation,
    'busy': busy,
    'refreshing': refreshing,
    'resolved': resolved,
    'failed': failed,
    'cached': cached,
    'scm': scm,
    'legacy': legacy,
  });

  int? visitFor(String route) =>
      !_stopped && route == _activeRoute ? _visit : null;

  LoadingRenderedContent? renderedFor(String route, int visit) =>
      _rendered[(route, visit)];

  int pendingTransportsFor(int visit) =>
      _transports.values.where((value) => value == visit).length;

  /// Unknown callers remain conservative page blockers. Only an explicitly
  /// identified passive owner can opt its reads out; all transport statistics
  /// remain intact. Foreground borrowers of shared passive work join separately.
  int pendingPageReadsFor(int visit) =>
      _pageReads.values.where((value) => value == visit).length;

  T background<T>(T Function() action) => _readScope(action, background: true);

  /// Explicit foreground borrowers can override a passive notification's zone.
  T foreground<T>(T Function() action) => _readScope(action, background: false);

  T _readScope<T>(T Function() action, {required bool background}) {
    final previous = Zone.current[_backgroundReadZoneKey];
    final scope = <LoadingMetrics, bool>{
      if (previous is Map<LoadingMetrics, bool>) ...previous,
      this: background,
    };
    return runZoned(
      action,
      zoneValues: {
        _backgroundReadZoneKey: Map<LoadingMetrics, bool>.unmodifiable(scope),
      },
    );
  }

  void tour(LoadingTourPhase phase, {String? route, int round = 0}) {
    if (route != null && !_routes.contains(route)) return;
    _record({
      'kind': 'tour',
      'phase': phase.name,
      'route': ?route,
      'round': round,
    });
  }

  void contentPainted(
    String route,
    LoadingContentStatus status, {
    required int items,
  }) => _painted(route, status, items);

  void visualPainted(
    String route,
    LoadingVisualPart part,
    LoadingContentStatus status, {
    required int items,
  }) => _painted(route, status, items, part: part);

  void _painted(
    String route,
    LoadingContentStatus status,
    int items, {
    LoadingVisualPart? part,
  }) {
    if (_stopped || route != _activeRoute || !_routes.contains(route)) return;
    final mark = <String, Object>{
      'builtUs': nowUs(),
      'route': route,
      'visit': _visit,
      'status': status.name,
      'items': items < 0 ? 0 : items,
      'part': ?part?.name,
    };
    _record({'kind': part == null ? 'contentPaint' : 'visualPaint', ...mark});
    final pending = part == null ? _pendingContent : _pendingVisual;
    pending.add(mark);
    final capacity = part == null ? 128 : 256;
    if (pending.length > capacity) pending.removeAt(0);
  }

  ({String route, int visit})? _routeAt(int us) {
    for (final entry in _routeHistory.reversed) {
      if (entry.us <= us) return (route: entry.route, visit: entry.visit);
    }
    return null;
  }

  void frame({
    required int buildUs,
    required int rasterUs,
    required int totalUs,
    int? vsyncUs,
    int? buildStartUs,
    int? buildFinishUs,
    int? rasterFinishUs,
  }) {
    // Callbacks may arrive after navigation. Attribute the scene by its actual
    // build finish, including a destination first built in this very frame.
    final location = _routeAt(buildFinishUs ?? vsyncUs ?? nowUs());
    _record({
      'kind': 'frame',
      'us': ?vsyncUs,
      'route': ?location?.route,
      'visit': ?location?.visit,
      'buildUs': buildUs,
      'rasterUs': rasterUs,
      'totalUs': totalUs,
    });
    if (buildStartUs == null ||
        buildFinishUs == null ||
        rasterFinishUs == null) {
      return;
    }
    _menuDragRaster(buildStartUs, buildFinishUs, rasterFinishUs);
    if ((_pendingContent.isEmpty && _pendingVisual.isEmpty) || _stopped) return;
    final painted = [..._pendingContent, ..._pendingVisual].where((mark) {
      final built = mark['builtUs']! as int;
      return built >= buildStartUs && built <= buildFinishUs;
    }).toList();
    for (final mark in painted) {
      if (mark.containsKey('part')) {
        _record({'kind': 'visualRaster', 'us': rasterFinishUs, ...mark});
        _pendingVisual.remove(mark);
        continue;
      }
      _record({'kind': 'contentRaster', 'us': rasterFinishUs, ...mark});
      _rendered[(
        mark['route']! as String,
        mark['visit']! as int,
      )] = LoadingRenderedContent(
        LoadingContentStatus.values.byName(mark['status']! as String),
        rasterFinishUs,
        mark['items']! as int,
      );
      if (_rendered.length > 256) _rendered.remove(_rendered.keys.first);
      _pendingContent.remove(mark);
    }
    // Missing/dropped frame evidence is never promoted to a rendered milestone.
    _pendingContent.removeWhere(
      (mark) => (mark['builtUs']! as int) < buildStartUs,
    );
    _pendingVisual.removeWhere(
      (mark) => (mark['builtUs']! as int) < buildStartUs,
    );
  }

  void memory({
    required int rssBytes,
    required int imageBytes,
    required int liveImages,
    required int pendingImages,
  }) => _record({
    'kind': 'memory',
    'rssBytes': rssBytes,
    'imageBytes': imageBytes,
    'liveImages': liveImages,
    'pendingImages': pendingImages,
  });

  /// Anonymous image attempts. These receipts never add a page-read lease.
  void imageTransferRecorderPresent() {
    if (_stopped || _imageTransferRecorderPresent) return;
    _imageTransferRecorderPresent = true;
    _record({'kind': 'imageTransferMetrics', 'version': 1});
  }

  int? imageTransferStarted({required int hop}) {
    if (_stopped || hop < 0 || hop > 5) return null;
    imageTransferRecorderPresent();
    if (_stopped) return null;
    final id = ++_nextImageTransfer;
    _record({
      'kind': 'imageTransferStart',
      'id': id,
      'hop': hop,
      'visit': ?(_visit > 0 ? _visit : null),
    });
    return _stopped ? null : id;
  }

  void imageTransferFinished({
    required int id,
    required int statusCode,
    required int consumedBodyBytes,
    required bool bodyComplete,
    required LoadingImageBodyEncoding encoding,
  }) {
    if (_stopped || id <= 0 || consumedBodyBytes < 0) return;
    _record({
      'kind': 'imageTransferEnd',
      'id': id,
      'statusCode': statusCode >= 100 && statusCode <= 599 ? statusCode : 0,
      'consumedBodyBytes': consumedBodyBytes,
      'bodyComplete': bodyComplete,
      'encoding': encoding.name,
      if (bodyComplete && encoding == LoadingImageBodyEncoding.encoded)
        'encodedResponseBodyBytes': consumedBodyBytes,
    });
  }

  LoadingReadRelease observe(
    String name,
    Future<Object?> future, {
    required bool transport,
  }) {
    if (_stopped) return (_) {};
    final started = nowUs(), id = ++_nextSpan;
    final operation = _operations[name] ?? 'other';
    final route = _activeRoute;
    final visit = route == null ? null : _visit;
    final scope = Zone.current[_backgroundReadZoneKey];
    final intent = scope is Map<LoadingMetrics, bool> ? scope[this] : null;
    final background = intent == true;
    final activity = intent == null
        ? 'unclassified'
        : background
        ? 'background'
        : 'foreground';
    final kind = transport ? 'transport' : 'consumer';
    if (transport) _transports[id] = visit;
    if (!background && visit != null) _pageReads[id] = visit;
    _record({
      'kind': '${kind}Start',
      'operation': operation,
      'span': id,
      'activity': activity,
      'route': ?route,
      'visit': ?visit,
    });
    future.then(
      (_) {
        _transports.remove(id);
        _pageReads.remove(id);
        _record({
          'kind': kind,
          'operation': operation,
          'span': id,
          'activity': activity,
          'route': ?route,
          'visit': ?visit,
          'durationUs': nowUs() - started,
          'outcome': 'ok',
        });
      },
      onError: (Object error, StackTrace stack) {
        _transports.remove(id);
        _pageReads.remove(id);
        _record({
          'kind': kind,
          'operation': operation,
          'span': id,
          'activity': activity,
          'route': ?route,
          'visit': ?visit,
          'durationUs': nowUs() - started,
          'outcome': 'error',
        });
      },
    );
    return (reason) {
      if (_stopped || _pageReads.remove(id) == null) return;
      // Retiring a logical page lease never cancels or completes business work.
      // The original future still reports its actual outcome and physical IO.
      _record({
        'kind': 'readLeaseRetired',
        'operation': operation,
        'span': id,
        'activity': activity,
        'reason': reason.name,
        'route': ?route,
        'visit': ?visit,
      });
    };
  }

  static const _stages = {
    'connecting',
    'preferences',
    'account',
    'ready',
    'hostUnavailable',
    'preferencesUnavailable',
    'accountUnavailable',
    'complete',
  };
  static const _routes = {
    '/',
    '/rooms',
    '/operations',
    '/fleet',
    '/marketplace',
    '/communities',
    '/hangar',
    '/overlay',
    '/tools',
    '/tools/exec-hangar',
    '/settings/privacy',
    '/settings',
    '/settings/account',
    '/profile',
    '/friends',
    '/messages',
    '/notifications',
    '/achievements',
    '/menu',
  };
  static const _operations = {
    'host.hello': 'host.hello',
    'host.ready': 'host.ready',
    // Recurring background reads that previously all reported as "other"
    // (about 860 calls per 7-minute tour, 2026-10-19 device traces).
    'social.wait': 'social.wait',
    'presence.activity': 'presence.activity',
    'privacy.localRead': 'privacy.read',
    'privacy.communityTargets': 'privacy.targets',
    'privacy.officialFleetRead': 'privacy.fleetRead',
    'eventSharing.read': 'sharing.events',
    'friendSharing.read': 'sharing.friends',
    'gameIdVisibility.read': 'sharing.gameId',
    'accountSafety.read': 'account.safety',
    'account.offlineData.read': 'account.offlineRead',
    'profile.readDisplayCache': 'profile.displayCache',
    'friends.readPage': 'friends.page',
    'directMessages.privacyRead': 'messages.privacy',
    'friendRequests.privacyRead': 'friends.privacy',
    'communities.announcements': 'communities.announcements',
    'communities.logo': 'communities.logo',
    'communities.shipImage': 'communities.shipImage',
    'communities.profile': 'communities.profile',
    'overlay.appearanceProgress.read': 'overlay.progress',
    'playReminder.read': 'playReminder.read',
    'onboarding.startup.read': 'onboarding.startup',
    'diagnostics.getRuntimeFacts': 'diagnostics.facts',
    'applicationUpdates.check': 'updates.check',
    // Remaining recurring/page reads that still reported as "other" in the
    // 2026-10-20 08:40 device batch (20-39 per 30 s). Labels only.
    'account.avatar.read': 'account.avatar.read',
    'account.compatibility.read': 'account.compatibility.read',
    'account.read': 'account.read',
    'account.readAvatar': 'account.readAvatar',
    'applicationPreferences.read': 'applicationPreferences.read',
    'communities.previewInvite': 'communities.previewInvite',
    'communities.wait': 'communities.wait',
    'dataLocation.getMigrationResult': 'dataLocation.getMigrationResult',
    'diagnostics.getDataLocation': 'diagnostics.getDataLocation',
    'diagnostics.getLocalEvents': 'diagnostics.getLocalEvents',
    'diagnostics.getOverlayRuntimeStatus':
        'diagnostics.getOverlayRuntimeStatus',
    'diagnostics.getSafeSummary': 'diagnostics.getSafeSummary',
    'eventSharing.settings': 'eventSharing.settings',
    'execHangar.gameOverlay.read': 'execHangar.gameOverlay.read',
    'execHangar.preview': 'execHangar.preview',
    'friendSharing.settings': 'friendSharing.settings',
    'friends.readDisplay': 'friends.readDisplay',
    'friends.readPages': 'friends.readPages',
    'gameIdVisibility.settings': 'gameIdVisibility.settings',
    'gameplayTime.history': 'gameplayTime.history',
    'gameplayTime.read': 'gameplayTime.read',
    'helpSupport.history': 'helpSupport.history',
    'imageCache.read': 'imageCache.read',
    'legal.getClientLicense': 'legal.getClientLicense',
    'legal.readTestBuildNotice': 'legal.readTestBuildNotice',
    'menuBrowserResume.read': 'menuBrowserResume.read',
    'menuHotkey.settings.get': 'menuHotkey.settings.get',
    'menuScreenshotDirectory.read': 'menuScreenshotDirectory.read',
    'notificationAudio.read': 'notificationAudio.read',
    'notificationPolicies.read': 'notificationPolicies.read',
    'notificationSettings.read': 'notificationSettings.read',
    'officialFleet.getMembers': 'officialFleet.getMembers',
    'officialFleet.getRuntimeMembers': 'officialFleet.getRuntimeMembers',
    'officialFleet.read': 'officialFleet.read',
    'officialFleet.readGovernanceContext':
        'officialFleet.readGovernanceContext',
    'officialFleet.ships': 'officialFleet.ships',
    'officialFleet.wait': 'officialFleet.wait',
    'officialFleet.waitRuntimeActivity': 'officialFleet.waitRuntimeActivity',
    'onboarding.deviceReview.read': 'onboarding.deviceReview.read',
    'onboarding.localStatistics.historyRead':
        'onboarding.localStatistics.historyRead',
    'onboarding.localStatistics.read': 'onboarding.localStatistics.read',
    'onboarding.mode.read': 'onboarding.mode.read',
    'onboarding.nativeOverlayObservation.read':
        'onboarding.nativeOverlayObservation.read',
    'onboarding.onlineInstallation.read': 'onboarding.onlineInstallation.read',
    'onboarding.onlineReview.read': 'onboarding.onlineReview.read',
    'onboarding.read': 'onboarding.read',
    'overlay.runtime.getState': 'overlay.runtime.getState',
    'overlay.settings': 'overlay.settings',
    'overlayRoster.read': 'overlayRoster.read',
    'overlayScenes.read': 'overlayScenes.read',
    'partyRooms.read': 'partyRooms.read',
    'personalProfile.readBackground': 'personalProfile.readBackground',
    'personalProfile.readVisibility': 'personalProfile.readVisibility',
    'playerActivity.read': 'playerActivity.read',
    'presence.read': 'presence.read',
    'profile.getDisplayData': 'profile.getDisplayData',
    'profile.getTimeZoneDirectory': 'profile.getTimeZoneDirectory',
    'scmAchievements.read': 'scmAchievements.read',
    'users.profile': 'users.profile',
    'account.getCurrent': 'account.current',
    'profile.getSelf': 'account.profile',
    'gameIdentity.getPolicy': 'account.identityPolicy',
    'account.getCompatibilityState': 'account.compatibility',
    'applicationPreferences.get': 'preferences.read',
    'applicationPreferences.menu.get': 'menuPreferences.read',
    'applicationPreferences.menu.begin': 'menu.begin',
    'applicationPreferences.menu.startup': 'menu.startup',
    'applicationPreferences.menu.finish': 'menu.finish',
    'menuHotkey.attach': 'menu.attach',
    'host.getGamePresence': 'gamePresence.read',
    'personalProfile.localRead': 'profile.localRead',
    'personalProfile.getSelf': 'profile.remoteRead',
    'officialFleet.getCurrent': 'fleet.read',
    'officialFleet.getIdentity': 'fleet.identity.read',
    'officialFleet.getPublicProfile': 'fleet.profile.read',
    'hangarReader.inventory': 'hangar.inventory',
    'hangar.unknown.pageRead': 'hangar.unknown.pageRead',
    'hangar.unknown.bind': 'hangar.unknown.bind',
    'hangar.unknown.inventory': 'hangar.unknown.inventory',
    'hangar.unknown.inventoryProjection': 'hangar.unknown.inventoryProjection',
    'hangar.unknown.legacyRead': 'hangar.unknown.legacyRead',
    'hangar.unknown.legacyProjection': 'hangar.unknown.legacyProjection',
    'hangar.feature.pageRead': 'hangar.feature.pageRead',
    'hangar.feature.bind': 'hangar.feature.bind',
    'hangar.feature.inventory': 'hangar.feature.inventory',
    'hangar.feature.inventoryProjection': 'hangar.feature.inventoryProjection',
    'hangar.feature.legacyRead': 'hangar.feature.legacyRead',
    'hangar.feature.legacyProjection': 'hangar.feature.legacyProjection',
    'hangar.profile.pageRead': 'hangar.profile.pageRead',
    'hangar.profile.bind': 'hangar.profile.bind',
    'hangar.profile.inventory': 'hangar.profile.inventory',
    'hangar.profile.inventoryProjection': 'hangar.profile.inventoryProjection',
    'hangar.profile.legacyRead': 'hangar.profile.legacyRead',
    'hangar.profile.legacyProjection': 'hangar.profile.legacyProjection',
    'hangar.menuProfile.pageRead': 'hangar.menuProfile.pageRead',
    'hangar.menuProfile.bind': 'hangar.menuProfile.bind',
    'hangar.menuProfile.inventory': 'hangar.menuProfile.inventory',
    'hangar.menuProfile.inventoryProjection':
        'hangar.menuProfile.inventoryProjection',
    'hangar.menuProfile.legacyRead': 'hangar.menuProfile.legacyRead',
    'hangar.menuProfile.legacyProjection':
        'hangar.menuProfile.legacyProjection',
    'friends.read': 'friends.read',
    'communities.read': 'communities.read',
    'partyRooms.getDirectory': 'rooms.read',
    'communities.workspace': 'communities.workspace',
    'communities.ships': 'communities.ships',
    'communities.chat': 'communities.chat',
    'communities.media': 'communities.media',
    'directMessages.read': 'messages.read',
    'overlay.getState': 'overlay.state',
    'overlay.getWorkspace': 'overlay.workspace',
    'achievements.read': 'achievements.read',
    'execHangar.read': 'execHangar.read',
    'execHangar.refresh': 'execHangar.refresh',
    'notificationInbox.read': 'notifications.read',
    // Trading hall: one bridge name per request kind, plus a consumer span
    // per public read operation (the operation set is fixed by the Host).
    'marketplace.read': 'marketplace.read',
    'marketplace.preferences': 'marketplace.preferences',
    'marketplace.listings': 'marketplace.listings',
    'marketplace.trade': 'marketplace.trade',
    'tradeProfile.read': 'marketplace.tradeProfile',
    'marketplace.read.categories': 'marketplace.categories',
    'marketplace.read.categoryListings': 'marketplace.categoryListings',
    'marketplace.read.trending': 'marketplace.trending',
    'marketplace.read.latest': 'marketplace.latest',
    'marketplace.read.locations': 'marketplace.locations',
    'marketplace.read.reputation': 'marketplace.reputation',
    'marketplace.read.timezones': 'marketplace.timezones',
    'marketplace.read.bestPrices': 'marketplace.bestPrices',
    'marketplace.read.item': 'marketplace.item',
    'marketplace.read.offers': 'marketplace.offers',
    'marketplace.read.trend': 'marketplace.trend',
    'marketplace.read.search': 'marketplace.search',
  };
}

enum LoadingMilestone { dartEntry, firstRaster, stopped }

enum LoadingContentStatus { waiting, data, empty, partial, unavailable, failed }

final class LoadingRenderedContent {
  const LoadingRenderedContent(this.status, this.us, this.items);
  final LoadingContentStatus status;
  final int us, items;
}

enum LoadingTourPhase { begin, navigate, settled, timeout, blocked, complete }

enum LoadingAuxiliarySurface {
  friends,
  messages,
  notifications,
  menu;

  String get route => '/$name';
}

enum LoadingAuxiliaryPhase { request, snapshot, shown }

enum LoadingMenuPhase {
  request,
  preferencesFinished,
  recoveryFinished,
  hostReportFinished,
  nativeRequest,
  nativeReply,
  visible,
  hidden,
  unavailable,
  settled,
}

/// Fixed native reasons for a hidden menu. Unknown values are dropped.
enum LoadingMenuHideReason {
  request,
  close,
  dismiss,
  shortcut,
  tool,
  detach,
  reconfigure,
  deactivated,
  externalSwitch,
  switchedBeforeReveal,
  handoffRefused,
  inputTimeout,
  frameTimeout,
  targetInvalid,
  localModalLost,
  closeMessage,
  display,
  composition,
  timerFailed,
}

enum LoadingVisualPart { hangarThumbnail, communityImage }

enum LoadingImageSurface { communityLogo, communityWorkspaceImage }

enum LoadingImageRegression { redecode, cleared }

enum LoadingImageBodyEncoding { encoded, decoded, unknown }
