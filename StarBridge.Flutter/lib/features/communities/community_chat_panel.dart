import '../../design_system/icons/standard_icon.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'community_chat_read_schedule.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../platform/window/native_viewport_visibility.dart';
import '../common/organization_holo.dart';
import '../common/social_read_activity.dart';
import 'community_chat_composer.dart';
import 'community_chat_controller.dart';
import 'community_activity_port.dart';
import 'community_chat_media_cache.dart';
import 'community_avatar_cache.dart';
import 'community_chat_copy.dart';
import 'community_chat_holo_effects.dart';
import 'community_chat_holo_parts.dart';
import 'community_chat_panel_parts.dart';
import 'community_chat_message_tile.dart';
import 'community_local_message_tile.dart';
import 'community_own_avatar.dart';
import 'community_chat_port.dart';
import 'community_chat_author_viewport.dart';
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
    this.onBackSource,
    super.key,
  });
  final CommunityChatPort port;
  final String targetRef, name;
  final VoidCallback onBack;
  final ValueChanged<InteractionSource>? onBackSource;
  final CommunityAvatarCache? avatars;
  final CommunityChatController? controller;
  @override
  State<CommunityChatPanel> createState() => CommunityChatPanelState();
}

class CommunityChatPanelState extends State<CommunityChatPanel>
    with
        WidgetsBindingObserver,
        TickerProviderStateMixin,
        CommunityChatHoloEffects<CommunityChatPanel> {
  late CommunityChatController model;
  late CommunityChatMediaCache media;
  late SocialReadActivityBinding _readActivity;
  late SocialReadActivityBinding _sendActivity;
  final _text = TextEditingController(), _scroll = ScrollController();
  final _keys = <String, GlobalKey>{};
  bool _readScheduled = false, _followLatest = true, _dialogOpen = false;
  // Older history loads by itself when the reader scrolls up (as in WeChat);
  // a failed load waits for the button instead of retrying in a loop.
  bool _olderFailed = false, _userScrollingUp = false;
  bool _restoring = false, _positionScheduled = false;
  bool _autoScrolling = false, _readingLayoutPending = false;
  StarBridgeDialogRoute<bool>? _leaveConfirmation;
  int _positionGeneration = 0, _observedLatest = 0;
  int? _lastSequence;
  late final CommunityChatReadDriver _reads;
  StreamSubscription<void>? _activity;
  String t(String key) => communityChatText(context, key);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_scrollChanged);
    _start();
    _reads = CommunityChatReadDriver(
      port: () => widget.port,
      model: () => model,
      canRead: () => mounted && _syncContext(),
      onInputChanged: () => mounted
          ? setState(() {
              _syncContext();
              _scheduleRead();
            })
          : null,
    );
  }

  void _start() {
    unawaited(_activity?.cancel());
    _activity = widget.port is CommunityActivityPort
        ? (widget.port as CommunityActivityPort).workspaceChanges.listen((_) {
            if (mounted && _syncContext()) {
              unawaited(_reads.pushedRead(model));
            }
          })
        : null;
    model =
        widget.controller ??
        CommunityChatController(widget.port, widget.targetRef, localEcho: true);
    model.retireAuthors();
    media = model.media(avatars: widget.avatars);
    _readActivity = SocialReadActivityBinding(
      model,
      () => model.showProgress,
      initialRead: !model.hasLoaded,
    );
    _sendActivity = SocialReadActivityBinding(
      model,
      () => model.sending,
      initialRead: false,
    );
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
    holoReset(model);
    _olderFailed = false;
    unawaited(model.enter());
  }

  @override
  void didUpdateWidget(covariant CommunityChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.port == widget.port &&
        oldWidget.avatars == widget.avatars &&
        oldWidget.controller != null &&
        identical(oldWidget.controller, widget.controller) &&
        oldWidget.targetRef != widget.targetRef) {
      media = model.media(avatars: widget.avatars);
      return;
    }
    if (oldWidget.port != widget.port ||
        oldWidget.avatars != widget.avatars ||
        oldWidget.targetRef != widget.targetRef ||
        oldWidget.controller != widget.controller) {
      _dismissLeaveConfirmation();
      _rememberPosition();
      _positionGeneration++;
      _restoring = false;
      model.removeListener(_changed);
      _readActivity.dispose();
      _sendActivity.dispose();
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
    _reads.syncContext(model, visible: visible);
    return visible && _reads.inFront;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    model.retireAuthors();
    _syncContext();
    _scheduleRead();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Names go at once, even with nothing else about to redraw.
    setState(_syncContext);
    if (state == AppLifecycleState.resumed) {
      _scheduleRead();
      WidgetsBinding.instance.scheduleFrame();
    }
  }

  void _changed() {
    if (!mounted) return;
    if (model.invalidated) {
      _dismissLeaveConfirmation();
      media.invalidate();
    }
    if (_text.text != model.draft) _text.text = model.draft;
    final last = model.messages.lastOrNull?.sequence;
    final changed = last != _lastSequence, previous = _lastSequence;
    _lastSequence = last;
    holoObserve(model, previousLast: previous, following: _followLatest);
    if (_followLatest) _observedLatest = last ?? 0;
    final retained = model.messages.map((m) => m.messageRef).toSet();
    _keys.removeWhere((key, _) => !retained.contains(key));
    setState(() {});
    if (changed && _followLatest) _jumpAfterLayout();
    _scheduleRead();
  }

  void _scrollChanged() {
    model.retireAuthors(notify: true);
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
      final visible = visibleCommunityChatMessages(model.messages, _keys);
      model.observeAuthors(visible);
      final through = visible.lastOrNull;
      model.renewLapsedReceipt().then((ok) => ok ? _scheduleRead(retry: true) : 0);
      if (through != null) {
        unawaited(model.acknowledgeVisible(through.messageRef, retry: retry));
      }
    });
  }

  Future<void> _older() async {
    _followLatest = false;
    _rememberPosition();
    final current = model;
    setState(() => holoLoadingOlder = true);
    await current.loadOlder();
    if (mounted) {
      setState(() {
        holoLoadingOlder = false;
        _olderFailed = current.error != null;
      });
    }
    if (mounted && model == current && current.viewport != null) {
      _restorePosition(current.viewport!);
    }
  }

  void _autoOlder() {
    if (model.hasOlder &&
        !model.loading &&
        !holoLoadingOlder &&
        !_olderFailed) {
      unawaited(_older());
    }
  }

  Future<bool> confirmLeave({InteractionSource? source}) async {
    final current = model;
    if (current.sending || _dialogOpen) return false;
    if (current.draft.isNotEmpty ||
        current.draftAttachment != null ||
        current.sendUncertain) {
      _dialogOpen = true;
      _syncContext();
      final leave = await showCommunityChatLeaveDialog(
        context,
        source: source ?? StarBridgeActivationOrigin.sourceOf(context),
        onRouteCreated: (route) => _leaveConfirmation = route,
      );
      _leaveConfirmation = null;
      _dialogOpen = false;
      if (!mounted ||
          model != current ||
          current.invalidated ||
          leave != true) {
        if (mounted) _scheduleRead();
        return false;
      }
      current.discardDraft();
    }
    return mounted;
  }

  Future<void> _back(InteractionSource source) async {
    if (await confirmLeave(source: source) && mounted) {
      if (widget.onBackSource != null) {
        widget.onBackSource!(currentStarBridgeActivationSource);
      } else {
        widget.onBack();
      }
    }
  }

  void _dismissLeaveConfirmation() {
    final route = _leaveConfirmation;
    _leaveConfirmation = null;
    if (route == null) return;
    scheduleMicrotask(() {
      if (route.isActive) route.navigator?.removeRoute(route, false);
    });
  }

  Future<void> _sharePreset(InteractionSource source) async {
    final port = widget.port;
    final current = model;
    if (_dialogOpen || !current.canSubmit || port is! CommunityPresetPort) {
      return;
    }
    _dialogOpen = true;
    _syncContext();
    try {
      final attachment = await showCommunityPresetDialog(
        context,
        port: port as CommunityPresetPort,
        source: source,
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
    _dismissLeaveConfirmation();
    _rememberPosition();
    _positionGeneration++;
    _reads.dispose();
    unawaited(_activity?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    model.removeListener(_changed);
    _readActivity.dispose();
    _sendActivity.dispose();
    model.setReadingContext(visible: false, foreground: false);
    if (widget.controller == null) model.dispose();
    _scroll.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final holo = OrganizationHolo.of(context);
    final fresh = holoNewCount(model, _observedLatest);
    return CommunityChatHoloAmbient(
      child: Container(
        padding: holo ? EdgeInsets.zero : const EdgeInsets.all(16),
        decoration: holo
            ? null
            : BoxDecoration(
                color: context.tokens.surfaces.panel.fill,
                border: Border.all(color: context.tokens.surfaces.panel.border),
                borderRadius: BorderRadius.circular(6),
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                StarBridgeIconAction(
                  controlKey: const Key('community-chat-back'),
                  onActivate: model.sending ? null : _back,
                  label: t('back'),
                  icon: const StandardIcon(StandardIconSemantic.arrowBack),
                ),
                Expanded(
                  child: CommunityChatTitle('${widget.name} · ${t('title')}'),
                ),
                StarBridgeIconAction(
                  controlKey: const Key('community-chat-refresh'),
                  onActivate: model.loading || model.invalidated
                      ? null
                      : (_) => model.refresh(),
                  label: t('refresh'),
                  icon: const StandardIcon(StandardIconSemantic.refresh),
                ),
              ],
            ),
            if (holo) holoSignal(),
            if (model.showProgress)
              SocialReadActivity(
                key: ValueKey((model, _readActivity.revision)),
                source: _readActivity.source,
                opening: _readActivity.opening,
                label: t('refresh'),
              )
            else
              const SizedBox(height: 2),
            if (model.error != null) CommunityChatNotice(model.error!),
            if (model.receiptError != null)
              CommunityChatNotice(
                communityChatReceiptCopyKey(model.receiptError),
                retry: () {
                  _scheduleRead(retry: true);
                  WidgetsBinding.instance.scheduleFrame();
                },
              ),
            if (model.hasOlder && holoLoadingOlder)
              const CommunityChatOlderProgress()
            else if (model.hasOlder)
              Align(
                alignment: Alignment.center,
                child: StarBridgeActionButton(
                  controlKey: const Key('community-chat-older'),
                  kind: StarBridgeActionKind.quiet,
                  onActivate: model.loading
                      ? null
                      : (_) {
                          _olderFailed = false;
                          unawaited(_older());
                        },
                  child: Text(t('older')),
                ),
              ),
            Expanded(
              child: model.messages.isEmpty && model.localMessages.isEmpty
                  ? holo && model.loading && !model.hasLoaded
                        ? const CommunityChatHoloSkeleton()
                        : Center(
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
                        // Only the reader's own scroll counts, never a jump.
                        if (event is UserScrollNotification &&
                            event.depth == 0) {
                          _userScrollingUp =
                              event.direction == ScrollDirection.forward;
                        }
                        // As in WeChat: nearing the top loads older history.
                        if (_userScrollingUp &&
                            event is ScrollUpdateNotification &&
                            event.depth == 0 &&
                            (event.scrollDelta ?? 0) < 0 &&
                            event.metrics.extentBefore < 240 &&
                            !_restoring &&
                            !_autoScrolling) {
                          _autoOlder();
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
                            final localTile = CommunityLocalMessageTile(
                              key: ObjectKey(local),
                              message: local,
                              source: _sendActivity.source,
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
                            return holoTile(
                              local,
                              local.state == 'sending'
                                  ? CommunityChatHoloSending(child: localTile)
                                  : localTile,
                            );
                          }
                          final message = model.messages[index];
                          final tile = CommunityChatMessageTile(
                            key: _keys.putIfAbsent(message.messageRef, GlobalKey.new),
                            port: widget.port,
                            mediaCache: media,
                            targetRef: widget.targetRef,
                            message: model.presentAuthor(message),
                            authorIsCurrent: model.authorIsCurrent,
                            seenAuthors: model.seenAuthors,
                          );
                          final shown = holoTile(message.messageRef, tile);
                          final day =
                              holo &&
                              communityChatNewDay(
                                index == 0
                                    ? null
                                    : model.messages[index - 1].createdAt,
                                message.createdAt,
                              );
                          final unread =
                              holo && message.messageRef == holoUnreadRef;
                          if (!day && !unread) return shown;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (day) CommunityChatDayBreak(message.createdAt),
                              if (unread) const CommunityChatUnreadBreak(),
                              shown,
                            ],
                          );
                        },
                      ),
                    ),
            ),
            if (!_followLatest || model.hasNewer)
              OrganizationHoloFace(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: StarBridgeActionButton(
                    controlKey: const Key('community-chat-latest'),
                    nativeStyle: holo
                        ? organizationHoloButton(context)
                        : OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            backgroundColor: context.tokens.surfaces.panel.fill,
                          ),
                    onActivate: (_) {
                      _positionGeneration++;
                      _restoring = false;
                      setState(() {
                        _followLatest = true;
                        _observedLatest = _lastSequence ?? 0;
                      });
                      _jumpAfterLayout();
                      unawaited(model.refresh());
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const StandardIcon(
                          StandardIconSemantic.arrowDownward,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            holo && fresh > 0
                                ? t('newCount').replaceAll('{count}', '$fresh')
                                : t(
                                    (_lastSequence ?? 0) > _observedLatest
                                        ? 'newMessages'
                                        : 'latest',
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (model.sendError != null &&
                (!model.localEcho || model.localMessages.isEmpty))
              CommunityChatNotice(
                model.sendError!,
                retry: model.sendUncertain ? () => model.refresh() : null,
              ),
            if (model.localEcho && model.localMessages.length >= 20)
              CommunityChatNotice(
                'localLimit',
                retry: () => model.refresh(silent: true),
              ),
            if (model.draftAttachment case final attachment?)
              ListTile(
                dense: true,
                title: Text(attachment['title'] as String? ?? t('preset')),
                subtitle: Text(t('preset')),
                trailing: StarBridgeIconAction(
                  onActivate: model.sending
                      ? null
                      : (_) => model.setDraftAttachment(null),
                  label: t('removeAttachment'),
                  icon: const StandardIcon(StandardIconSemantic.close),
                ),
              ),
            if (widget.port is CommunityPresetPort &&
                (widget.port as CommunityPresetPort).communityPresetsAvailable)
              Align(
                alignment: Alignment.centerLeft,
                child: StarBridgeActionButton(
                  kind: StarBridgeActionKind.quiet,
                  onActivate: model.canSubmit ? _sharePreset : null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const StandardIcon(
                        StandardIconSemantic.attachFile,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(t('sharePreset')),
                    ],
                  ),
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
                  model.draft.trim().isNotEmpty ||
                  model.draftAttachment != null,
            ),
          ],
        ),
      ),
    );
  }
}
