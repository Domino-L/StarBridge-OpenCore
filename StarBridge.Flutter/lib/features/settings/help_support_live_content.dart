import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/tokens/color_tokens.dart';
import 'help_support_port.dart';

String helpLiveText(BuildContext context, String key) {
  final locale = AppStrings.of(context).locale;
  final index = locale.languageCode == 'en'
      ? 2
      : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? 1
      : 0;
  return const <String, List<String>>{
    'history': ['版本记录', '版本記錄', 'Release history'],
    'historyInfo': [
      '查看各版本新增的功能、体验改进与问题修复。',
      '查看各版本新增的功能、體驗改善與問題修復。',
      'Explore new features, improvements and fixes in each release.',
    ],
    'stats': ['星桥使用概况', '星橋使用概況', 'StarBridge usage'],
    'statsInfo': [
      '服务端汇总数据，不包含个人记录；查看此页不会上报使用时长。',
      '伺服器彙總資料，不包含個人記錄；查看此頁不會上報使用時長。',
      'Service totals, not personal records. Viewing this page does not upload usage.',
    ],
    'downloadCount': ['累计安装', '累計安裝', 'Installations'],
    'onlineUserCount': ['在线用户', '線上使用者', 'Online users'],
    'registeredAccountCount': ['星桥注册账号数', '星橋註冊帳號數', 'StarBridge accounts'],
    'accountsScope': [
      '仅统计星桥注册账号，暂不包含 SCM 账号。',
      '僅統計星橋註冊帳號，暫不包含 SCM 帳號。',
      'StarBridge registrations only; SCM accounts are not included.',
    ],
    'unavailable': ['暂不可用', '暫無法使用', 'Unavailable'],
    'fleetCount': ['社区组织数量', '社群組織數量', 'Community organizations'],
    'overlayUsageSeconds': ['浮层累计时长（小时）', '浮層累計時長（小時）', 'Overlay hours'],
    'updated': ['数据更新时间', '資料更新時間', 'Data updated'],
    'loading': ['正在读取…', '正在讀取…', 'Loading…'],
    'failed': ['暂时无法读取，请重试。', '暫時無法讀取，請重試。', 'Could not load. Please retry.'],
    'retry': ['重新读取', '重新讀取', 'Reload'],
    'version': ['当前客户端版本', '目前用戶端版本', 'Current client version'],
    'channel-unconfigured': [
      '当前尚未提供此客户端的在线更新来源。请通过原安装来源获取新版本。',
      '目前尚未提供此用戶端的線上更新來源。請透過原安裝來源取得新版本。',
      'An update channel is not configured for this client. Use your original installation source.',
    ],
    'up-to-date': ['当前已是最新版本', '目前已是最新版本', 'You are up to date'],
    'available': ['发现新版本', '發現新版本', 'An update is available'],
    'contact': ['联系方式（选填）', '聯絡方式（選填）', 'Contact (optional)'],
    'message': ['反馈内容', '意見內容', 'Feedback'],
    'send': ['发送反馈', '傳送意見', 'Send feedback'],
    'sending': ['正在发送…', '正在傳送…', 'Sending…'],
    'sent': ['反馈已发送，谢谢。', '意見已傳送，謝謝。', 'Feedback sent. Thank you.'],
    'unconfirmed': [
      '未能确认发送结果，内容已保留。不会自动重发，请稍后再试或通过 QQ 群联系。',
      '未能確認傳送結果，內容已保留。不會自動重送，請稍後再試或透過 QQ 群聯絡。',
      'Delivery could not be confirmed. Your text is retained and will not be resent automatically. Try later or use the support group.',
    ],
    'feedbackInfo': [
      '反馈问题时，可以补充操作步骤与预期结果；提出建议或功能需求时，可以说明使用场景和希望达到的效果。仅发送你填写的内容，不附带账号资料或日志；请勿填写密码等敏感信息。',
      '回報問題時，可以補充操作步驟與預期結果；提出建議或功能需求時，可以說明使用情境和希望達到的效果。僅傳送你填寫的內容，不附帶帳號資料或日誌；請勿填寫密碼等敏感資訊。',
      'For a problem, you can include the steps and expected result. For a suggestion or feature request, describe when you would use it and what it would help you do. Only the text you enter is sent, without account details or logs. Do not include passwords or sensitive information.',
    ],
  }[key]![index];
}

class HelpSupportReadCard extends StatefulWidget {
  const HelpSupportReadCard({required this.name, this.port, super.key});
  final String name;
  final HelpSupportPort? port;
  @override
  State<HelpSupportReadCard> createState() => _HelpSupportReadCardState();
}

class _HelpSupportReadCardState extends State<HelpSupportReadCard> {
  Map<String, dynamic>? _value;
  bool _busy = true, _failed = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final value = await widget.port!
          .read(widget.name)
          .timeout(const Duration(seconds: 22));
      if (value['schemaVersion'] != 1) throw const FormatException();
      if (widget.name == 'helpSupport.history') {
        if (!{'starbridge', 'wpf'}.contains(value['edition']) ||
            value['entries'] is! List) {
          throw const FormatException();
        }
        for (final e in value['entries'] as List) {
          if (e is! Map ||
              ![
                'version',
                'publishedOn',
                'title',
                'summary',
              ].every((k) => e[k] is String) ||
              e['highlights'] is! List ||
              !(e['highlights'] as List).every((x) => x is String)) {
            throw const FormatException();
          }
        }
      } else if (widget.name == 'helpSupport.stats') {
        for (final key in [
          'downloadCount',
          'onlineUserCount',
          'fleetCount',
          'overlayUsageSeconds',
        ]) {
          if (value[key] is! int || (value[key] as int) < 0) {
            throw const FormatException();
          }
        }
        if (value['updatedAt'] is! String ||
            DateTime.tryParse(value['updatedAt']) == null) {
          throw const FormatException();
        }
      } else if (!{
            'channel-unconfigured',
            'available',
            'up-to-date',
          }.contains(value['state']) ||
          (value['currentVersion'] != null &&
              value['currentVersion'] is! String)) {
        throw const FormatException();
      }
      if (mounted) setState(() => _value = value);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => helpLiveText(context, key);
    final tokens = context.tokens;
    final data = _value;
    final history = widget.name == 'helpSupport.history';
    final stats = widget.name == 'helpSupport.stats';
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t(
              history
                  ? 'history'
                  : stats
                  ? 'stats'
                  : 'version',
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SizedBox(height: tokens.space.sm),
          if (history || stats) Text(t(history ? 'historyInfo' : 'statsInfo')),
          if (_busy) Text(t('loading')),
          if (_failed)
            Text(t('failed'), style: TextStyle(color: tokens.colors.warning)),
          if (data != null && history) ...[
            for (final entry in data['entries'] as List)
              Material(
                color: Colors.transparent,
                child: ExpansionTile(
                  key: PageStorageKey('release-${entry['version']}'),
                  title: Text('v${entry['version']} · ${entry['title']}'),
                  subtitle: Text(entry['publishedOn'] as String),
                  childrenPadding: EdgeInsets.all(tokens.space.md),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry['summary'] as String),
                    for (final line in entry['highlights'] as List)
                      Padding(
                        padding: EdgeInsets.only(top: tokens.space.sm),
                        child: Text('• $line'),
                      ),
                  ],
                ),
              ),
          ],
          if (data != null && stats) ...[
            Wrap(
              spacing: tokens.space.lg,
              runSpacing: tokens.space.md,
              children: [
                for (final key in [
                  'downloadCount',
                  'registeredAccountCount',
                  'onlineUserCount',
                  'fleetCount',
                  'overlayUsageSeconds',
                ])
                  SizedBox(
                    width: 160,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t(key)),
                        Text(
                          key == 'registeredAccountCount' &&
                                  (data[key] is! int || (data[key] as int) < 0)
                              ? t('unavailable')
                              : key == 'overlayUsageSeconds'
                              ? (data[key] / 3600).toStringAsFixed(1)
                              : '${data[key]}',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(color: tokens.colors.accent),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            Text(t('accountsScope')),
            Text(
              '${t('updated')} · ${DateTime.parse(data['updatedAt']).toLocal()}',
            ),
          ],
          if (data != null && !history && !stats) ...[
            SelectableText(data['currentVersion'] as String? ?? '—'),
            Text(t(data['state'] as String)),
            if (data['availableVersion'] is String)
              Text(data['availableVersion'] as String),
          ],
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: _busy ? null : _load,
              child: Text(t('retry')),
            ),
          ),
        ],
      ),
    );
  }
}

class HelpSupportFeedbackForm extends StatefulWidget {
  const HelpSupportFeedbackForm({
    this.port,
    required this.contact,
    required this.message,
    super.key,
  });
  final HelpSupportPort? port;
  final TextEditingController contact, message;
  @override
  State<HelpSupportFeedbackForm> createState() =>
      _HelpSupportFeedbackFormState();
}

class _HelpSupportFeedbackFormState extends State<HelpSupportFeedbackForm> {
  bool _busy = false;
  String? _status;
  Future<void> _send() async {
    if (_busy || widget.message.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await widget.port!.send(
        widget.contact.text.trim(),
        widget.message.text.trim(),
      );
      if (!mounted) return;
      widget.message.clear();
      setState(() => _status = 'sent');
    } catch (_) {
      if (mounted) setState(() => _status = 'unconfirmed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => helpLiveText(context, key);
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t('feedbackInfo')),
          const SizedBox(height: 12),
          TextField(
            key: const Key('help-feedback-contact'),
            controller: widget.contact,
            enabled: !_busy,
            maxLength: 120,
            decoration: InputDecoration(labelText: t('contact')),
          ),
          TextField(
            key: const Key('help-feedback-message'),
            controller: widget.message,
            enabled: !_busy,
            minLines: 4,
            maxLines: 8,
            maxLength: 2000,
            decoration: InputDecoration(labelText: t('message')),
            onChanged: (_) => setState(() {}),
          ),
          if (_status != null)
            Text(
              t(_status!),
              style: TextStyle(
                color: _status == 'sent'
                    ? context.tokens.colors.success
                    : context.tokens.colors.warning,
              ),
            ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton(
              key: const Key('help-feedback-send'),
              onPressed:
                  _busy ||
                      widget.port == null ||
                      widget.message.text.trim().isEmpty
                  ? null
                  : _send,
              child: Text(t(_busy ? 'sending' : 'send')),
            ),
          ),
        ],
      ),
    );
  }
}
