import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_dialog_owner.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
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
  PrivacyPageDrafts drafts = PrivacyPageDrafts();
  StreamSubscription? events;
  Object? _registeredOwner;
  Future<bool> Function()? _guard;
  Future<bool>? _pendingLeave;
  StarBridgeDialogRoute<String>? _route;
  int _binding = 0, _completed = 0;
  InteractionSource _source = InteractionSource.programmatic;

  bool _current(int binding, PrivacyPageDrafts group) =>
      mounted &&
      binding == _binding &&
      identical(group, drafts) &&
      identical(notificationLeaveGuards[widget.owner], _guard);

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    final binding = _binding;
    final group = drafts;
    _registeredOwner = widget.owner;
    _guard = () => _current(binding, group) ? _leave() : Future.value(false);
    notificationLeaveGuards[widget.owner] = _guard;
    events = widget.session?.events.listen((event) {
      if (!_current(binding, group)) return;
      if (event.name == 'account.changed' ||
          event.name == 'bootstrap.invalidated') {
        _rotate();
        if (mounted) setState(() {});
      }
    });
  }

  void _detach() {
    final owner = _registeredOwner;
    if (owner != null && identical(notificationLeaveGuards[owner], _guard)) {
      notificationLeaveGuards[owner] = null;
    }
    _registeredOwner = null;
    _pendingLeave = null;
    retireStarBridgeDialog(_route);
    _route = null;
    unawaited(events?.cancel());
    events = null;
  }

  void _rotate() {
    _detach();
    _binding++;
    drafts.dispose();
    drafts = PrivacyPageDrafts();
    _completed = 0;
    _source = InteractionSource.programmatic;
    _attach();
  }

  @override
  void didUpdateWidget(NotificationEditorFrame old) {
    super.didUpdateWidget(old);
    if (!identical(old.owner, widget.owner) ||
        !identical(old.session, widget.session)) {
      _rotate();
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

  String get save => copy('保存更改', '儲存變更', 'Save changes');
  String get discard => copy('放弃更改', '放棄變更', 'Discard changes');

  Future<bool> _save(InteractionSource source) async {
    final group = drafts, binding = _binding, epoch = drafts.epoch;
    if (!_current(binding, group) || group.saving || !group.dirty) return false;
    setState(() => _source = source);
    final result = await runStarBridgeActivation<bool>(source, group.save);
    if (!_current(binding, group) || epoch != group.epoch) return false;
    setState(() => _completed++);
    return result;
  }

  Future<bool> _leave() {
    final existing = _pendingLeave;
    if (existing != null) return existing;
    late final Future<bool> request;
    request = _askLeave().whenComplete(() {
      if (identical(_pendingLeave, request)) _pendingLeave = null;
    });
    _pendingLeave = request;
    return request;
  }

  Future<bool> _askLeave() async {
    final group = drafts, binding = _binding, epoch = drafts.epoch;
    if (!_current(binding, group) || group.saving) return false;
    if (!group.dirty) return true;
    bool current() => _current(binding, group) && epoch == group.epoch;
    var responseSource = StarBridgeActivationOrigin.sourceOf(context);
    final title = copy('尚有未保存的更改', '尚有未儲存的變更', 'Unsaved changes');
    final message = copy(
      '保存后应用本页的提醒设置，或放弃更改。',
      '儲存後套用本頁的提醒設定，或放棄變更。',
      'Save to apply this page’s notification settings, or discard your changes.',
    );
    final stay = copy('继续编辑', '繼續編輯', 'Keep editing');
    final discardLabel = discard, saveLabel = save;
    StarBridgeDialogRoute<String>? route;
    final result = await showStarBridgeDialog<String>(
      context,
      source: responseSource,
      barrierDismissible: false,
      onRouteCreated: (value) {
        route = value;
        _route = value;
      },
      builder: (dialogContext) {
        void choose(String value, InteractionSource source) {
          if (!current() || route?.isCurrent != true) return;
          responseSource = source;
          dismissStarBridgeDialog(dialogContext, source: source, result: value);
        }

        return StarBridgeDialogOwnerGuard(
          isCurrent: current,
          child: AlertDialog(
            key: const Key('notification-leave-dialog'),
            title: Text(title),
            content: Text(message),
            actions: [
              StarBridgeActionButton(
                controlKey: const Key('notification-leave-stay'),
                kind: StarBridgeActionKind.quiet,
                onActivate: (source) => choose('stay', source),
                child: Text(stay),
              ),
              StarBridgeActionButton(
                controlKey: const Key('notification-leave-discard'),
                kind: StarBridgeActionKind.quiet,
                onActivate: (source) => choose('discard', source),
                child: Text(discardLabel),
              ),
              StarBridgeActionButton(
                controlKey: const Key('notification-leave-save'),
                kind: StarBridgeActionKind.primary,
                onActivate: (source) => choose('save', source),
                child: Text(saveLabel),
              ),
            ],
          ),
        );
      },
    );
    if (identical(_route, route)) _route = null;
    if (!current()) return false;
    if (result == 'save') return _save(responseSource);
    if (result == 'discard') {
      group.discard();
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    _detach();
    _binding++;
    drafts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NotificationDraftScope(
    drafts: drafts,
    child: Column(
      children: [
        Expanded(
          child: KeyedSubtree(key: ValueKey(_binding), child: widget.child),
        ),
        StarBridgeInteractionRegion(
          child: Builder(
            builder: (context) {
              final data = InteractionScope.of(context);
              final group = drafts, binding = _binding;
              return ListenableBuilder(
                listenable: group,
                builder: (context, _) {
                  final enabled =
                      _current(binding, group) && group.dirty && !group.saving;
                  final effective = data.copyWith(
                    reduceMotion:
                        data.reduceMotion ||
                        _source == InteractionSource.keyboard,
                  );
                  final status = group.saving
                      ? copy('正在保存…', '正在儲存…', 'Saving…')
                      : group.failed
                      ? copy(
                          '部分更改未能确认，未保存项已保留。',
                          '部分變更未能確認，未儲存項目已保留。',
                          'Some changes could not be confirmed. Unsaved edits are retained.',
                        )
                      : group.dirty
                      ? copy('有未保存的更改', '有未儲存的變更', 'Unsaved changes')
                      : copy('没有未保存的更改', '沒有未儲存的變更', 'No unsaved changes');
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Semantics(
                              liveRegion: true,
                              child: group.saving
                                  ? InteractionScope(
                                      data: effective,
                                      child: SuiteBusyLabel(status),
                                    )
                                  : Text(status),
                            ),
                            StarBridgeActionButton(
                              controlKey: const Key('notification-discard'),
                              semanticLabel: discard,
                              onActivate: enabled
                                  ? (source) {
                                      if (_current(binding, group)) {
                                        runStarBridgeSynchronousActivation(
                                          source,
                                          group.discard,
                                        );
                                      }
                                    }
                                  : null,
                              child: Text(discard),
                            ),
                            StarBridgeActionButton(
                              controlKey: const Key('notification-save'),
                              semanticLabel: save,
                              kind: StarBridgeActionKind.primary,
                              onActivate: enabled
                                  ? (source) {
                                      if (_current(binding, group)) {
                                        unawaited(
                                          runStarBridgeActivation<bool>(
                                            source,
                                            () => _save(source),
                                          ),
                                        );
                                      }
                                    }
                                  : null,
                              child: Text(save),
                            ),
                          ],
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ExcludeSemantics(
                            child: InteractionScope(
                              data: effective,
                              child: SuiteBusyFrame(
                                key: ValueKey((binding, group.epoch)),
                                busy: group.saving,
                                doneToken: _completed,
                                doneOutcome: group.failed
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
              );
            },
          ),
        ),
      ],
    ),
  );
}
