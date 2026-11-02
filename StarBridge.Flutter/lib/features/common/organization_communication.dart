import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../communities/community_announcements_controller.dart';
import '../communities/community_announcements_management.dart';
import '../communities/community_announcements_dialog.dart';
import '../../shared/diagnostics/loading_read_scope.dart';
import '../communities/community_avatar_cache.dart';
import '../communities/community_chat_controller.dart';
import '../communities/community_author_projection_port.dart';
import '../communities/community_chat_attention.dart';
import '../communities/community_activity_port.dart';
import '../communities/community_chat_panel.dart';
import '../communities/communities_module.dart' show CommunityFailure;
import 'organization_chat_preview_authors.dart';
import 'organization_communication_port.dart';
import 'organization_governance_port.dart';
import 'organization_announcement_management_port.dart';
import 'organization_announcement_management_session.dart';
import 'organization_announcement_outcomes_controller.dart';

/// Retains the existing collaboration controllers across navigation and manual
/// identity refresh. Discard the whole scope when its authorized viewer changes.
final class OrganizationCommunication extends ChangeNotifier {
  OrganizationCommunication(this.factory);
  final OrganizationCommunicationFactory? factory;
  Object? _governanceOwner;
  OrganizationGovernancePort? _governance;
  OrganizationGovernancePort get governance =>
      _governance ?? const UnavailableOrganizationGovernance();
  void configureGovernance({
    required Object owner,
    required OrganizationGovernancePort Function() create,
  }) {
    if (_closed) return;
    if (_governanceOwner != null) {
      if (!identical(owner, _governanceOwner)) {
        throw StateError('Governance transport owner changed');
      }
      return;
    }
    _governanceOwner = owner;
    _governance = create();
  }

  Object? _managementOwner;
  OrganizationAnnouncementManagementPort? _managementPort;
  OrganizationAnnouncementManagementSession? _managementSession;
  OrganizationAnnouncementOutcomesController? announcementOutcomes;
  bool get announcementOutcomesAvailable =>
      !_closed && _managementPort?.outcomesAvailable == true;

  void configureAnnouncementManagement({
    required Object owner,
    required OrganizationAnnouncementManagementPort Function() create,
  }) {
    if (_closed) {
      return;
    }
    if (_managementOwner != null) {
      if (!identical(owner, _managementOwner)) {
        throw StateError('Announcement management owner changed');
      }
      return;
    }
    _managementOwner = owner;
    _managementPort = create();
    announcementOutcomes = OrganizationAnnouncementOutcomesController(
      _managementPort!,
    )..addListener(_notifySoon);
  }

  OrganizationCommunicationPort? _port;
  OrganizationCommunicationContext? _context;
  String? _source;
  int _epoch = 0;
  bool _closed = false;
  bool _readOnly = false;
  int _accessRevision = 0;
  bool get readOnly => _readOnly;

  /// Whether the announcement controller would show its own publish actions;
  /// a shortcut to them must never appear where the controller hides them.
  bool get announcementManagementVisible =>
      !_closed && !_readOnly && _announcements?.showManagementActions == true;

  /// For a settings section, which stays through the reads the actions wait for.
  bool get announcementManagementGranted =>
      !_closed && !_readOnly && _announcements?.managementGranted == true;

  /// The newest messages for the upper screen's channel tile, from the same
  /// reads as the unread count. Names come only from a current author proof.
  List<CommunityChatMessage> get chatRecent {
    final target = _context?.targetRef;
    if (_readOnly ||
        !chatAvailable ||
        target == null ||
        _attention?.readError(target) != null) {
      return const [];
    }
    final authors = _previewAuthors;
    return [
      for (final message in _attention?.recent(target) ?? const [])
        authors?.present(message) ??
            CommunityChatMessage.neutralAuthor(message),
    ];
  }

  OrganizationChatPreviewAuthors? _previewAuthors;
  final _previewOwners = <Object>{};
  @visibleForTesting
  bool get chatPreviewOnScreen => _previewOwners.isNotEmpty;

  /// Author proofs are renewed only while a tile reports itself on screen.
  /// How many messages the tile shows now; only those are observed.
  set chatPreviewCount(int value) => _previewAuthors?.shownCount = value;

  void setChatPreviewVisible(Object owner, {required bool visible}) {
    if (_closed) return;
    if (visible) {
      _previewOwners.add(owner);
    } else {
      _previewOwners.remove(owner);
    }
    _syncPreviewAuthors();
  }

  void _syncPreviewAuthors() {
    _previewAuthors?.setActive(
      _previewOwners.isNotEmpty &&
          !_readOnly &&
          _context != null &&
          chatAvailable,
    );
  }

  bool _managementVisibleSeen = false;
  bool _managementGrantedSeen = false;

  /// Only the shortcut's own state rebuilds the page; a background announcement
  /// read that changed nothing must not (loading line 2026-10-29).
  void _announcementsChanged() {
    final visible = announcementManagementVisible;
    final granted = announcementManagementGranted;
    if (visible == _managementVisibleSeen &&
        granted == _managementGrantedSeen) {
      return;
    }
    _managementVisibleSeen = visible;
    _managementGrantedSeen = granted;
    _notifySoon();
  }

  /// A verified workspace address only. Each independent feature still checks
  /// its own Host/backend capability; chat availability grants no ship access.
  String? get verifiedWorkspaceTargetRef =>
      _closed || _readOnly ? null : _context?.targetRef;

  DateTime? _lastVerifiedAtUtc;
  DateTime? get lastVerifiedAtUtc => _lastVerifiedAtUtc;
  void retainReadOnly() {
    if (_closed) return;
    ++_accessRevision;
    _announcements?.setManagementReadOnly(true);
    if (_readOnly) return;
    _readOnly = true;
    _chat?.setReadOnly(true);
    _attention?.bind(const []);
    _previewAuthors?.setActive(false);
    _notifySoon();
  }

  Future<void>? _opening;
  bool get isRefreshing => _opening != null;
  CommunityChatController? _chat;
  CommunityAnnouncementsController? _announcements;
  CommunityAvatarCache? _avatars;
  CommunityChatAttention? _attention;
  StreamSubscription<void>? _scopeInvalidations, _connection;
  StreamSubscription<void>? _workspaceActivity;
  StreamSubscription<String>? _activityErrors;
  bool get backgroundAttentionManaged => _workspaceActivity != null;
  final _attentionCount = ValueNotifier<int>(0);
  ValueListenable<int> get attentionCount => _attentionCount;
  bool _notifyQueued = false;
  bool get needsScopeRefresh => factory != null && _source == null;
  Stream<void>? get workspaceChanges => _port is CommunityActivityPort
      ? (_port as CommunityActivityPort).workspaceChanges
      : null;
  int get chatUnreadCount =>
      !_readOnly &&
          chatAvailable &&
          _context != null &&
          _attention?.readError(_context!.targetRef) == null
      ? _attention?.count(_context!.targetRef) ?? 0
      : 0;

  void _notifySoon() {
    if (_closed || _notifyQueued) return;
    _notifyQueued = true;
    scheduleMicrotask(() {
      _notifyQueued = false;
      if (!_closed) {
        _attentionCount.value = chatUnreadCount;
        notifyListeners();
      }
    });
  }

  void _chatChanged() {
    final chat = _chat;
    if (chat == null) return;
    final error = chat.error;
    if (error != null) {
      // A metadata-only repaint cannot re-submit a retained transient failure.
      if (_readOnly &&
          !const {
            'identityUnavailable',
            'notAllowed',
            'notFound',
          }.contains(error)) {
        return;
      }
      final epoch = _epoch;
      scheduleMicrotask(() {
        if (_closed || epoch != _epoch || !identical(chat, _chat)) return;
        _readFailed(error);
      });
    } else if (!_readOnly) {
      _attention?.observe(chat);
    }
  }

  void _readFailed(String error) {
    if (const {
      'identityUnavailable',
      'notAllowed',
      'notFound',
    }.contains(error)) {
      reset();
    } else {
      retainReadOnly();
    }
    _notifySoon();
  }

  void _attentionChanged() {
    final attention = _attention;
    final epoch = _epoch;
    final target = _context?.targetRef;
    // The callback may be inside attention.notifyListeners. Retire/dispose it
    // after that notification completes, still fenced to this exact scope.
    scheduleMicrotask(() {
      if (_closed || epoch != _epoch || !identical(attention, _attention)) {
        return;
      }
      final error = target == null ? null : attention?.readError(target);
      if (error != null) {
        _readFailed(error);
      }
      _notifySoon();
    });
  }

  void _connectionChanged() {
    final port = _port;
    if (_closed || port is! OrganizationCommunicationConnectionPort) return;
    final connection = port as OrganizationCommunicationConnectionPort;
    if (!connection.onlineTrafficAllowed) {
      retainReadOnly();
    } else if (_source != null) {
      unawaited(refresh(_source!));
    }
  }

  Future<void> recheckAnnouncementManagement({required bool allowed}) async =>
      _announcements?.recheckManagement(allowed: allowed);

  /// A visible owner calls this on existing invalidations or bounded fallback.
  /// Reads neither advance receipts nor replay a pending send.
  Future<void> refreshReadback() async {
    if (_closed || _source == null) return;
    final port = _port;
    final connection = port is OrganizationCommunicationConnectionPort
        ? port as OrganizationCommunicationConnectionPort
        : null;
    if (connection != null && !connection.onlineTrafficAllowed) {
      return;
    }
    if (_readOnly) {
      await refresh(_source!);
    } else {
      _attention?.refresh();
    }
  }

  bool get chatAvailable => _context != null && _port?.chatAvailable == true;
  bool get announcementsAvailable =>
      _context != null && _port?.announcementsAvailable == true;

  Future<void> open(String source) => _open(source, revalidate: false);

  Future<void> refresh(String source) => _open(source, revalidate: true);

  Future<void> _open(String source, {required bool revalidate}) {
    if (_closed || factory == null) return Future.value();
    if (_source == source && _opening != null) return _opening!;
    final retained = _source == source && _context != null;
    if (retained && !_readOnly && !revalidate) return Future.value();
    if (retained) retainReadOnly();
    if (!retained) reset();
    _source = source;
    final epoch = _epoch;
    final accessRevision = _accessRevision;
    final port = _port = retained ? _port! : factory!(source);
    if (!retained) {
      _scopeInvalidations = port.invalidations.listen((_) {
        if (_closed || !identical(_port, port)) return;
        reset();
        _notifySoon();
      });
      if (port is OrganizationCommunicationConnectionPort) {
        final connection = port as OrganizationCommunicationConnectionPort;
        _connection = connection.connectionChanges.listen(
          (_) => _connectionChanged(),
        );
      }
      _attention = CommunityChatAttention.forChat(port, observeActivity: false)
        ..addListener(_attentionChanged);
      if (port is CommunityActivityPort) {
        _workspaceActivity = (port as CommunityActivityPort).workspaceChanges
            .listen((_) {
              if (!_closed && epoch == _epoch && identical(port, _port)) {
                unawaited(refreshReadback());
              }
            });
      }
      if (port is CommunityActivityFailurePort) {
        _activityErrors = (port as CommunityActivityFailurePort)
            .activityReadErrors
            .listen((error) {
              if (!_closed && epoch == _epoch && identical(port, _port)) {
                _readFailed(error);
              }
            });
      }
    }
    return _opening = () async {
      try {
        final context = await port.open();
        if (_closed || epoch != _epoch || accessRevision != _accessRevision) {
          return;
        }
        if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(context.targetRef)) {
          throw const FormatException();
        }
        final oldTarget = _context?.targetRef;
        _context = context;
        _avatars ??= CommunityAvatarCache();
        if (!port.chatAvailable) {
          _chat?.removeListener(_chatChanged);
          _chat?.dispose();
          _chat = null;
        } else if (_chat == null || _chat!.invalidated) {
          _chat?.removeListener(_chatChanged);
          _chat?.dispose();
          _chat = CommunityChatController(
            port,
            context.targetRef,
            localEcho: true,
          )..addListener(_chatChanged);
        } else {
          _chat!.renewVerifiedReference(context.targetRef);
        }
        if (!port.announcementsAvailable) {
          _announcements?.dispose();
          _announcements = null;
          _managementSession?.dispose();
          _managementSession = null;
        } else if (_announcements == null || oldTarget != context.targetRef) {
          _announcements?.dispose();
          _managementSession?.dispose();
          final management = _managementPort;
          final outcomes = announcementOutcomes;
          _managementSession = management == null || outcomes == null
              ? null
              : OrganizationAnnouncementManagementSession(
                  management,
                  source,
                  outcomes: outcomes,
                );
          _announcements = CommunityAnnouncementsController(
            port,
            context.targetRef,
            management: _managementSession,
          )
            ..setManagementReadOnly(_readOnly)
            ..addListener(_announcementsChanged);
        }
        // A cached history error remains on the existing controller until an
        // actual successful history read replaces it. Keep admission paused
        // through that read rather than replaying the old error from the
        // setReadOnly(false) notification, or masking a fresh permission denial.
        if (_chat?.error != null) {
          final recovering = _chat!;
          await recovering.refresh(silent: true);
          if (_closed ||
              epoch != _epoch ||
              accessRevision != _accessRevision ||
              !identical(recovering, _chat)) {
            return;
          }
          if (recovering.error != null || recovering.invalidated) {
            retainReadOnly();
            return;
          }
        }
        _readOnly = false;
        _announcements?.setManagementReadOnly(false);
        _lastVerifiedAtUtc = DateTime.now().toUtc();
        _chat?.setReadOnly(false);
        _attention?.bind(port.chatAvailable ? [context.targetRef] : const []);
        if (port is OrganizationChatPreviewAuthorPort) {
          (_previewAuthors ??=
                  OrganizationChatPreviewAuthors(
                    port as OrganizationChatPreviewAuthorPort,
                    onAccessLost: _readFailed,
                  )..addListener(_notifySoon))
              .target = context
              .targetRef;
          _syncPreviewAuthors();
        }
        // The upper screen's announce shortcut needs the editor before any
        // announcement dialog opens. Authority stays with the Host's answer.
        final announcements = _announcements;
        if (announcements != null) {
          unawaited(
            backgroundLoadingRead(announcements.prepareManagementIfNeeded),
          );
        }
      } on Object catch (error) {
        if (!_closed &&
            epoch == _epoch &&
            error is CommunityFailure &&
            const {
              'identityUnavailable',
              'notAllowed',
              'notFound',
            }.contains(error.code)) {
          reset();
          _notifySoon();
          return;
        }
        if (!_closed && epoch == _epoch) retainReadOnly();
      } finally {
        if (epoch == _epoch) {
          _opening = null;
          if (!_closed) notifyListeners();
        }
      }
    }();
  }

  Widget announcement({bool expanded = false}) => CommunityAnnouncementEntry(
    key: ValueKey((_port, 'announcement', expanded)),
    port: _port!,
    targetRef: _context!.targetRef,
    controller: _announcements,
    expanded: expanded,
  );

  Widget chat({required VoidCallback onBack}) => CommunityChatPanel(
    key: ValueKey((_port, 'chat')),
    port: _port!,
    targetRef: _context!.targetRef,
    name: _context!.name,
    controller: _chat,
    avatars: _avatars,
    onBack: onBack,
  );

  void reset() {
    ++_epoch;
    ++_accessRevision;
    _context = null;
    _lastVerifiedAtUtc = null;
    _readOnly = false;
    _source = null;
    _opening = null;
    unawaited(_scopeInvalidations?.cancel());
    unawaited(_connection?.cancel());
    unawaited(_workspaceActivity?.cancel());
    unawaited(_activityErrors?.cancel());
    _workspaceActivity = null;
    _activityErrors = null;
    _attentionCount.value = 0;
    _scopeInvalidations = _connection = null;
    _attention?.removeListener(_attentionChanged);
    _attention?.dispose();
    _attention = null;
    _previewAuthors?.removeListener(_notifySoon);
    _previewAuthors?.dispose();
    _previewAuthors = null;
    _managementVisibleSeen = false;
    _chat?.removeListener(_chatChanged);
    _chat?.dispose();
    _announcements?.dispose();
    _managementSession?.dispose();
    _managementSession = null;
    _avatars?.dispose();
    _chat = null;
    _announcements = null;
    _avatars = null;
    final previous = _port;
    _port = null;
    if (previous != null) unawaited(previous.close());
  }

  @override
  void dispose() {
    _closed = true;
    reset();
    announcementOutcomes?.removeListener(_notifySoon);
    announcementOutcomes?.dispose();
    final management = _managementPort;
    if (management != null) unawaited(management.close());
    unawaited(_governance?.close());
    _attentionCount.dispose();
    super.dispose();
  }
}
