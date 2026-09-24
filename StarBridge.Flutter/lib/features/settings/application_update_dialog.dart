import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../app/routing/exit_application_intent.dart';
import '../../platform/bridge/bridge_client_session.dart';

typedef ApplicationUpdateRead = Future<Map<String, dynamic>> Function();
typedef ApplicationUpdatePrepare = Future<Map<String, dynamic>> Function(
  String version,
);

Future<void> showApplicationUpdateDialog(
  BuildContext context,
  BridgeClientSession? session,
) async {
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
  try {
    ticket = await showDialog<String>(
      context: context,
      builder: (_) => ApplicationUpdateDialog(
        progress: progress.stream,
        read:
            session == null ||
                !session.hostCapabilities.contains('applicationUpdates.check')
            ? null
            : () async {
                if (session.activeGeneration != generation) {
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
                if (session.activeGeneration != generation) {
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
      ),
    );
  } finally {
    // Teardown is not part of installation authorization. Stop delivery now;
    // do not hold the exit intent behind a subscription's asynchronous cleanup.
    unawaited(events?.cancel());
    unawaited(progress.close());
  }
  if (ticket == null || !context.mounted || session == null) return;
  // Close the confirmation before invoking the existing draft/leave guards.
  Actions.maybeInvoke(
    context,
    ExitApplicationIntent(
      beforeExit: () async {
        try {
          if (session.activeGeneration != generation) return false;
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
          if (context.mounted) {
            final locale = AppStrings.of(context).locale;
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(
                content: Text(
                  locale.languageCode == 'en'
                      ? 'Update could not start. The client remains open.'
                      : locale.countryCode == 'TW' ||
                            locale.scriptCode == 'Hant'
                      ? '更新未能啟動，用戶端保持開啟。'
                      : '更新未能启动，客户端保持打开。',
                ),
              ),
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
    super.key,
  });
  final ApplicationUpdateRead? read;
  final ApplicationUpdatePrepare? prepare;
  final VoidCallback? cancelPreparation;
  final VoidCallback? cancelCheck;

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
  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _prepare() async {
    if (_state == 'downloading' ||
        _available == null ||
        widget.prepare == null) {
      return;
    }
    setState(() {
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

  void _cancelDownload() {
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
      const states = {
        'channel-unconfigured',
        'up-to-date',
        'available',
        'configuration-invalid',
        'channel-unavailable',
        'verification-failed',
      };
      if (value.length != 5 ||
          !value.keys.every(
            const {
              'schemaVersion',
              'state',
              'currentVersion',
              'availableVersion',
              'notes',
            }.contains,
          ) ||
          value['schemaVersion'] != 1 ||
          !states.contains(value['state']) ||
          ![
            'currentVersion',
            'availableVersion',
            'notes',
          ].every((key) => value[key] == null || value[key] is String) ||
          (value['currentVersion'] as String? ?? '').length > 96 ||
          (value['availableVersion'] as String? ?? '').length > 96 ||
          (value['notes'] as String? ?? '').length > 16384 ||
          (value['state'] == 'available' &&
              (value['availableVersion'] == null ||
                  !RegExp(r'^\d+\.\d+\.\d+(?:\.\d+)?$')
                      .hasMatch(value['availableVersion'] as String))) ||
          (value['state'] != 'available' &&
              (value['availableVersion'] != null || value['notes'] != null))) {
        throw const FormatException('Incompatible update status');
      }
      if (!mounted) return;
      setState(() {
        _state = value['state'] as String;
        _current = value['currentVersion'] as String?;
        _available = value['availableVersion'] as String?;
        _notes = value['notes'] as String?;
      });
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

  void _scheduleRetry() {
    const delays = [2, 5, 15];
    if (_attempt >= delays.length) {
      setState(() => _state = 'check-failed');
      return;
    }
    setState(() => _state = 'retrying');
    _retry = Timer(Duration(seconds: delays[_attempt++]), _load);
  }

  void _checkAgain() {
    _retry?.cancel();
    setState(() {
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
        '发现新版本；安装功能尚未开放。',
        '發現新版本；安裝功能尚未開放。',
        'An update is available. Installation is not available yet.',
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
        '更新未准备完成，当前版本保持不变。你可以重新下载。',
        '更新未準備完成，目前版本保持不變。你可以重新下載。',
        'The update could not be prepared. Your current version is unchanged. You can download again.',
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

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('application-update-dialog'),
    scrollable: true,
    title: Text(t('title')),
    content: SizedBox(
      width: 440,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_current != null) Text('${t('current')} · $_current'),
          Text(
            t(
              _state == 'available' && widget.prepare != null
                  ? 'available-installable'
                  : _state == 'downloading' && _phase != 'downloading'
                  ? 'verifying'
                  : _state,
            ),
          ),
          if (_state == 'downloading' && _phase == 'downloading') ...[
            const SizedBox(height: 12),
            // Unknown size has no invented percentage or endless animation.
            if (_total != null)
              LinearProgressIndicator(value: _received / _total!),
            Text(
              _total == null
                  ? '${(_received / 1048576).toStringAsFixed(1)} MB'
                  : '${(_received * 100 / _total!).floor()}% · '
                        '${(_received / 1048576).toStringAsFixed(1)} / '
                        '${(_total! / 1048576).toStringAsFixed(1)} MB',
            ),
          ],
          if (_available != null) ...[
            Text(_available!),
            if (_notes?.isNotEmpty == true) Text(_notes!),
          ],
        ],
      ),
    ),
    actions: [
      if (_state == 'check-failed' ||
          _state == 'channel-unavailable' ||
          _state == 'verification-failed')
        TextButton(onPressed: _checkAgain, child: Text(t('retry'))),
      if ((_state == 'available' ||
              _state == 'prepare-failed' ||
              _state == 'cancelled') &&
          widget.prepare != null)
        FilledButton(onPressed: _prepare, child: Text(t('download'))),
      if (_state == 'downloading')
        TextButton(
          onPressed: _cancelDownload,
          child: Text(t('cancel-download')),
        ),
      if (_state == 'ready' && _ticket != null)
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_ticket),
          child: Text(t('install')),
        ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(t('close')),
      ),
    ],
  );
}
