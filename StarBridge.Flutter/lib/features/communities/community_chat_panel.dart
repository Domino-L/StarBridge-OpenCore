import '../../design_system/icons/standard_icon.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../platform/window/native_viewport_visibility.dart';
import '../direct_messages/chat_send_shortcuts.dart';
import 'community_chat_controller.dart';
import 'community_chat_media_cache.dart';
import 'community_avatar_cache.dart';
import 'community_chat_copy.dart';
import 'community_chat_message_tile.dart';
import 'community_chat_port.dart';
import 'community_preset_port.dart';
import 'community_preset_dialog.dart';

class CommunityChatPanel extends StatefulWidget {
  const CommunityChatPanel({
    required this.port,
    required this.targetRef,
    required this.name,
    required this.onBack,
    this.avatars,
    this.controller,
    super.key,
  });
  final CommunityChatPort port;
  final String targetRef, name;
  final VoidCallback onBack;
  final CommunityAvatarCache? avatars;
  final CommunityChatController? controller;
  @override
  State<CommunityChatPanel> createState() => CommunityChatPanelState();
}

class CommunityChatPanelState extends State<CommunityChatPanel>
    with WidgetsBindingObserver {
  late CommunityChatController model;
  late CommunityChatMediaCache media;
  final _text = TextEditingController(), _scroll = ScrollController();
  final _keys = <String, GlobalKey>{};
  bool _readScheduled = false, _followLatest = true, _dialogOpen = false;
  int? _lastSequence;
  Timer? _poll;
  String t(String key) => communityChatText(context, key);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_scheduleRead);
    _start();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted &&
          _syncContext() &&
          !model.invalidated &&
          model.error != 'refreshRequired') {
        unawaited(model.refresh(silent: true));
      }
    });
  }

  void _start() {
    media = CommunityChatMediaCache(
      widget.port,
      widget.targetRef,
      avatars: widget.avatars,
    );
    model =
        widget.controller ??
        CommunityChatController(widget.port, widget.targetRef);
    model.addListener(_changed);
    _text.text = model.draft;
    _lastSequence = model.messages.lastOrNull?.sequence;
    if (_lastSequence != null) _jumpAfterLayout();
    unawaited(model.enter());
  }

  @override
  void didUpdateWidget(covariant CommunityChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.port != widget.port ||
        oldWidget.avatars != widget.avatars ||
        oldWidget.targetRef != widget.targetRef ||
        oldWidget.controller != widget.controller) {
      model.removeListener(_changed);
      model.setReadingContext(visible: false, foreground: false);
      if (oldWidget.controller == null) model.dispose();
      media.dispose();
      _text.clear();
      _keys.clear();
      _lastSequence = null;
      _followLatest = true;
      _start();
    }
  }

  bool _syncContext() {
    final visible =
        mounted &&
        !_dialogOpen &&
        TickerMode.valuesOf(context).enabled &&
        NativeViewportScope.isActive(context) &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    final foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    model.setReadingContext(visible: visible, foreground: foreground);
    return visible && foreground;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncContext();
    _scheduleRead();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _syncContext();
    if (state == AppLifecycleState.resumed) {
      _scheduleRead();
      WidgetsBinding.instance.scheduleFrame();
    }
  }

  void _changed() {
    if (!mounted) return;
    if (model.invalidated) media.invalidate();
    if (_text.text != model.draft) _text.text = model.draft;
    final last = model.messages.lastOrNull?.sequence;
    final changed = last != _lastSequence;
    _lastSequence = last;
    final retained = model.messages.map((m) => m.messageRef).toSet();
    _keys.removeWhere((key, _) => !retained.contains(key));
    setState(() {});
    if (changed && _followLatest) _jumpAfterLayout();
    _scheduleRead();
  }

  void _jumpAfterLayout() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _scroll.hasClients && _followLatest) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
      _scheduleRead();
    }
  });
  void _scheduleRead({bool retry = false}) {
    if (!mounted || _readScheduled) return;
    _readScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _readScheduled = false;
      if (!mounted || !_syncContext()) return;
      CommunityChatMessage? through;
      for (final message in model.messages) {
        final element = _keys[message.messageRef]?.currentContext;
        final box = element?.findRenderObject();
        final viewport = element
            ?.findAncestorRenderObjectOfType<RenderViewport>();
        if (box is! RenderBox ||
            viewport == null ||
            !box.attached ||
            !box.hasSize) {
          continue;
        }
        final bounds = box.localToGlobal(Offset.zero) & box.size;
        final visible = viewport.localToGlobal(Offset.zero) & viewport.size;
        if (bounds.overlaps(visible) &&
            bounds.intersect(visible).height >= 16) {
          through = message;
        }
      }
      if (through != null) {
        unawaited(model.acknowledgeVisible(through.messageRef, retry: retry));
      }
    });
  }

  Future<void> _older() async {
    _followLatest = false;
    final oldMax = _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;
    final oldOffset = _scroll.hasClients ? _scroll.offset : 0.0;
    final current = model;
    await current.loadOlder();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && model == current && _scroll.hasClients) {
        _scroll.jumpTo(
          (oldOffset + _scroll.position.maxScrollExtent - oldMax).clamp(
            0.0,
            _scroll.position.maxScrollExtent,
          ),
        );
        _scheduleRead();
      }
    });
  }

  Future<bool> confirmLeave() async {
    if (model.sending || _dialogOpen) return false;
    if (model.draft.isNotEmpty ||
        model.draftAttachment != null ||
        model.sendUncertain) {
      _dialogOpen = true;
      _syncContext();
      final leave = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(t('leaveTitle')),
          content: Text(t('leaveBody')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('stay')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('leave')),
            ),
          ],
        ),
      );
      _dialogOpen = false;
      if (!mounted || leave != true) {
        if (mounted) _scheduleRead();
        return false;
      }
      model.discardDraft();
    }
    return mounted;
  }

  Future<void> _back() async {
    if (await confirmLeave() && mounted) widget.onBack();
  }

  Future<void> _sharePreset() async {
    final port = widget.port;
    final current = model;
    if (_dialogOpen || !current.canSubmit || port is! CommunityPresetPort) {
      return;
    }
    _dialogOpen = true;
    _syncContext();
    try {
      final attachment = await showDialog<Map<String, Object?>>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            CommunityPresetDialog(port: port as CommunityPresetPort),
      );
      if (mounted &&
          model == current &&
          !current.invalidated &&
          attachment != null) {
        current.setDraftAttachment(attachment);
      }
    } finally {
      _dialogOpen = false;
      if (mounted) {
        _scheduleRead();
        WidgetsBinding.instance.scheduleFrame();
      }
    }
  }

  @override
  void dispose() {
    media.dispose();
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    model.removeListener(_changed);
    model.setReadingContext(visible: false, foreground: false);
    if (widget.controller == null) model.dispose();
    _scroll.dispose();
    _text.dispose();
    super.dispose();
  }

  Widget _notice(String key, {VoidCallback? retry}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Text(
            t(key),
            style: TextStyle(color: context.tokens.colors.warning),
          ),
        ),
        if (retry != null)
          TextButton(onPressed: retry, child: Text(t('retry'))),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.tokens.surfaces.panel.fill,
        border: Border.all(color: context.tokens.surfaces.panel.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: model.sending ? null : _back,
                tooltip: t('back'),
                icon: const StandardIcon(StandardIconSemantic.arrowBack),
              ),
              Expanded(
                child: Text(
                  '${widget.name} · ${t('title')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                onPressed: model.loading || model.invalidated
                    ? null
                    : model.refresh,
                tooltip: t('refresh'),
                icon: const StandardIcon(StandardIconSemantic.refresh),
              ),
            ],
          ),
          if (model.showProgress)
            const LinearProgressIndicator(minHeight: 2)
          else
            const SizedBox(height: 2),
          if (model.error != null) _notice(model.error!),
          if (model.receiptError != null)
            _notice(
              'readFailed',
              retry: () {
                _scheduleRead(retry: true);
                WidgetsBinding.instance.scheduleFrame();
              },
            ),
          if (model.hasOlder)
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: model.loading ? null : _older,
                child: Text(t('older')),
              ),
            ),
          Expanded(
            child: model.messages.isEmpty
                ? Center(
                    child: Text(
                      model.loading ? '' : t(model.error ?? 'empty'),
                      textAlign: TextAlign.center,
                    ),
                  )
                : NotificationListener<UserScrollNotification>(
                    onNotification: (event) {
                      if (event.direction != ScrollDirection.idle &&
                          _scroll.hasClients) {
                        setState(
                          () =>
                              _followLatest = _scroll.position.extentAfter < 36,
                        );
                      }
                      _scheduleRead();
                      return false;
                    },
                    child: ListView.builder(
                      controller: _scroll,
                      // Desktop scrollbar paints inside the viewport; keep
                      // message avatars and bubbles outside its hit area.
                      padding: const EdgeInsetsDirectional.only(end: 20),
                      itemCount: model.messages.length,
                      itemBuilder: (context, index) {
                        final message = model.messages[index];
                        return CommunityChatMessageTile(
                          key: _keys.putIfAbsent(
                            message.messageRef,
                            GlobalKey.new,
                          ),
                          port: widget.port,
                          mediaCache: media,
                          targetRef: widget.targetRef,
                          message: message,
                        );
                      },
                    ),
                  ),
          ),
          if (!_followLatest || model.hasNewer)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  setState(() => _followLatest = true);
                  _jumpAfterLayout();
                  unawaited(model.refresh());
                },
                icon: const StandardIcon(StandardIconSemantic.arrowDownward, size: 16),
                label: Text(t('latest')),
              ),
            ),
          if (model.sendError != null)
            _notice(
              model.sendError!,
              retry: model.sendUncertain ? () => model.refresh() : null,
            ),
          if (model.draftAttachment case final attachment?)
            ListTile(
              dense: true,
              title: Text(attachment['title'] as String? ?? t('preset')),
              subtitle: Text(t('preset')),
              trailing: IconButton(
                onPressed: model.sending
                    ? null
                    : () => model.setDraftAttachment(null),
                tooltip: t('removeAttachment'),
                icon: const StandardIcon(StandardIconSemantic.close),
              ),
            ),
          if (widget.port is CommunityPresetPort &&
              (widget.port as CommunityPresetPort).communityPresetsAvailable)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: model.canSubmit ? _sharePreset : null,
                icon: const StandardIcon(StandardIconSemantic.attachFile, size: 16),
                label: Text(t('sharePreset')),
              ),
            ),
          ChatSendShortcuts(
            controller: _text,
            onSend: model.canSubmit ? model.submit : null,
            child: TextField(
              key: const ValueKey('community-chat-input'),
              controller: _text,
              enabled: !model.invalidated,
              minLines: 1,
              maxLines: 4,
              maxLength: 1000,
              onChanged: model.updateDraft,
              decoration: InputDecoration(labelText: t('draft')),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  t('keys'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              FilledButton(
                onPressed:
                    model.canSubmit &&
                        (model.draft.trim().isNotEmpty ||
                            model.draftAttachment != null)
                    ? model.submit
                    : null,
                child: Text(t('send')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
