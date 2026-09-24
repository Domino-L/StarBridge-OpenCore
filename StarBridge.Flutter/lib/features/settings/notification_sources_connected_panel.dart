import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/icons/icon_semantic.dart';
import 'bridge_notification_sources.dart';
import 'notification_editor_frame.dart';
import 'notification_settings_common.dart';
import 'notification_settings_models.dart';
import 'notification_settings_sources.dart';

class NotificationSourcesConnectedPanel extends StatefulWidget {
  const NotificationSourcesConnectedPanel({required this.port, super.key});
  final NotificationSourcesPort port;
  @override
  State<NotificationSourcesConnectedPanel> createState() => _State();
}

class _State extends State<NotificationSourcesConnectedPanel> {
  NotificationSourcesValue? value;
  bool loading = true, failed = false, uncertain = false;
  int request = 0;
  int? draftEpoch;
  late final StreamSubscription<void> events;
  @override
  void initState() {
    super.initState();
    events = widget.port.invalidations.listen((_) {
      if (!mounted) return;
      value = null;
      uncertain = false;
      read();
    });
    read();
  }

  Future<void> read() async {
    final ticket = ++request;
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final next = await widget.port.read();
      if (!mounted || ticket != request) return;
      setState(() {
        value = next;
        loading = false;
        uncertain = false;
      });
    } catch (_) {
      if (!mounted || ticket != request) return;
      setState(() {
        value = null;
        loading = false;
        failed = true;
      });
    }
  }

  String copy(String cn, String tw, String en) {
    final locale = Localizations.localeOf(context);
    return locale.languageCode == 'en'
        ? en
        : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
        ? tw
        : cn;
  }

  @override
  Widget build(BuildContext context) {
    final drafts = NotificationDraftScope.of(context);
    if (draftEpoch != drafts?.epoch) {
      final initial = draftEpoch == null;
      draftEpoch = drafts?.epoch;
      if (!initial && uncertain) {
        loading = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) read();
        });
      }
    }
    final saved = value;
    final modes = saved == null
        ? <String, NotificationSourceMode>{}
        : drafts?.value('notification-sources', saved.modes) ?? saved.modes;
    return NotificationSettingsPanel(
      icon: StarBridgeIconSemantic.community,
      titleKey: 'settings.notification.sources.title',
      descriptionKey: 'settings.notification.sources.description',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            copy(
              '保存后生效，仅影响接收提醒，不改变共享权限。',
              '儲存後生效，僅影響接收提醒，不改變共享權限。',
              'Applied when saved. These rules affect incoming reminders, not sharing permissions.',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            copy(
              '仅重要提醒保留所有私信、房间邀请、加入申请和组织管理待办；不包含普通聊天与玩家动态。',
              '僅重要提醒保留所有私訊、房間邀請、加入申請和組織管理待辦；不包含一般聊天與玩家動態。',
              'Important only includes all private messages, room invitations, join requests and organization management tasks, but not ordinary chat or player activity.',
            ),
          ),
          if (loading)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                copy('正在读取来源规则…', '正在讀取來源規則…', 'Loading source rules…'),
              ),
            )
          else if (failed) ...[
            const SizedBox(height: 12),
            Text(
              copy(
                '暂时无法读取来源规则。请确认账号已登录后重试；其他提醒设置仍可使用。',
                '暫時無法讀取來源規則。請確認帳號已登入後重試；其他提醒設定仍可使用。',
                'Source rules could not be loaded. Check that you are signed in and retry. Other notification settings remain available.',
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: read,
                child: Text(copy('重新读取', '重新讀取', 'Reload')),
              ),
            ),
          ] else if (saved != null) ...[
            for (final source in saved.sources)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: NotificationSourceRuleRow(
                  rule: NotificationSourceRule(
                    sourceRef: source.sourceRef,
                    kind: source.kind,
                    displayName: switch (source.sourceRef) {
                      'room' => copy('房间提醒', '房間提醒', 'Room reminders'),
                      'friends' => copy('好友动态', '好友動態', 'Friend activity'),
                      'directMessages' => copy('私信', '私訊', 'Private messages'),
                      _ => source.displayName,
                    },
                    contextLabel: '',
                    mode: modes[source.sourceRef]!,
                    logoImageData: source.logoImageData,
                  ),
                  enabled: drafts != null && !drafts.saving && !uncertain,
                  onChanged: (mode) async {
                    if (drafts == null) return false;
                    final epoch = drafts.epoch;
                    drafts.edit(
                      'notification-sources',
                      saved.modes,
                      {...modes, source.sourceRef: mode},
                      (next) async {
                        try {
                          final result = await widget.port.save(saved, next);
                          if (!mounted || epoch != drafts.epoch) return false;
                          setState(() {
                            value = result;
                            uncertain = false;
                          });
                          return true;
                        } catch (_) {
                          if (mounted && epoch == drafts.epoch) {
                            setState(() => uncertain = true);
                          }
                          return false;
                        }
                      },
                    );
                    return true;
                  },
                ),
              ),
            if (uncertain)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  copy(
                    '尚未确认来源规则已保存。可再次点击“保存更改”；放弃更改将重新读取已生效的设置。',
                    '尚未確認來源規則已儲存。可再次點選「儲存變更」；放棄變更將重新讀取已生效的設定。',
                    'Saving has not been confirmed. Retry Save changes, or discard to reload the settings currently in effect.',
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    request++;
    events.cancel();
    super.dispose();
  }
}
