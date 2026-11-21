import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/localization/app_strings.dart';
import '../../app/routing/exit_application_intent.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/interaction/starbridge_snack_bar.dart';
import '../../platform/bridge/bridge_client_session.dart';
import 'application_update_announcement.dart';
import 'application_update_hero.dart';
import 'application_update_panel.dart';
import 'application_update_poster.dart';
import 'application_update_status.dart';
import 'application_update_strings.dart';
import '../../design_system/interaction/starbridge_timed_snack_bar.dart';

final _announcedVersions = Expando<Set<String>>();
// Host: at most 3 origins x 8s; leave 11s for Bridge chunks and validation.
const _heroReadTimeout = Duration(seconds: 35);
Set<String> applicationUpdateShownVersions(BridgeClientSession session) =>
    _announcedVersions[session] ??= <String>{};

typedef ApplicationUpdateRead = Future<Map<String, dynamic>> Function();
typedef ApplicationUpdatePrepare = Future<Map<String, dynamic>> Function(
  String version,
);
Future<void> showApplicationUpdateDialog(
  BuildContext context,
  BridgeClientSession? session, {
  ApplicationUpdateStatus? initialStatus,
  bool startupAnnouncement = false,
  bool Function()? isCurrent,
  void Function(VoidCallback dismiss)? onDismissReady,
  InteractionSource? source,
}) async {
  BridgeRequestOperation? checking;
  BridgeRequestOperation? preparing;
  BridgeRequestOperation? readingHero;
  // Explicit rechecks become manual; the initial startup offer remains automatic.
  var automaticHero = startupAnnouncement;
  final progress = StreamController<Map<String, dynamic>>.broadcast();
  final generation = session?.activeGeneration;
  final events = session?.events.listen((event) {
    if (!progress.isClosed &&
        event.name == 'applicationUpdates.progress' &&
        event.accountContext == null &&
        event.sessionGeneration == generation &&
        session.activeGeneration == generation &&
        preparing != null &&
        event.payload['requestId'] == preparing!.correlationId) {
      progress.add(Map<String, dynamic>.from(event.payload));
    }
  });
  final installable =
      session != null &&
      session.hostCapabilities.contains('applicationUpdates.prepare') &&
      session.hostCapabilities.contains('applicationUpdates.handoff') &&
      Actions.maybeFind<ExitApplicationIntent>(context) != null;
  String? ticket;
  InteractionSource? confirmedSource;
  try {
    ticket = await showStarBridgeDialog<String>(
      context,
      source: source,
      barrierDismissible: false,
      onRouteCreated: (route) => onDismissReady?.call(() {
        if (route.isActive) route.navigator?.removeRoute(route);
      }),
      builder: (_) {
        return ApplicationUpdateDialog(
          initialStatus: initialStatus,
          startupAnnouncement: startupAnnouncement,
          onInstallSource: (source) => confirmedSource = source,
          onAvailable: (version) {
            if (session != null) {
              applicationUpdateShownVersions(session).add(version);
            }
          },
          progress: progress.stream,
          read:
              session == null ||
                  !session.hostCapabilities.contains('applicationUpdates.check')
              ? null
              : () async {
                  if (session.activeGeneration != generation ||
                      isCurrent?.call() == false) {
                    throw const FormatException('Update session changed');
                  }
                  checking = session.beginRequest(
                    'applicationUpdates.check',
                    payload: const {'schemaVersion': 1},
                    timeout: const Duration(seconds: 35),
                  );
                  automaticHero = false;
                  return (await checking!.future).payload;
                },
          readHero:
              session == null ||
                  !session.hostCapabilities.contains(
                    'applicationUpdates.heroRead',
                  )
              ? null
              : (version, offset) async {
                  if (session.activeGeneration != generation ||
                      isCurrent?.call() == false) {
                    throw const FormatException('Update session changed');
                  }
                  readingHero = session.beginRequest(
                    'applicationUpdates.heroRead',
                    payload: {
                      'schemaVersion': 1,
                      'version': version,
                      'offset': offset,
                      'automatic': automaticHero,
                    },
                    timeout: _heroReadTimeout,
                  );
                  return (await readingHero!.future).payload;
                },
          cancelHero: () {
            final operation = readingHero;
            readingHero = null;
            if (operation != null) unawaited(operation.cancel());
          },
          cancelCheck: () {
            final operation = checking;
            if (operation != null) unawaited(operation.cancel());
          },
          prepare: !installable
              ? null
              : (version) async {
                  if (session.activeGeneration != generation ||
                      isCurrent?.call() == false) {
                    throw const FormatException('Update session changed');
                  }
                  preparing = session.beginRequest(
                    'applicationUpdates.prepare',
                    payload: {'schemaVersion': 1, 'version': version},
                    timeout: const Duration(minutes: 11),
                  );
                  final operation = preparing!;
                  try {
                    return (await operation.future).payload;
                  } finally {
                    if (identical(preparing, operation)) preparing = null;
                  }
                },
          cancelPreparation: () {
            final operation = preparing;
            preparing = null;
            if (operation != null) unawaited(operation.cancel());
          },
        );
      },
    );
  } finally {
    // Teardown is not part of installation authorization. Stop delivery now;
    // do not hold the exit intent behind a subscription's asynchronous cleanup.
    unawaited(events?.cancel());
    unawaited(progress.close());
  }
  if (ticket == null ||
      !context.mounted ||
      session == null ||
      isCurrent?.call() == false) {
    return;
  }
  // Close the confirmation before invoking the existing draft/leave guards.
  Actions.maybeInvoke(
    context,
    ExitApplicationIntent(
      source: confirmedSource,
      beforeExit: () async {
        try {
          if (session.activeGeneration != generation ||
              isCurrent?.call() == false) {
            return false;
          }
          final reply = (await session.request(
            'applicationUpdates.handoff',
            payload: {'schemaVersion': 1, 'ticket': ticket},
            timeout: const Duration(seconds: 150),
          )).payload;
          if (reply.length != 2 ||
              reply['schemaVersion'] != 1 ||
              reply['accepted'] != true) {
            throw const FormatException('Unconfirmed update handoff');
          }
          return true;
        } on Object {
          if (context.mounted && ScaffoldMessenger.maybeOf(context) != null) {
            final locale = AppStrings.of(context).locale;
            showStarBridgeSnackBar(
              context,
              starBridgeTimedSnackBar(
                content: Text(
                  locale.languageCode == 'en'
                      ? 'Update could not start. The client remains open.'
                      : locale.countryCode == 'TW' ||
                            locale.scriptCode == 'Hant'
                      ? '更新未能啟動，用戶端保持開啟。'
                      : '更新未能启动，客户端保持打开。',
                ),
              ),
              source: confirmedSource ?? source,
            );
          }
          return false;
        }
      },
    ),
  );
}

class ApplicationUpdateDialog extends StatefulWidget {
  const ApplicationUpdateDialog({
    this.read,
    this.prepare,
    this.cancelPreparation,
    this.cancelCheck,
    this.readHero,
    this.cancelHero,
    this.progress,
    this.initialStatus,
    this.startupAnnouncement = false,
    this.onAvailable,
    this.onInstallSource,
    super.key,
  });
  final ApplicationUpdateRead? read;
  final ApplicationUpdatePrepare? prepare;
  final VoidCallback? cancelPreparation;
  final VoidCallback? cancelCheck;
  final ApplicationUpdateHeroRead? readHero;
  final VoidCallback? cancelHero;
  final ApplicationUpdateStatus? initialStatus;
  final bool startupAnnouncement;
  final ValueChanged<String>? onAvailable;

  /// Presentation origin only; does not authorize installation or own exit.
  final ValueChanged<InteractionSource>? onInstallSource;

  /// Broadcast updates for the currently active prepare request only.
  final Stream<Map<String, dynamic>>? progress;
  @override
  State<ApplicationUpdateDialog> createState() =>
      _ApplicationUpdateDialogState();
}

class _ApplicationUpdateDialogState extends State<ApplicationUpdateDialog> {
  String _state = 'checking';
  String? _current, _available, _notes;
  String? _ticket;
  UpdateAnnouncement? _announcement;
  bool _showFullNotes = false;
  Uint8List? _hero;
  String? _heroVersion;
  Timer? _retry;
  int _attempt = 0;
  StreamSubscription<Map<String, dynamic>>? _progressSubscription;
  int _preparation = 0;
  int _received = 0;
  int? _total;
  String _phase = 'downloading';
  InteractionSource _source = InteractionSource.programmatic;
  @override
  void initState() {
    super.initState();
    if (widget.initialStatus case final status?) {
      _applyStatus(status);
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _retry?.cancel();
    _preparation++;
    unawaited(_progressSubscription?.cancel());
    widget.cancelCheck?.call();
    widget.cancelHero?.call();
    widget.cancelPreparation?.call();
    super.dispose();
  }

  Future<void> _prepare(InteractionSource source) async {
    if (_state == 'downloading' ||
        _available == null ||
        widget.prepare == null) {
      return;
    }
    setState(() {
      _source = source;
      _state = 'downloading';
      _ticket = null;
      _received = 0;
      _total = null;
      _phase = 'downloading';
    });
    final attempt = ++_preparation;
    try {
      _progressSubscription = widget.progress?.listen(
        (value) => _receiveProgress(value, attempt),
        onError: (Object _) {},
      );
      final reply = await widget.prepare!(_available!);
      if (reply.length != 3 ||
          reply['schemaVersion'] != 1 ||
          reply['version'] != _available ||
          reply['ticket'] is! String ||
          !RegExp(r'^[0-9a-f]{32}$').hasMatch(reply['ticket'] as String)) {
        throw const FormatException('Invalid prepared update');
      }
      if (!mounted || attempt != _preparation) return;
      setState(() {
        _ticket = reply['ticket'] as String;
        _state = 'ready';
      });
    } on BridgeClientException catch (error) {
      if (mounted && attempt == _preparation) {
        setState(
          () => _state =
              error.code == 'applicationUpdates.installationVersionMismatch'
              ? 'installation-version-mismatch'
              : 'prepare-failed',
        );
      }
    } on Object {
      if (mounted && attempt == _preparation) {
        setState(() => _state = 'prepare-failed');
      }
    } finally {
      if (attempt == _preparation) {
        await _progressSubscription?.cancel();
        _progressSubscription = null;
      }
    }
  }

  void _receiveProgress(Map<String, dynamic> value, int attempt) {
    const phases = ['downloading', 'verifying', 'verified'];
    final received = value['receivedBytes'];
    final total = value['totalBytes'];
    final phase = value['phase'];
    if (!mounted ||
        attempt != _preparation ||
        _state != 'downloading' ||
        value.length != 6 ||
        value['schemaVersion'] != 1 ||
        value['requestId'] is! String ||
        value['version'] != _available ||
        !value.containsKey('totalBytes') ||
        !phases.contains(phase) ||
        phases.indexOf(phase as String) < phases.indexOf(_phase) ||
        received is! int ||
        received < _received ||
        received > 1073741824 ||
        (total != null &&
            (total is! int ||
                total <= 0 ||
                total > 1073741824 ||
                received > total)) ||
        (_total != null && total != _total)) {
      return;
    }
    setState(() {
      _received = received;
      _total = total as int?;
      _phase = phase;
    });
  }

  void _cancelDownload(InteractionSource source) {
    _source = source;
    _preparation++;
    unawaited(_progressSubscription?.cancel());
    _progressSubscription = null;
    widget.cancelPreparation?.call();
    setState(() => _state = 'cancelled');
  }

  Future<void> _load() async {
    if (widget.read == null) {
      setState(() => _state = 'unsupported');
      return;
    }
    try {
      final value = await widget.read!().timeout(const Duration(seconds: 35));
      final status = ApplicationUpdateStatus.parse(value);
      if (!mounted) return;
      setState(() => _applyStatus(status));
    } on FormatException {
      if (mounted) setState(() => _state = 'unsupported');
    } on BridgeClientException catch (error) {
      if (!mounted) return;
      if (!error.retryable) {
        setState(() => _state = 'check-failed');
      } else {
        _scheduleRetry();
      }
    } on Object {
      if (!mounted) return;
      _scheduleRetry();
    }
  }

  void _applyStatus(ApplicationUpdateStatus status) {
    _state = status.state;
    _current = status.payload['currentVersion'] as String?;
    _available = status.version;
    _notes = status.payload['notes'] as String?;
    _announcement = switch (_available) {
      final version? when isMajorUpdateVersion(version) =>
        UpdateAnnouncement.parse(_notes),
      _ => null,
    };
    if (_available != null) widget.onAvailable?.call(_available!);
    unawaited(_loadHero());
  }

  // 主图只是锦上添花：弹窗先用自带的图打开，读到了再换，读不到就不换，也不提示。
  Future<void> _loadHero() async {
    final version = _available, read = widget.readHero;
    if (version == null ||
        read == null ||
        _announcement == null ||
        _heroVersion == version ||
        !updateNotesHaveHero(_notes!)) {
      return;
    }
    _heroVersion = version;
    var expired = false;
    final bytes =
        await readApplicationUpdateHero(
          read,
          version,
          isCurrent: () => mounted && _available == version && !expired,
        ).timeout(
          _heroReadTimeout,
          onTimeout: () {
            expired = true;
            widget.cancelHero?.call();
            return null;
          },
        );
    if (bytes == null || !mounted || _available != version) return;
    setState(() => _hero = bytes);
  }

  void _scheduleRetry() {
    const delays = [2, 5, 15];
    if (_attempt >= delays.length) {
      setState(() => _state = 'check-failed');
      return;
    }
    setState(() => _state = 'retrying');
    _retry = Timer(Duration(seconds: delays[_attempt++]), _load);
  }

  void _checkAgain(InteractionSource source) {
    _retry?.cancel();
    setState(() {
      _source = source;
      _state = 'checking';
      _attempt = 0;
      _available = null;
      _notes = null;
      _announcement = null;
      _showFullNotes = false;
      _hero = null;
      _heroVersion = null;
      _ticket = null;
    });
    _load();
  }

  String t(String key) {
    final locale = AppStrings.of(context).locale;
    final index = locale.languageCode == 'en'
        ? 2
        : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
        ? 1
        : 0;
    return applicationUpdateStrings[key]![index];
  }

  /// 下载 › 校验 › 准备好 › 安装。只在有进度可看时显示。
  Widget? _steps(BuildContext context) {
    final current = _state == 'ready'
        ? 2
        : _state != 'downloading'
        ? null
        : _phase == 'downloading'
        ? 0
        : 1;
    if (current == null) return null;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final names = [
      t('step-download'),
      t('step-verify'),
      t('step-ready'),
      t('step-install'),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(
        TextSpan(
          children: [
            for (var i = 0; i < names.length; i++) ...[
              if (i > 0) const TextSpan(text: ' › '),
              TextSpan(
                text: names[i],
                style: i == current
                    ? TextStyle(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                      )
                    : null,
              ),
            ],
          ],
        ),
        key: const Key('update-steps'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _posterStatus(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final steps = _steps(context);
    final linkStyle = theme.textTheme.bodySmall?.copyWith(
      color: colors.primary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?steps,
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (_current != null)
              Text(
                '${t('current')} · $_current',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            if (_announcement?.fullNotes != null)
              InkWell(
                key: const Key('update-full-notes'),
                onTap: () => setState(() => _showFullNotes = !_showFullNotes),
                child: Text(
                  t(_showFullNotes ? 'collapse-notes' : 'full-notes'),
                  style: linkStyle,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        StarBridgeInteractionRegion(
          child: Builder(
            builder: (context) => SuiteContentSwitcher(
              instant:
                  resolveStarBridgeInitialReadSource(context, _source) ==
                  InteractionSource.keyboard,
              child: _statusContent(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusContent(BuildContext context) => Column(
    key: ValueKey(_state),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        t(
          _state == 'available' && widget.prepare != null
              ? 'available-installable'
              : _state == 'downloading' && _phase != 'downloading'
              ? 'verifying'
              : _state,
        ),
      ),
      if (_state == 'installation-version-mismatch') ...[
        const SizedBox(height: 8),
        const SelectableText(
          'applicationUpdates.installationVersionMismatch',
          key: Key('update-failure-code'),
        ),
      ],
      if (_state == 'downloading' && _phase == 'downloading') ...[
        const SizedBox(height: 12),
        // Unknown size has no invented percentage or endless animation.
        if (_total != null)
          StarBridgeInteractionRegion(
            child: Builder(
              builder: (context) {
                final data = InteractionScope.of(context);
                final origin = resolveStarBridgeInitialReadSource(
                  context,
                  _source,
                );
                return InteractionScope(
                  data: data.copyWith(
                    reduceMotion:
                        data.reduceMotion ||
                        origin == InteractionSource.keyboard,
                  ),
                  child: SuiteProgressBar(
                    value: _received / _total!,
                    phase: ProgressPhase.running,
                  ),
                );
              },
            ),
          ),
        Text(
          _total == null
              ? '${(_received / 1048576).toStringAsFixed(1)} MB'
              : '${(_received * 100 / _total!).floor()}% · '
                    '${(_received / 1048576).toStringAsFixed(1)} / '
                    '${(_total! / 1048576).toStringAsFixed(1)} MB',
        ),
      ],
    ],
  );

  List<Widget> _actions(BuildContext context) => [
    StarBridgeActionButton(
      kind: StarBridgeActionKind.quiet,
      controlKey: const Key('update-close'),
      onActivate: (source) =>
          dismissStarBridgeDialog<String>(context, source: source),
      child: Text(t(widget.startupAnnouncement ? 'later' : 'close')),
    ),
    if (_state == 'check-failed' ||
        _state == 'channel-unavailable' ||
        _state == 'verification-failed')
      StarBridgeActionButton(
        kind: StarBridgeActionKind.quiet,
        controlKey: const Key('update-retry'),
        onActivate: _checkAgain,
        child: Text(t('retry')),
      ),
    if ((_state == 'available' ||
            _state == 'prepare-failed' ||
            _state == 'cancelled') &&
        widget.prepare != null)
      StarBridgeActionButton(
        kind: StarBridgeActionKind.primary,
        controlKey: const Key('update-download'),
        onActivate: (source) => unawaited(_prepare(source)),
        child: Text(
          t(
            _state == 'prepare-failed'
                ? 'retry-download'
                : _state == 'cancelled'
                ? 'download-again'
                : 'download',
          ),
        ),
      ),
    if (_state == 'downloading')
      StarBridgeActionButton(
        kind: StarBridgeActionKind.quiet,
        controlKey: const Key('update-cancel'),
        onActivate: _cancelDownload,
        child: Text(t('cancel-download')),
      ),
    if (_state == 'ready' && _ticket != null)
      StarBridgeActionButton(
        kind: StarBridgeActionKind.primary,
        controlKey: const Key('update-install'),
        onActivate: (source) {
          widget.onInstallSource?.call(source);
          dismissStarBridgeDialog<String>(
            context,
            source: source,
            result: _ticket,
          );
        },
        child: Text(t('install')),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    if (_announcement case final announcement?) {
      return ApplicationUpdatePoster(
        key: const Key('application-update-dialog'),
        announcement: announcement,
        version: _available,
        testVersionLabel: t('test-version'),
        showFullNotes: _showFullNotes,
        hero: _hero,
        warning:
            _state == 'prepare-failed' ||
            _state == 'installation-version-mismatch',
        status: _posterStatus(context),
        actions: _actions(context),
      );
    }
    final split = _available == null || _notes == null
        ? null
        : splitUpdateNotesTitle(stripUpdateHeroLine(_notes!));
    return ApplicationUpdatePanel(
      key: const Key('application-update-dialog'),
      title: split?.title ?? t(_available == null ? 'title' : 'announcement'),
      currentLabel: t('current'),
      current: _current,
      version: _available,
      banner: _available != null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StarBridgeInteractionRegion(
            child: Builder(
              builder: (context) => SuiteContentSwitcher(
                instant:
                    resolveStarBridgeInitialReadSource(context, _source) ==
                    InteractionSource.keyboard,
                child: _statusContent(context),
              ),
            ),
          ),
          // Keep the notes mounted across state/progress changes, preserving selection.
          if (_available != null && _notes?.isNotEmpty == true)
            UpdateReleaseNotes(split?.notes ?? _notes!),
        ],
      ),
      actions: _actions(context),
    );
  }
}
