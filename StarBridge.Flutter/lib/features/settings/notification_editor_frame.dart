import 'dart:async';

import 'package:flutter/material.dart';

import '../../platform/bridge/bridge_client_session.dart';
import 'privacy_page_drafts.dart';

// Reuse the independently acknowledged draft queue, not privacy permissions.
final notificationLeaveGuards = Expando<Future<bool> Function()>();
Future<bool> confirmNotificationLeave(Object owner) async =>
    await notificationLeaveGuards[owner]?.call() ?? true;

class NotificationDraftScope extends InheritedNotifier<PrivacyPageDrafts> {
  const NotificationDraftScope({
    required PrivacyPageDrafts drafts,
    required super.child,
    super.key,
  }) : super(notifier: drafts);
  static PrivacyPageDrafts? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<NotificationDraftScope>()
      ?.notifier;
}

class NotificationEditorFrame extends StatefulWidget {
  const NotificationEditorFrame({
    required this.owner,
    required this.child,
    this.session,
    super.key,
  });
  final Object owner;
  final Widget child;
  final BridgeClientSession? session;
  @override
  State<NotificationEditorFrame> createState() =>
      _NotificationEditorFrameState();
}

class _NotificationEditorFrameState extends State<NotificationEditorFrame> {
  final drafts = PrivacyPageDrafts();
  StreamSubscription? events;
  @override
  void initState() {
    super.initState();
    notificationLeaveGuards[widget.owner] = _leave;
    events = widget.session?.events.listen((event) {
      if (event.name == 'account.changed' ||
          event.name == 'bootstrap.invalidated') {
        drafts.discard();
      }
    });
  }

  String copy(String cn, String tw, String en) {
    final locale = Localizations.localeOf(context);
    return locale.languageCode == 'en'
        ? en
        : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
        ? tw
        : cn;
  }

  String get save => copy('保存更改', '儲存變更', 'Save changes');
  String get discard => copy('放弃更改', '放棄變更', 'Discard changes');
  Future<bool> _leave() async {
    if (drafts.saving) return false;
    if (!drafts.dirty) return true;
    final epoch = drafts.epoch;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        key: const Key('notification-leave-dialog'),
        title: Text(copy('尚有未保存的更改', '尚有未儲存的變更', 'Unsaved changes')),
        content: Text(
          copy(
            '保存后应用本页的提醒设置，或放弃更改。',
            '儲存後套用本頁的提醒設定，或放棄變更。',
            'Save to apply this page’s notification settings, or discard your changes.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'stay'),
            child: Text(copy('继续编辑', '繼續編輯', 'Keep editing')),
          ),
          TextButton(
            key: const Key('notification-leave-discard'),
            onPressed: () => Navigator.pop(context, 'discard'),
            child: Text(discard),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: Text(save),
          ),
        ],
      ),
    );
    if (!mounted || epoch != drafts.epoch) return false;
    if (result == 'save') return drafts.save();
    if (result == 'discard') {
      drafts.discard();
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    notificationLeaveGuards[widget.owner] = null;
    unawaited(events?.cancel());
    drafts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NotificationDraftScope(
    drafts: drafts,
    child: Column(
      children: [
        Expanded(child: widget.child),
        ListenableBuilder(
          listenable: drafts,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  drafts.saving
                      ? copy('正在保存…', '正在儲存…', 'Saving…')
                      : drafts.failed
                      ? copy(
                          '部分更改未能确认，未保存项已保留。',
                          '部分變更未能確認，未儲存項目已保留。',
                          'Some changes could not be confirmed. Unsaved edits are retained.',
                        )
                      : drafts.dirty
                      ? copy('有未保存的更改', '有未儲存的變更', 'Unsaved changes')
                      : copy('没有未保存的更改', '沒有未儲存的變更', 'No unsaved changes'),
                ),
                OutlinedButton(
                  key: const Key('notification-discard'),
                  onPressed: drafts.dirty && !drafts.saving
                      ? drafts.discard
                      : null,
                  child: Text(discard),
                ),
                FilledButton(
                  key: const Key('notification-save'),
                  onPressed: drafts.dirty && !drafts.saving
                      ? drafts.save
                      : null,
                  child: Text(save),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
