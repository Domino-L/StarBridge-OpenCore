import '../../design_system/icons/standard_icon.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../platform/window/native_viewport_visibility.dart';
import 'community_chat_composer.dart';
import 'community_chat_controller.dart';
import 'community_activity_port.dart';
import 'community_chat_media_cache.dart';
import 'community_avatar_cache.dart';
import 'community_chat_copy.dart';
import 'community_chat_message_tile.dart';
import 'community_local_message_tile.dart';
import 'community_own_avatar.dart';
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
  bool _restoring = false, _positionScheduled = false;
  bool _autoScrolling = false, _readingLayoutPending = false;
  int _positionGeneration = 0, _observedLatest = 0;
  int? _lastSequence;
  Timer? _poll;
  StreamSubscription<void>? _activity;
  String t(String key) => communityChatText(context, key);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_scrollChanged);
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
    unawaited(_activity?.cancel());
    _activity = widget.port is CommunityActivityPort
        ? (widget.port as CommunityActivityPort).workspaceChanges.listen((_) {
            if (mounted && _syncContext()) {
              unawaited(model.refresh(silent: true));
            }
          })
        : null;
    model =
        widget.controller ??
        CommunityChatController(widget.port, widget.targetRef, localEcho: true);
    media = model.media(avatars: widget.avatars);
    model.addListener(_changed);
    _text.text = model.draft;
    _lastSequence = model.messages.lastOrNull?.sequence;
    final saved = model.viewport;
    _followLatest = saved?.followLatest ?? true;
    _observedLatest = saved?.observedLatest ?? _lastSequence ?? 0;
    if (saved != null && !saved.followLatest) {
      _restorePosition(saved);
    } else if (_lastSequence != null) {
      _jumpAfterLayout();
    }
    unawaited(model.enter());
  }

  @override
  void didUpdateWidget(covariant CommunityChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.port != widget.port ||
        oldWidget.avatars != widget.avatars ||
        oldWidget.targetRef != widget.targetRef ||
        oldWidget.controller != widget.controller) {
      _rememberPosition();
      _positionGeneration++;
      _restoring = false;
      model.removeListener(_changed);
      model.setReadingContext(visible: false, foreground: false);
      if (oldWidget.controller == null) model.dispose();
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
    if (_followLatest) _observedLatest = last ?? 0;
    final retained = model.messages.map((m) => m.messageRef).toSet();
    _keys.removeWhere((key, _) => !retained.contains(key));
    setState(() {});
    if (changed && _followLatest) _jumpAfterLayout();
    _scheduleRead();
  }

  void _scrollChanged() {
    _scheduleRead();
    if (_positionScheduled) return;
    _positionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _positionScheduled = false;
      if (mounted) _rememberPosition();
    });
  }

  void _rememberPosition() {
    if (_restoring ||
        _autoScrolling ||
        _readingLayoutPending ||
        !_scroll.hasClients ||
        model.invalidated) {
      return;
    }
    int? anchor;
    var relative = 0.0;
    for (final message in model.messages) {
      final element = _keys[message.messageRef]?.currentContext;
      final box = element?.findRenderObject();
      final viewport = element
          ?.findAncestorRenderObjectOfType<RenderViewport>();
      if (box is! RenderBox ||
          viewport == null ||
          !box.attached ||
          !viewport.attached ||
          !box.hasSize) {
        continue;
      }
      final top =
          box.localToGlobal(Offset.zero).dy -
          viewport.localToGlobal(Offset.zero).dy;
      if (top + box.size.height > 0 && top < viewport.size.height) {
        anchor = message.sequence;
        relative = top;
        break;
      }
    }
    model.rememberViewport(
      CommunityChatViewport(
        pixels: _scroll.offset,
        followLatest: _followLatest,
        observedLatest: _observedLatest,
        anchorSequence: anchor,
        anchorOffset: relative,
      ),
    );
  }

  // Keep receipts paused until lazy layout has restored the measured anchor.
  // A bounded seek also handles wrapping changes after resizing the window.
  void _restorePosition(CommunityChatViewport saved) {
    final generation = ++_positionGeneration;
    _restoring = true;
    void restore(int attempt) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _positionGeneration) return;
        if (!_scroll.hasClients || model.invalidated) {
          _restoring = false;
          return;
        }
        var target = saved.pixels;
        final anchorIndex = model.messages.indexWhere(
          (m) => m.sequence == saved.anchorSequence,
        );
        // Trimmed/expired history must not silently send the reader to latest.
        if (saved.anchorSequence != null && anchorIndex < 0) target = 0;
        if (attempt > 0 && anchorIndex >= 0) {
          final anchorRef = model.messages[anchorIndex].messageRef;
          for (var i = 0; i < model.messages.length; i++) {
            final ref = model.messages[i].messageRef;
            final element = _keys[ref]?.currentContext;
            final box = element?.findRenderObject();
            final viewport = element
                ?.findAncestorRenderObjectOfType<RenderViewport>();
            if (box is! RenderBox ||
                viewport == null ||
                !box.attached ||
                !viewport.attached ||
                !box.hasSize) {
              continue;
            }
            final top =
                box.localToGlobal(Offset.zero).dy -
                viewport.localToGlobal(Offset.zero).dy;
            target = _scroll.offset + top - saved.anchorOffset;
            if (i != anchorIndex) {
              target += (anchorIndex - i) * box.size.height;
            }
            // Prefer the exact anchor if it is already mounted.
            if (i == anchorIndex || _keys[anchorRef]?.currentContext == null) {
              break;
            }
          }
        }
        target = target.clamp(0.0, _scroll.position.maxScrollExtent);
        final settled = attempt > 0 && (target - _scroll.offset).abs() < 0.5;
        _jumpTo(target);
        if (!settled && attempt < 8) {
          restore(attempt + 1);
          WidgetsBinding.instance.scheduleFrame();
        } else {
          _restoring = false;
          _rememberPosition();
          _scheduleRead();
          WidgetsBinding.instance.scheduleFrame();
        }
      });
    }

    restore(0);
  }

  void _jumpTo(double pixels) {
    _autoScrolling = true;
    _readingLayoutPending = true;
    try {
      _scroll.jumpTo(pixels);
    } finally {
      _autoScrolling = false;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _readingLayoutPending = false;
      _rememberPosition();
      _scheduleRead();
      WidgetsBinding.instance.scheduleFrame();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _jumpAfterLayout({int attempt = 0}) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients && _followLatest && !_restoring) {
          _jumpTo(_scroll.position.maxScrollExtent);
          // A lazy list may refine its extent after building the final rows.
          if (attempt < 3) _jumpAfterLayout(attempt: attempt + 1);
        }
      });
  void _scheduleRead({bool retry = false}) {
    if (!mounted || _readScheduled) return;
    _readScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _readScheduled = false;
      if (!mounted || _restoring || _readingLayoutPending || !_syncContext()) {
        return;
      }
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
    _rememberPosition();
    final current = model;
    await current.loadOlder();
    if (mounted && model == current && current.viewport != null) {
      _restorePosition(current.viewport!);
    }
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
    _rememberPosition();
    _positionGeneration++;
    _poll?.cancel();
    unawaited(_activity?.cancel());
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
            child: model.messages.isEmpty && model.localMessages.isEmpty
                ? Center(
                    child: Text(
                      model.loading ? '' : t(model.error ?? 'empty'),
                      textAlign: TextAlign.center,
                    ),
                  )
                : NotificationListener<ScrollNotification>(
                    onNotification: (event) {
                      if (!_restoring &&
                          !_autoScrolling &&
                          event.depth == 0 &&
                          (event is ScrollUpdateNotification ||
                              event is ScrollEndNotification)) {
                        final follow = event.metrics.extentAfter < 36;
                        if (follow != _followLatest) {
                          setState(() => _followLatest = follow);
                        }
                        if (follow) _observedLatest = _lastSequence ?? 0;
                        _rememberPosition();
                      }
                      _scheduleRead();
                      return false;
                    },
                    child: ListView.builder(
                      controller: _scroll,
                      // Desktop scrollbar paints inside the viewport; keep
                      // message avatars and bubbles outside its hit area.
                      padding: const EdgeInsetsDirectional.only(end: 20),
                      itemCount:
                          model.messages.length + model.localMessages.length,
                      itemBuilder: (context, index) {
                        if (index >= model.messages.length) {
                          final local = model
                              .localMessages[index - model.messages.length];
                          return CommunityLocalMessageTile(
                            key: ObjectKey(local),
                            message: local,
                            composerOccupied:
                                model.draft.isNotEmpty ||
                                model.draftAttachment != null,
                            avatar: widget.port is CommunityOwnAvatarSource
                                ? (widget.port as CommunityOwnAvatarSource)
                                      .ownAvatarImageData
                                : null,
                            onRetry: model.canRetry(local)
                                ? () => model.submit(retry: local)
                                : null,
                            onRestore: model.canRestore(local)
                                ? () => model.restoreLocalDraft(local)
                                : null,
                            onCheck: model.loading
                                ? null
                                : () => model.refresh(silent: true),
                          );
                        }
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
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  backgroundColor: context.tokens.surfaces.panel.fill,
                ),
                onPressed: () {
                  _positionGeneration++;
                  _restoring = false;
                  setState(() {
                    _followLatest = true;
                    _observedLatest = _lastSequence ?? 0;
                  });
                  _jumpAfterLayout();
                  unawaited(model.refresh());
                },
                icon: const StandardIcon(
                  StandardIconSemantic.arrowDownward,
                  size: 16,
                ),
                label: Text(
                  t(
                    (_lastSequence ?? 0) > _observedLatest
                        ? 'newMessages'
                        : 'latest',
                  ),
                ),
              ),
            ),
          if (model.sendError != null &&
              (!model.localEcho || model.localMessages.isEmpty))
            _notice(
              model.sendError!,
              retry: model.sendUncertain ? () => model.refresh() : null,
            ),
          if (model.localEcho && model.localMessages.length >= 20)
            _notice('localLimit', retry: () => model.refresh(silent: true)),
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
                icon: const StandardIcon(
                  StandardIconSemantic.attachFile,
                  size: 16,
                ),
                label: Text(t('sharePreset')),
              ),
            ),
          CommunityChatComposer(
            inputKey: const ValueKey('community-chat-input'),
            controller: _text,
            enabled: !model.invalidated,
            onChanged: model.updateDraft,
            onSend: model.canSubmit
                ? () {
                    _followLatest = true;
                    unawaited(model.submit());
                    _jumpAfterLayout();
                  }
                : null,
            canSend:
                model.draft.trim().isNotEmpty || model.draftAttachment != null,
          ),
        ],
      ),
    );
  }
}
