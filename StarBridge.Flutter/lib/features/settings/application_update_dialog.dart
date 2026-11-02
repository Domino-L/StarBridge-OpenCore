import 'dart:async';

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
import 'application_update_panel.dart';
import 'application_update_status.dart';
import '../../design_system/interaction/starbridge_timed_snack_bar.dart';

final _announcedVersions = Expando<Set<String>>();
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
                  return (await checking!.future).payload;
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
    if (_available != null) widget.onAvailable?.call(_available!);
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
    return const <String, List<String>>{
      'title': ['检查更新', '檢查更新', 'Check for updates'],
      'announcement': ['发现新版本', '發現新版本', 'A new version is available'],
      'later': ['稍后', '稍後', 'Later'],
      'checking': ['正在检查更新…', '正在檢查更新…', 'Checking for updates…'],
      'channel-unconfigured': [
        '此版本尚未提供在线更新。你可以继续使用当前客户端。',
        '此版本尚未提供線上更新。你可以繼續使用目前的用戶端。',
        'Online updates are not available for this build. You can keep using the current client.',
      ],
      'up-to-date': ['当前已是最新版本。', '目前已是最新版本。', 'You are up to date.'],
      'configuration-invalid': [
        '此版本的更新服务暂不可用。你可以继续使用当前客户端。',
        '此版本的更新服務暫不可用。你可以繼續使用目前的用戶端。',
        'The update service is unavailable for this build. You can keep using the current client.',
      ],
      'channel-unavailable': [
        '暂时无法获取更新信息，请稍后重试。',
        '暫時無法取得更新資訊，請稍後重試。',
        'Update information is unavailable. Try again later.',
      ],
      'verification-failed': [
        '更新信息未通过安全验证，已停止更新。当前版本保持不变。',
        '更新資訊未通過安全驗證，已停止更新。目前版本保持不變。',
        'Update information failed security verification. The update was stopped; your current version is unchanged.',
      ],
      'check-failed': [
        '暂时无法检查更新。请检查网络后重试，或继续使用当前客户端。',
        '暫時無法檢查更新。請檢查網路後重試，或繼續使用目前的用戶端。',
        'Unable to check for updates. Check your connection and try again, or keep using the current client.',
      ],
      'retry': ['重新检查', '重新檢查', 'Check again'],
      'available': [
        '此安装暂时无法在应用内更新。请从官网下载最新版安装器，保留现有资料完成升级。',
        '此安裝暫時無法在應用程式內更新。請從官網下載最新版安裝程式，保留現有資料完成升級。',
        'In-app installation is unavailable for this installation. Use the latest installer from the official website, keeping your existing data.',
      ],
      'available-installable': [
        '发现新版本，可以下载更新。',
        '發現新版本，可以下載更新。',
        'An update is available to download.',
      ],
      'download': ['下载更新', '下載更新', 'Download update'],
      'downloading': [
        '正在下载更新。你可以随时取消，当前版本不会改变。',
        '正在下載更新。你可以隨時取消，目前版本不會改變。',
        'Downloading the update. You can cancel at any time; your current version will not change.',
      ],
      'verifying': [
        '下载完成，正在验证更新…',
        '下載完成，正在驗證更新…',
        'Download complete. Verifying the update…',
      ],
      'cancel-download': ['取消下载', '取消下載', 'Cancel download'],
      'cancelled': [
        '下载已取消，当前版本保持不变。',
        '下載已取消，目前版本保持不變。',
        'Download cancelled. Your current version is unchanged.',
      ],
      'ready': [
        '更新已准备好。安装将关闭并重新打开客户端，请先保存未完成的更改。',
        '更新已準備好。安裝將關閉並重新開啟用戶端，請先儲存未完成的變更。',
        'The update is ready. Installation will restart the client. Save your changes first.',
      ],
      'install': ['重启并安装', '重新啟動並安裝', 'Restart and install'],
      'prepare-failed': [
        '更新未准备完成，当前版本保持不变。请重试；若仍失败，请从官网下载正式安装包，关闭客户端后安装到原目录。无需先卸载或删除个人资料。',
        '更新未準備完成，目前版本保持不變。請重試；若仍失敗，請從官網下載正式安裝程式，關閉用戶端後安裝至原目錄。無需先解除安裝或刪除個人資料。',
        'The update could not be prepared. Your current version is unchanged. Try again. If it still fails, download the official installer, close the client, and install to the same location. Do not uninstall or delete personal data first.',
      ],
      'installation-version-mismatch': [
        '安装登记与程序版本不一致，已停止更新。当前版本和个人资料未更改。请保存未完成的内容并关闭客户端，从官网下载正式安装包，安装到原目录。无需先卸载、删除个人资料或手动修改登记信息。',
        '安裝登記與程式版本不一致，已停止更新。目前版本與個人資料未變更。請儲存未完成的內容並關閉用戶端，從官網下載正式安裝程式，安裝至原目錄。無需先解除安裝、刪除個人資料或手動修改登記資訊。',
        'The installation registration does not match the program version. The update was stopped; your current version and personal data are unchanged. Save your work and close the client, then download the official installer and install to the same location. Do not uninstall, delete personal data, or manually edit the registration first.',
      ],
      'retrying': [
        '暂时无法检查更新，正在自动重试。',
        '暫時無法檢查更新，正在自動重試。',
        'Unable to check for updates. Retrying automatically.',
      ],
      'unsupported': [
        '当前客户端暂不支持检查更新。',
        '目前的用戶端暫不支援檢查更新。',
        'This client does not support update checks yet.',
      ],
      'current': ['当前版本', '目前版本', 'Current version'],
      'close': ['关闭', '關閉', 'Close'],
    }[key]![index];
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

  @override
  Widget build(BuildContext context) => ApplicationUpdatePanel(
    key: const Key('application-update-dialog'),
    title: t(_available == null ? 'title' : 'announcement'),
    currentLabel: t('current'),
    current: _current,
    version: _available,
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
          UpdateReleaseNotes(_notes!),
      ],
    ),
    actions: [
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
          child: Text(t('download')),
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
    ],
  );
}
