import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_segmented_control.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'scm_route_port.dart';

String scmRouteCopy(BuildContext context, String key) {
  final locale = Localizations.localeOf(context);
  final value = _copy[key]!;
  return locale.languageCode == 'en'
      ? value.$3
      : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? value.$2
      : value.$1;
}

const _copy = <String, (String, String, String)>{
  'panel': ('网络线路', '網路線路', 'Network route'),
  'panelHint': (
    '在中国大陆网络下自动走国内线，连不上时自动换回海外线。',
    '在中國大陸網路下自動走國內線，連不上時自動換回海外線。',
    'Uses the mainland China route automatically there, and falls back to the overseas route when it cannot connect.',
  ),
  'title': ('SCM 线路', 'SCM 線路', 'SCM route'),
  'description': (
    '连接 SCM 交易市场和主舰队时使用的线路。',
    '連接 SCM 交易市場和主艦隊時使用的線路。',
    'The route used to reach the SCM marketplace and the main fleet.',
  ),
  'auto': ('自动', '自動', 'Automatic'),
  'overseas': ('海外', '海外', 'Overseas'),
  'current': ('当前线路', '目前線路', 'Current route'),
  'domestic': ('国内线', '國內線', 'Mainland China route'),
  'overseasRoute': ('海外线', '海外線', 'Overseas route'),
  'domesticUnavailable': (
    '国内线暂时不可用，已自动换回海外线。',
    '國內線暫時無法使用，已自動換回海外線。',
    'The mainland China route is unavailable right now, so the overseas route is used.',
  ),
  'domesticLoginFailed': (
    '上次在国内线上登录没成功，这次先用海外线。',
    '上次在國內線上登入沒成功，這次先用海外線。',
    'Sign-in on the mainland China route failed last time, so the overseas route is used this time.',
  ),
  'userOverseas': (
    '你选了一直使用海外线。',
    '你選了一直使用海外線。',
    'You chose to always use the overseas route.',
  ),
  'restart': (
    '改动会在重启应用后生效。',
    '變更會在重新啟動應用程式後生效。',
    'The change takes effect after you restart the app.',
  ),
  'loading': ('正在读取当前线路…', '正在讀取目前線路…', 'Reading the current route…'),
  'failed': ('暂时读不到线路状态。', '暫時讀不到線路狀態。', 'Could not read the route status.'),
  'saveFailed': ('没能保存，请再试一次。', '沒能儲存，請再試一次。', 'Could not save. Try again.'),
  'retry': ('重试', '重試', 'Retry'),
};

/// One row: the route choice, the route this run actually uses, and why.
/// Status only — no dialog, nothing hidden (user rule: don't hide settings).
class ScmRouteSettings extends StatefulWidget {
  const ScmRouteSettings({required this.port, super.key});
  final ScmRoutePort port;

  @override
  State<ScmRouteSettings> createState() => _ScmRouteSettingsState();
}

class _ScmRouteSettingsState extends State<ScmRouteSettings> {
  ScmRouteStatus? _status;
  bool _failed = false, _saving = false, _saveFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final status = await widget.port.read();
      if (mounted) setState(() => _status = status);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _save(ScmRouteMode mode) async {
    if (_saving || _status?.mode == mode) return;
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    try {
      final status = await widget.port.save(mode);
      if (mounted) setState(() => _status = status);
    } catch (_) {
      if (mounted) setState(() => _saveFailed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final status = _status;
    final control = StarBridgeSegmentedControl<ScmRouteMode>(
      controlKey: const Key('settings-scm-route-mode'),
      segments: [
        StarBridgeSegment(
          value: ScmRouteMode.auto,
          label: scmRouteCopy(context, 'auto'),
        ),
        StarBridgeSegment(
          value: ScmRouteMode.overseas,
          label: scmRouteCopy(context, 'overseas'),
        ),
      ],
      value: status?.mode ?? ScmRouteMode.auto,
      onChanged: status == null || _saving ? null : _save,
    );
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          scmRouteCopy(context, 'title'),
          style: theme.textTheme.titleMedium,
        ),
        SizedBox(height: tokens.space.xxs),
        Text(
          scmRouteCopy(context, 'description'),
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
    return Column(
      key: const Key('settings-scm-route'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth < 680
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    copy,
                    SizedBox(height: tokens.space.sm),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: control,
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: copy),
                    SizedBox(width: tokens.space.lg),
                    control,
                  ],
                ),
        ),
        SizedBox(height: tokens.space.sm),
        if (status != null)
          _StatusLine(status: status)
        else if (_failed)
          Row(
            children: [
              Expanded(
                child: Text(
                  scmRouteCopy(context, 'failed'),
                  key: const Key('settings-scm-route-failed'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.colors.warning,
                  ),
                ),
              ),
              StarBridgeActionButton(
                controlKey: const Key('settings-scm-route-retry'),
                onActivate: (_) => _load(),
                child: Text(scmRouteCopy(context, 'retry')),
              ),
            ],
          )
        else
          Text(
            scmRouteCopy(context, 'loading'),
            style: theme.textTheme.bodySmall,
          ),
        if (status?.restartRequired ?? false) ...[
          SizedBox(height: tokens.space.xxs),
          Text(
            scmRouteCopy(context, 'restart'),
            key: const Key('settings-scm-route-restart'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: tokens.colors.warning,
            ),
          ),
        ],
        if (_saveFailed) ...[
          SizedBox(height: tokens.space.xxs),
          Text(
            scmRouteCopy(context, 'saveFailed'),
            key: const Key('settings-scm-route-save-failed'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: tokens.colors.danger,
            ),
          ),
        ],
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.status});
  final ScmRouteStatus status;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final fellBack =
        status.reason is ScmRouteReason &&
        status.reason != ScmRouteReason.userOverseas;
    final active = scmRouteCopy(
      context,
      status.active == ScmRouteActive.domestic ? 'domestic' : 'overseasRoute',
    );
    return Wrap(
      key: const Key('settings-scm-route-status'),
      spacing: tokens.space.sm,
      runSpacing: tokens.space.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          scmRouteCopy(context, 'current'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: tokens.colors.textSecondary,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: fellBack ? tokens.colors.warning : tokens.colors.success,
              ),
            ),
            SizedBox(width: tokens.space.xs),
            Text(
              active,
              key: const Key('settings-scm-route-active'),
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
        if (status.reason case final ScmRouteReason reason)
          Text(
            scmRouteCopy(context, reason.name),
            key: const Key('settings-scm-route-reason'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: tokens.colors.textSecondary,
            ),
          ),
      ],
    );
  }
}
