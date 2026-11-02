import '../../shared/guide/guide_scope.dart';
import '../../shared/guide/guide_tours.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/icons/icon_semantic.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../platform/window/method_channel_hangar_browser.dart';
import '../../platform/window/native_viewport_visibility.dart';
import '../account/account_module.dart';
import '../account/account_models.dart';
import '../communities/community_hangar_sharing_port.dart';
import '../../app/routing/open_destination_intent.dart';
import 'hangar_browser_viewport.dart';
import 'hangar_reader_controller.dart';
import 'hangar_reader_copy.dart';
import 'hangar_reader_waiting.dart';
import 'hangar_reader_port.dart';
import 'hangar_reader_results.dart';
import 'hangar_inventory_port.dart';
import 'hangar_inventory_module.dart';
import 'hangar_inventory_page.dart';
import 'hangar_inventory_copy.dart';
import 'local_hangar_port.dart';
import 'local_hangar_page.dart';
import 'local_hangar_save_panel.dart';
import 'hangar_sharing_action.dart';
import '../onboarding/connection_mode_port.dart';
import 'hangar_display_session.dart';

class HangarPage extends StatefulWidget {
  const HangarPage({
    required this.account,
    required this.previewFactory,
    this.browserFactory,
    this.inventoryPort,
    this.localFactory,
    this.sharingPort,
    this.connectionMode,
    this.offlineFactory,
    this.retainedFactory,
    this.displaySession,
    super.key,
  });
  final AccountModule account;
  final HangarPreviewPort Function() previewFactory;
  final HangarBrowserPort Function()? browserFactory;
  final HangarInventoryPort? inventoryPort;
  final LocalHangarPort Function()? localFactory;
  final CommunityHangarSharingPort? sharingPort;
  final ConnectionModeControl? connectionMode;
  final LocalHangarPort Function(int revision)? offlineFactory;
  final LocalHangarPort Function(String readId)? retainedFactory;
  final HangarDisplaySession? displaySession;
  @override
  State<HangarPage> createState() => _HangarPageState();
}

class _HangarPageState extends State<HangarPage> {
  HangarReaderController? _reader;
  InteractionSource _readerSource = InteractionSource.programmatic;
  InteractionSource? _returnSource;
  int _readerWaitPhase = 0;
  HangarInventoryModule? _inventory;
  bool _testAvailable = false;
  int _localRevision = 0;
  LocalHangarPort? _localPort;
  LocalHangarPort? _offlinePort;
  Object? _modeKey;
  String? _retainedReadId;
  late int _generation;
  bool get _hasAccount =>
      widget.account.projection.value.isSignedIn ||
      widget.account.projection.value.sessionState ==
          AccountSessionState.legacySignedIn;
  @override
  void initState() {
    super.initState();
    _generation = widget.account.projection.value.generation;
    widget.account.projection.addListener(_accountChanged);
    widget.connectionMode?.addListener(_modeChanged);
    widget.displaySession?.addListener(_displayChanged);
    final port = widget.inventoryPort;
    if (port != null) {
      unawaited(
        port.available().then((enabled) {
          if (mounted) setState(() => _testAvailable = enabled);
        }),
      );
    }
  }

  void _displayChanged() {
    if (mounted) setState(() {});
  }

  void _modeChanged() {
    final mode = widget.connectionMode;
    final key = (
      mode?.snapshot.scope,
      mode?.snapshot.state,
      mode?.snapshot.revision,
      mode?.failed,
      mode?.snapshot.offlineAccount?.displayName,
      mode?.snapshot.offlineAccount?.cachedAtUtc,
    );
    if (key == _modeKey) return;
    _modeKey = key;
    _returnSource = null;
    _offlinePort = null;
    _localPort = null;
    if (mode?.allowsOnlineTraffic == false) {
      _reader?.dispose();
      _reader = null;
      _inventory?.dispose();
      _inventory = null;
    }
    if (mounted) setState(() {});
  }

  void _accountChanged() {
    final account = widget.account.projection.value;
    if (_retainedReadId != account.retainedReadId) {
      _retainedReadId = account.retainedReadId;
      _offlinePort = null;
    }
    if (account.generation != _generation) {
      _returnSource = null;
      _localPort = null;
      _offlinePort = null;
      _inventory?.dispose();
      _inventory = null;
    }
    if (account.generation != _generation || !_hasAccount) {
      _generation = account.generation;
      if (_reader != null) unawaited(_reader!.cancel(reason: 'accountChanged'));
    }
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!NativeViewportScope.isActive(context) && _reader != null) {
      scheduleMicrotask(() {
        if (mounted) unawaited(_reader?.cancel() ?? Future<void>.value());
      });
    }
  }

  @override
  void dispose() {
    widget.connectionMode?.removeListener(_modeChanged);
    widget.displaySession?.removeListener(_displayChanged);
    widget.account.projection.removeListener(_accountChanged);
    _reader?.dispose();
    _inventory?.dispose();
    super.dispose();
  }

  void _enter() {
    if (!_hasAccount ||
        _reader != null ||
        widget.connectionMode?.allowsOnlineTraffic == false) {
      return;
    }
    final reader = HangarReaderController(
      widget.browserFactory?.call() ?? MethodChannelHangarBrowser(),
      widget.previewFactory(),
    );
    setState(() {
      _reader = reader;
      _readerSource = currentStarBridgeActivationSource;
      ++_readerWaitPhase;
      _returnSource = null;
    });
    unawaited(runStarBridgeActivation<void>(_readerSource, reader.open));
    guideReport(context, 'hangar.readerOpened');
  }

  /// [finished] after a successful save; otherwise leaving the reader ends
  /// a first-read tour step that needs it.
  void _back({bool finished = false}) {
    if (!finished) {
      guideFlowClosed(GuideScope.maybeOf(context), guideFlowHangarReader);
    }
    _reader?.dispose();
    setState(() {
      _reader = null;
      _returnSource = currentStarBridgeActivationSource;
    });
    final display = widget.displaySession;
    if (display?.confirmed == true) {
      unawaited(display!.read().then<void>((_) {}, onError: (Object _) {}));
    }
  }

  void _readerAction(InteractionSource source, Future<void> Function() action) {
    setState(() {
      _readerSource = source;
      ++_readerWaitPhase;
    });
    unawaited(runStarBridgeActivation<void>(source, action));
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.connectionMode;
    if (mode?.failed == false &&
        mode?.snapshot.isOffline == true &&
        mode?.snapshot.offlineAccount != null &&
        widget.offlineFactory != null) {
      final revision = mode!.snapshot.revision!;
      return LocalHangarPage(
        key: ValueKey(('offline-hangar', mode.snapshot.scope, revision)),
        port: _offlinePort ??= widget.offlineFactory!(revision),
        onRead: null,
      );
    }
    final inventory = _inventory;
    final account = widget.account.projection.value;
    final display = widget.displaySession;
    if (display?.canDisplay == true && !display!.confirmed) {
      return LocalHangarPage(
        key: ObjectKey(display),
        port: display,
        onRead: null,
      );
    }
    if ((mode == null || mode.allowsOnlineTraffic) &&
        account.hasRetainedDisplayRead &&
        display == null &&
        widget.retainedFactory != null) {
      final id = account.retainedReadId!;
      return LocalHangarPage(
        key: ValueKey(('retained-hangar', account.generation, id)),
        port: _offlinePort ??= widget.retainedFactory!(id),
        onRead: null,
      );
    }
    if (inventory != null) {
      return HangarInventoryPage(
        module: inventory,
        onBack: () {
          inventory.dispose();
          setState(() => _inventory = null);
        },
      );
    }
    final copy = HangarReaderCopy(context);
    final reader = _reader;
    if (reader == null) {
      if (widget.localFactory != null && _hasAccount) {
        final page = LocalHangarPage(
          key: display?.canDisplay == true
              ? ObjectKey(display)
              : ValueKey('local-hangar:$_generation:$_localRevision'),
          port: display?.canDisplay == true
              ? display!
              : _localPort ??= widget.localFactory!(),
          onRead: mode?.allowsOnlineTraffic == false ? null : _enter,
          extraAction: mode?.allowsOnlineTraffic == false
              ? null
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (widget.sharingPort?.hangarSharingAvailable == true)
                      HangarSharingAction(
                        key: ValueKey('hangar-sharing:$_generation'),
                        port: widget.sharingPort!,
                      ),
                    if (_testAvailable)
                      StarBridgeActionButton(
                        controlKey: const Key('hangar-test-workspace-extra'),
                        onActivate: (_) => setState(
                          () => _inventory = HangarInventoryModule(
                            widget.inventoryPort!,
                          ),
                        ),
                        child: Text(HangarInventoryCopy(context).testTitle),
                      ),
                  ],
                ),
        );
        return _returnSource == null
            ? page
            : starBridgeInitialReadViewport(
                context,
                source: _returnSource!,
                child: page,
              );
      }
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 660),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StarBridgeIcon(
                  StarBridgeIconSemantic.hangar,
                  size: 36,
                  color: context.tokens.colors.accent,
                ),
                const SizedBox(height: 18),
                Text(
                  copy.noInventory,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                Text(copy.intro),
                const SizedBox(height: 24),
                if (_testAvailable) ...[
                  StarBridgeActionButton(
                    controlKey: const Key('hangar-test-workspace'),
                    onActivate: (_) => setState(
                      () => _inventory = HangarInventoryModule(
                        widget.inventoryPort!,
                      ),
                    ),
                    child: Text(HangarInventoryCopy(context).testTitle),
                  ),
                  const SizedBox(height: 12),
                ],
                StarBridgeActionButton(
                  controlKey: const Key('hangar-open-reader'),
                  kind: StarBridgeActionKind.primary,
                  onActivate: _hasAccount
                      ? (_) => _enter()
                      : (_) => Actions.maybeInvoke(
                          context,
                          const OpenDestinationIntent('/settings/account'),
                        ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StarBridgeIcon(
                        _hasAccount
                            ? StarBridgeIconSemantic.hangar
                            : StarBridgeIconSemantic.login,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(_hasAccount ? copy.title : copy.login),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return ListenableBuilder(
      listenable: reader,
      builder: (context, _) {
        final tokens = context.tokens;
        final complete = ['complete', 'needsReview'].contains(reader.phase);
        if (complete) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) guideReport(context, 'hangar.readDone');
          });
        }
        final warning = ![
          'idle',
          'ready',
          'opening',
          'starting',
          'reading',
          'verifying',
          'complete',
        ].contains(reader.phase);
        final tone = warning
            ? tokens.colors.warning
            : complete
            ? tokens.colors.success
            : tokens.colors.stateAccent;
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 20,
                runSpacing: 8,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StarBridgeIconAction(
                        controlKey: const Key('hangar-reader-back'),
                        label: copy.back,
                        onActivate: (_) => _back(),
                        icon: const RotatedBox(
                          quarterTurns: 2,
                          child: StarBridgeIcon(StarBridgeIconSemantic.forward),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        copy.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  Text(
                    '${copy.account} · ${widget.account.projection.value.identity.authoritativeHandle ?? "—"}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                key: const Key('hangar-reader-status'),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: tokens.surfaces.panel.fill,
                  border: Border(left: BorderSide(color: tone, width: 3)),
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 650),
                      child: Semantics(
                        liveRegion: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              copy.status(reader.phase),
                              style: TextStyle(color: tone),
                            ),
                            if (reader.view.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                copy.progress(
                                  reader.view['pagesRead'] as int? ?? 0,
                                  reader.view['totalPages'] as int?,
                                  reader.view['shipCount'] as int? ?? 0,
                                ),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (reader.busy)
                          StarBridgeActionButton(
                            controlKey: const Key('hangar-reader-cancel'),
                            onActivate: (_) => unawaited(reader.cancel()),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const StarBridgeIcon(
                                  StarBridgeIconSemantic.windowClose,
                                ),
                                const SizedBox(width: 8),
                                Flexible(child: Text(copy.cancel)),
                              ],
                            ),
                          )
                        else if (_hasAccount)
                          GuideAnchor(
                            id: 'hangar.action',
                            child: StarBridgeActionButton(
                              controlKey: const Key('hangar-reader-action'),
                              kind: StarBridgeActionKind.primary,
                              onActivate: !reader.canAct
                                  ? null
                                  : reader.browserOpen && !complete
                                  ? (source) =>
                                        _readerAction(source, reader.read)
                                  : (source) =>
                                        _readerAction(source, reader.open),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  StarBridgeIcon(
                                    reader.browserOpen && !complete
                                        ? StarBridgeIconSemantic.forward
                                        : StarBridgeIconSemantic.hangar,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      reader.browserOpen && !complete
                                          ? reader.paused
                                                ? copy.resume
                                                : copy.start
                                          : reader.phase == 'idle'
                                          ? copy.open
                                          : copy.retry,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (reader.browserOpen && !reader.busy && !complete)
                          StarBridgeActionButton(
                            controlKey: const Key('hangar-reader-reopen'),
                            onActivate: reader.canAct
                                ? (source) => _readerAction(source, reader.open)
                                : null,
                            child: Text(copy.retry),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(
                key: const Key('hangar-reader-progress'),
                height: 3,
                child: reader.busy
                    ? HangarReaderWaiting(
                        key: ValueKey(('reader-wait', _readerWaitPhase)),
                        source: _readerSource,
                        color: tone,
                      )
                    : null,
              ),
              const SizedBox(height: 10),
              if (complete &&
                  reader.view['canSave'] == true &&
                  widget.localFactory != null) ...[
                GuideAnchor(
                  id: 'hangar.save',
                  child: LocalHangarSavePanel(
                    key: ValueKey(reader.view['operationId']),
                    port: widget.localFactory!(),
                    view: reader.view,
                    initialSource: _readerSource,
                    onSaved: () {
                      GuideScope.maybeOf(context)?.controller
                          .markDone('hangar');
                      guideReport(context, 'hangar.saved');
                      _localRevision++;
                      _back(finished: true);
                    },
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Expanded(
                child: complete
                    ? GuideAnchor(
                        id: 'hangar.results',
                        child: HangarReaderResults(
                          view: reader.view,
                          complete: true,
                          arrivals: reader.arrivals,
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final browser = reader.browserOpen
                              ? GuideAnchor(
                                  id: 'hangar.browser',
                                  child: Container(
                                    key: const Key('hangar-browser-viewport'),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: tokens.surfaces.panel.border,
                                      ),
                                    ),
                                    child: HangarBrowserViewport(
                                      key: ValueKey(reader.browserRevision),
                                      browser: reader.browser,
                                      visible: true,
                                      interactive: !reader.busy,
                                    ),
                                  ),
                                )
                              : Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 520,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        StarBridgeIcon(
                                          StarBridgeIconSemantic.hangar,
                                          size: 44,
                                          color: tokens.colors.textSecondary,
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          copy.instructions,
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                          final results = GuideAnchor(
                            id: 'hangar.results',
                            child: HangarReaderResults(
                              key: const Key('hangar-reader-live-results'),
                              view: reader.view,
                              complete: false,
                              arrivals: reader.arrivals,
                            ),
                          );
                          if (constraints.maxWidth >= 900) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: browser),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: (constraints.maxWidth * .32).clamp(
                                    280.0,
                                    380.0,
                                  ),
                                  child: results,
                                ),
                              ],
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(flex: 3, child: browser),
                              const SizedBox(height: 12),
                              Expanded(flex: 2, child: results),
                            ],
                          );
                        },
                      ),
              ),
              const SizedBox(height: 10),
              Text(
                copy.safety,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: tokens.colors.textSecondary),
              ),
            ],
          ),
        );
      },
    );
  }
}
