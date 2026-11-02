import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';

import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_appearance_progress.dart';

/// Foreground-only reads. Never sends placement, accounting or pet commands.
class OverlayAppearanceCollectionPanel extends StatefulWidget {
  const OverlayAppearanceCollectionPanel({
    required this.appearanceId,
    required this.port,
    super.key,
  });
  final String appearanceId;
  final OverlayAppearanceProgressPort port;
  @override
  State<OverlayAppearanceCollectionPanel> createState() => _CollectionState();
}

class _CollectionState extends State<OverlayAppearanceCollectionPanel>
    with WidgetsBindingObserver {
  OverlayAppearanceProgress? _value;
  StreamSubscription<void>? _owner;
  Timer? _timer;
  int _epoch = 0;
  bool _busy = false, _failed = false;
  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bind();
  }

  void _bind() {
    _owner = widget.port.appearanceOwnerChanges.listen(
      (_) {
        // This invalidates completed and in-flight receipts immediately; no
        // response from a previous account may refill the replacement panel.
        _epoch++;
        if (!mounted) return;
        setState(() {
          _value = null;
          _busy = false;
          _failed = false;
        });
        unawaited(_read());
      },
      onError: (Object _) => _lostConnection(),
      onDone: _lostConnection,
    );
    _timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(_read()),
    );
    unawaited(_read());
  }

  void _lostConnection() {
    _epoch++;
    _timer?.cancel();
    if (mounted) {
      setState(() {
        _value = null;
        _busy = false;
        _failed = true;
      });
    }
  }

  @override
  void didUpdateWidget(OverlayAppearanceCollectionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.port != widget.port ||
        oldWidget.appearanceId != widget.appearanceId) {
      _epoch++;
      _timer?.cancel();
      unawaited(_owner?.cancel());
      _value = null;
      _busy = false;
      _failed = false;
      _bind();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_read());
  }

  Future<void> _read() async {
    if (!mounted ||
        _busy ||
        !_foreground ||
        !widget.port.supportsAppearanceProgress) {
      return;
    }
    final epoch = _epoch;
    final id = widget.appearanceId;
    final port = widget.port;
    setState(() => _busy = true);
    try {
      final value = await port.readAppearanceProgress(id);
      if (!mounted || epoch != _epoch) return;
      if (value.appearanceId != id) {
        throw const FormatException('Mismatched collection.');
      }
      setState(() {
        _value = value;
        _failed = false;
      });
    } on Object {
      if (mounted && epoch == _epoch) {
        // A lost Bridge response cannot prove the account still owns a prior
        // receipt. Clear it; the Host may return its valid confirmed copy next.
        setState(() {
          _value = null;
          _failed = true;
        });
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _epoch++;
    _timer?.cancel();
    unawaited(_owner?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final locale = Localizations.localeOf(context);
    String copy(String cn, String tw, String en) => locale.languageCode != 'zh'
        ? en
        : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
        ? tw
        : cn;
    final value = _value;
    final status = _failed
        ? copy(
            '未能读取收藏，请刷新重试。',
            '未能讀取收藏，請重新整理再試。',
            'Could not read your collection. Refresh to try again.',
          )
        : value == null
        ? copy('正在读取账号收藏…', '正在讀取帳號收藏…', 'Reading your account collection…')
        : switch (value.state) {
            'ready' => copy('已同步', '已同步', 'Synced'),
            'signedOut' => copy(
              '登录后读取账号收藏',
              '登入後讀取帳號收藏',
              'Sign in to read your account collection',
            ),
            'authenticationRequired' => copy(
              '登录已失效，请重新登录',
              '登入已失效，請重新登入',
              'Session expired. Sign in again',
            ),
            'accountSyncPending' => copy(
              '等待账号同步',
              '等待帳號同步',
              'Waiting for account sync',
            ),
            'waitingAcknowledgement' => copy(
              '等待服务端确认，保留已确认进度',
              '等待伺服器確認，保留已確認進度',
              'Awaiting confirmation; confirmed progress is kept',
            ),
            'anotherSession' => copy(
              '其他客户端正在计时，显示已确认进度',
              '其他用戶端正在計時，顯示已確認進度',
              'Another client is counting usage; showing confirmed progress',
            ),
            'resyncRequired' => copy(
              '计时需要重新同步，保留已确认进度',
              '計時需要重新同步，保留已確認進度',
              'Usage needs to resync; confirmed progress is kept',
            ),
            _ => copy(
              '同步暂不可用，请稍后刷新',
              '同步暫不可用，請稍後重新整理',
              'Sync is unavailable. Refresh later',
            ),
          };
    return StarBridgeSurface(
      key: Key('appearance-collection-${widget.appearanceId}'),
      role: SurfaceRole.panel,
      padding: EdgeInsets.all(tokens.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                copy('装饰收藏', '裝飾收藏', 'Decoration collection'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              StarBridgeActionButton(
                key: const Key('appearance-collection-refresh'),
                kind: StarBridgeActionKind.quiet,
                onActivate: _busy ? null : (_) => _read(),
                child: Text(copy('刷新收藏', '重新整理收藏', 'Refresh collection')),
              ),
            ],
          ),
          Text(
            status,
            key: const Key('appearance-collection-status'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _failed || value?.state == 'unavailable'
                  ? tokens.colors.warning
                  : tokens.colors.textSecondary,
            ),
          ),
          SizedBox(height: tokens.space.sm),
          Text(
            value?.confirmedUsageMs == null
                ? copy(
                    '使用进度尚未同步',
                    '使用進度尚未同步',
                    'Usage progress has not synced yet',
                  )
                : copy('已确认使用：', '已確認使用：', 'Confirmed usage: ') +
                      _duration(
                        value!.confirmedUsageMs!,
                        locale,
                        remaining: false,
                      ),
            key: const Key('appearance-collection-usage'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (value != null)
            for (final item in value.items) ...[
              SizedBox(height: tokens.space.md),
              MergeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.label.resolve(locale),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    SizedBox(width: tokens.space.sm),
                    Flexible(
                      child: Text(
                        item.owned
                            ? item.requiredUsageMs == 0
                                  ? copy('初始拥有', '初始擁有', 'Included')
                                  : copy('已解锁', '已解鎖', 'Unlocked')
                            : item.remainingMs == null
                            ? copy('等待进度同步', '等待進度同步', 'Awaiting progress sync')
                            : copy('还需使用 ', '還需使用 ', 'Use for another ') +
                                  _duration(
                                    item.remainingMs!,
                                    locale,
                                    remaining: true,
                                  ),
                        key: Key('appearance-collection-item-${item.id}'),
                        textAlign: TextAlign.end,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: item.owned
                              ? tokens.colors.success
                              : tokens.colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          SizedBox(height: tokens.space.md),
          Text(
            copy(
              '解锁只累计实际浮层使用，预览不计时。装饰随账号恢复，解锁后不会自动放置。',
              '解鎖只累計實際浮層使用，預覽不計時。裝飾隨帳號恢復，解鎖後不會自動放置。',
              'Only actual overlay use counts, not previews. Decorations restore with your account and are not placed automatically.',
            ),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: tokens.colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

String _duration(int ms, Locale locale, {required bool remaining}) {
  final zh = locale.languageCode == 'zh';
  final traditional = locale.countryCode == 'TW' || locale.scriptCode == 'Hant';
  final minute = traditional ? '分鐘' : '分钟', hour = traditional ? '小時' : '小时';
  if (remaining && ms < 60000) return zh ? '不足1$minute' : 'less than 1 minute';
  final minutes = ms ~/ 60000 + (remaining && ms % 60000 != 0 ? 1 : 0);
  final hours = minutes ~/ 60, rest = minutes % 60;
  if (zh) {
    return hours == 0
        ? '$minutes$minute'
        : rest == 0
        ? '$hours$hour'
        : '$hours$hour$rest$minute';
  }
  return hours == 0
      ? '$minutes min'
      : rest == 0
      ? '$hours h'
      : '$hours h $rest min';
}
