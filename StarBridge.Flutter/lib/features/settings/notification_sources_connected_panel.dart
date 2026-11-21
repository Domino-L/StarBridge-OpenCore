import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import 'bridge_notification_sources.dart';
import 'notification_editor_frame.dart';
import 'notification_settings_common.dart';
import 'notification_settings_models.dart';
import 'notification_settings_sources.dart';
import 'notification_organization_options.dart';
import 'notification_organization_controls.dart';
import '../../app/localization/app_strings.dart';
import '../../platform/bridge/bridge_client_session.dart';

class NotificationSourcesConnectedPanel extends StatefulWidget {
  const NotificationSourcesConnectedPanel({required this.port, super.key});
  final NotificationSourcesPort port;
  @override
  State<NotificationSourcesConnectedPanel> createState() => _State();
}

class _State extends State<NotificationSourcesConnectedPanel> {
  NotificationSourcesValue? value;
  bool loading = true, failed = false, saveFailed = false;
  bool uncertain = false;
  int request = 0;
  int _binding = 0, _completed = 0;
  InteractionSource _source = InteractionSource.programmatic;
  int? draftEpoch;
  StreamSubscription<void>? events;
  @override
  void initState() {
    super.initState();
    _attach();
    read();
  }

  void _attach() {
    final owner = widget.port;
    events = owner.invalidations.listen((_) {
      if (!identical(owner, widget.port)) return;
      if (!mounted) return;
      _binding++;
      value = null;
      saveFailed = false;
      uncertain = false;
      read();
    });
  }

  @override
  void didUpdateWidget(NotificationSourcesConnectedPanel old) {
    super.didUpdateWidget(old);
    if (!identical(old.port, widget.port)) {
      request++;
      _binding++;
      _completed = 0;
      _source = InteractionSource.programmatic;
      unawaited(events?.cancel());
      value = null;
      saveFailed = false;
      uncertain = false;
      draftEpoch = null;
      _attach();
      read();
    }
  }

  Future<void> read() async {
    final ticket = ++request;
    final owner = widget.port;
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final next = await owner.read();
      if (!mounted || ticket != request || !identical(owner, widget.port)) {
        return;
      }
      setState(() {
        value = next;
        loading = false;
        saveFailed = false;
        uncertain = false;
        _completed++;
      });
    } catch (_) {
      if (!mounted || ticket != request || !identical(owner, widget.port)) {
        return;
      }
      setState(() {
        loading = false;
        failed = true;
        _completed++;
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
    final owner = widget.port, binding = _binding;
    final drafts = NotificationDraftScope.of(context);
    if (draftEpoch != drafts?.epoch) {
      final initial = draftEpoch == null;
      draftEpoch = drafts?.epoch;
      if (!initial && saveFailed) {
        loading = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) read();
        });
      }
    }
    final saved = value;
    final initial =
        <String, (NotificationSourceMode, NotificationOrganizationOptions)>{
          if (saved != null)
            for (final s in saved.sources)
              s.sourceRef: (s.mode, s.organizationOptions),
        };
    final choices = drafts?.value('notification-sources', initial) ?? initial;
    Future<bool> editChoices(
      Map<String, (NotificationSourceMode, NotificationOrganizationOptions)>
      next,
    ) async {
      if (saved == null ||
          drafts == null ||
          drafts.saving ||
          !mounted ||
          !identical(owner, widget.port) ||
          binding != _binding ||
          loading ||
          failed ||
          uncertain) {
        return false;
      }
      final epoch = drafts.epoch;
      drafts.edit('notification-sources', initial, next, (next) async {
        try {
          if (!mounted ||
              !identical(owner, widget.port) ||
              binding != _binding ||
              epoch != drafts.epoch) {
            return false;
          }
          // Invalid local drafts have not been sent. Keep their controls
          // editable instead of treating them as an uncertain Host write.
          if (next.values.any((choice) => !choice.$2.valid)) return false;
          final result =
              owner is OrganizationNotificationSourcesPort &&
                  saved.supportsOrganizationOptions
              ? await owner.saveOrganizationOptions(
                  saved,
                  {for (final e in next.entries) e.key: e.value.$1},
                  {
                    for (final s in saved.sources)
                      if (s.kind == NotificationSourceKind.community ||
                          s.kind == NotificationSourceKind.officialFleet)
                        s.sourceRef: next[s.sourceRef]!.$2,
                  },
                )
              : await owner.save(saved, {
                  for (final e in next.entries) e.key: e.value.$1,
                });
          if (!mounted ||
              !identical(owner, widget.port) ||
              binding != _binding ||
              epoch != drafts.epoch) {
            return false;
          }
          setState(() {
            value = result;
            saveFailed = false;
            uncertain = false;
          });
          return true;
        } catch (error) {
          if (mounted &&
              identical(owner, widget.port) &&
              binding == _binding &&
              epoch == drafts.epoch) {
            // A known write failure permits editing. An unconfirmed write
            // freezes the submitted draft so an explicit retry reuses it.
            setState(() {
              saveFailed = true;
              uncertain =
                  error is! BridgeRemoteException ||
                  error.code != 'notificationPolicies.save_failed';
            });
          }
          return false;
        }
      });
      return true;
    }

    return NotificationSettingsPanel(
      icon: StarBridgeIconSemantic.community,
      titleKey: 'settings.notification.sources.title',
      descriptionKey: 'settings.notification.sources.description',
      child: StarBridgeInteractionRegion(
        child: Builder(
          builder: (context) {
            final data = InteractionScope.of(context);
            final effective = data.copyWith(
              reduceMotion:
                  data.reduceMotion ||
                  resolveStarBridgeInitialReadSource(context, _source) ==
                      InteractionSource.keyboard,
            );
            return Stack(
              children: [
                Column(
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
                        child: InteractionScope(
                          data: effective,
                          child: SuiteBusyLabel(
                            copy(
                              '正在读取来源规则…',
                              '正在讀取來源規則…',
                              'Loading source rules…',
                            ),
                          ),
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
                        child: StarBridgeActionButton(
                          controlKey: const Key('notification-sources-reload'),
                          kind: StarBridgeActionKind.quiet,
                          onActivate: (source) {
                            if (!mounted ||
                                !identical(owner, widget.port) ||
                                binding != _binding ||
                                loading) {
                              return;
                            }
                            _source = source;
                            unawaited(runStarBridgeActivation(source, read));
                          },
                          child: Text(copy('重新读取', '重新讀取', 'Reload')),
                        ),
                      ),
                    ],
                    if (saved != null) ...[
                      for (final source in saved.sources)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              NotificationSourceRuleRow(
                                rule: NotificationSourceRule(
                                  sourceRef: source.sourceRef,
                                  kind: source.kind,
                                  displayName: switch (source.sourceRef) {
                                    'room' => copy(
                                      '房间提醒',
                                      '房間提醒',
                                      'Room reminders',
                                    ),
                                    'friends' => copy(
                                      '好友动态',
                                      '好友動態',
                                      'Friend activity',
                                    ),
                                    'directMessages' => copy(
                                      '私信',
                                      '私訊',
                                      'Private messages',
                                    ),
                                    _ => source.displayName,
                                  },
                                  contextLabel: '',
                                  mode: choices[source.sourceRef]!.$1,
                                  logoImageData: source.logoImageData,
                                ),
                                enabled:
                                    drafts != null &&
                                    !drafts.saving &&
                                    !loading &&
                                    !failed &&
                                    !uncertain,
                                onChanged: (mode) => editChoices({
                                  ...choices,
                                  source.sourceRef: (
                                    mode,
                                    choices[source.sourceRef]!.$2,
                                  ),
                                }),
                              ),
                              if (source.kind ==
                                      NotificationSourceKind.community ||
                                  source.kind ==
                                      NotificationSourceKind.officialFleet)
                                if (saved.supportsOrganizationOptions &&
                                    owner
                                        is OrganizationNotificationSourcesPort)
                                  NotificationOrganizationControls(
                                    key: ValueKey(source.sourceRef),
                                    sourceRef: source.sourceRef,
                                    official:
                                        source.kind ==
                                        NotificationSourceKind.officialFleet,
                                    value: choices[source.sourceRef]!.$2,
                                    enabled:
                                        drafts != null &&
                                        !drafts.saving &&
                                        !loading &&
                                        !failed &&
                                        !uncertain,
                                    onChanged: (options) => unawaited(
                                      editChoices({
                                        ...choices,
                                        source.sourceRef: (
                                          choices[source.sourceRef]!.$1,
                                          options,
                                        ),
                                      }),
                                    ),
                                  )
                                else
                                  Text(
                                    AppStrings.of(context).text(
                                      'settings.notification.organization.upgrade',
                                    ),
                                  ),
                            ],
                          ),
                        ),
                      if (saveFailed)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              AppStrings.of(
                                context,
                              ).text('settings.notification.error.writeFailed'),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: InteractionScope(
                        data: effective,
                        child: SuiteBusyFrame(
                          key: ValueKey(binding),
                          busy: loading,
                          doneToken: _completed,
                          doneOutcome: failed
                              ? TaskOutcome.failure
                              : TaskOutcome.success,
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    request++;
    unawaited(events?.cancel());
    super.dispose();
  }
}
