import 'dart:async';

import 'package:flutter/material.dart';

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

class HangarPage extends StatefulWidget {
  const HangarPage({
    required this.account,
    required this.previewFactory,
    this.browserFactory,
    this.inventoryPort,
    this.localFactory,
    this.sharingPort,
    super.key,
  });
  final AccountModule account;
  final HangarPreviewPort Function() previewFactory;
  final HangarBrowserPort Function()? browserFactory;
  final HangarInventoryPort? inventoryPort;
  final LocalHangarPort Function()? localFactory;
  final CommunityHangarSharingPort? sharingPort;
  @override
  State<HangarPage> createState() => _HangarPageState();
}

class _HangarPageState extends State<HangarPage> {
  HangarReaderController? _reader;
  HangarInventoryModule? _inventory;
  bool _testAvailable = false;
  int _localRevision = 0;
  LocalHangarPort? _localPort;
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
    final port = widget.inventoryPort;
    if (port != null) {
      unawaited(
        port.available().then((enabled) {
          if (mounted) setState(() => _testAvailable = enabled);
        }),
      );
    }
  }

  void _accountChanged() {
    final account = widget.account.projection.value;
    if (account.generation != _generation) {
      _localPort = null;
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
    widget.account.projection.removeListener(_accountChanged);
    _reader?.dispose();
    _inventory?.dispose();
    super.dispose();
  }

  void _enter() {
    if (!_hasAccount || _reader != null) return;
    final reader = HangarReaderController(
      widget.browserFactory?.call() ?? MethodChannelHangarBrowser(),
      widget.previewFactory(),
    );
    setState(() => _reader = reader);
    unawaited(reader.open());
  }

  void _back() {
    _reader?.dispose();
    setState(() => _reader = null);
  }

  @override
  Widget build(BuildContext context) {
    final inventory = _inventory;
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
        return LocalHangarPage(
          key: ValueKey('local-hangar:$_generation:$_localRevision'),
          port: _localPort ??= widget.localFactory!(),
          onRead: _enter,
          extraAction: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (widget.sharingPort?.hangarSharingAvailable == true)
                HangarSharingAction(
                  key: ValueKey('hangar-sharing:$_generation'),
                  port: widget.sharingPort!,
                ),
              if (_testAvailable)
                OutlinedButton(
                  onPressed: () => setState(
                    () => _inventory = HangarInventoryModule(
                      widget.inventoryPort!,
                    ),
                  ),
                  child: Text(HangarInventoryCopy(context).testTitle),
                ),
            ],
          ),
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
                  OutlinedButton(
                    key: const Key('hangar-test-workspace'),
                    onPressed: () => setState(
                      () => _inventory = HangarInventoryModule(
                        widget.inventoryPort!,
                      ),
                    ),
                    child: Text(HangarInventoryCopy(context).testTitle),
                  ),
                  const SizedBox(height: 12),
                ],
                FilledButton.icon(
                  key: const Key('hangar-open-reader'),
                  onPressed: _hasAccount
                      ? _enter
                      : () => Actions.maybeInvoke(
                          context,
                          const OpenDestinationIntent('/settings/account'),
                        ),
                  icon: StarBridgeIcon(
                    _hasAccount
                        ? StarBridgeIconSemantic.hangar
                        : StarBridgeIconSemantic.login,
                  ),
                  label: Text(_hasAccount ? copy.title : copy.login),
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
            : tokens.colors.accent;
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
                      IconButton(
                        key: const Key('hangar-reader-back'),
                        tooltip: copy.back,
                        onPressed: _back,
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
                          OutlinedButton.icon(
                            key: const Key('hangar-reader-cancel'),
                            onPressed: () => reader.cancel(),
                            icon: const StarBridgeIcon(
                              StarBridgeIconSemantic.windowClose,
                            ),
                            label: Text(copy.cancel),
                          )
                        else if (_hasAccount)
                          FilledButton.icon(
                            key: const Key('hangar-reader-action'),
                            onPressed: !reader.canAct
                                ? null
                                : reader.browserOpen && !complete
                                ? reader.read
                                : reader.open,
                            icon: StarBridgeIcon(
                              reader.browserOpen && !complete
                                  ? StarBridgeIconSemantic.forward
                                  : StarBridgeIconSemantic.hangar,
                            ),
                            label: Text(
                              reader.browserOpen && !complete
                                  ? reader.paused
                                        ? copy.resume
                                        : copy.start
                                  : reader.phase == 'idle'
                                  ? copy.open
                                  : copy.retry,
                            ),
                          ),
                        if (reader.browserOpen && !reader.busy && !complete)
                          OutlinedButton(
                            onPressed: reader.canAct ? reader.open : null,
                            child: Text(copy.retry),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 3,
                child: reader.busy
                    ? LinearProgressIndicator(
                        value: MediaQuery.disableAnimationsOf(context)
                            ? 0.5
                            : null,
                        color: tone,
                      )
                    : null,
              ),
              const SizedBox(height: 10),
              if (complete &&
                  reader.view['canSave'] == true &&
                  widget.localFactory != null) ...[
                LocalHangarSavePanel(
                  key: ValueKey(reader.view['operationId']),
                  port: widget.localFactory!(),
                  view: reader.view,
                  onSaved: () {
                    _localRevision++;
                    _back();
                  },
                ),
                const SizedBox(height: 10),
              ],
              Expanded(
                child: complete
                    ? HangarReaderResults(
                        view: reader.view,
                        complete: true,
                        arrivals: reader.arrivals,
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final browser = reader.browserOpen
                              ? Container(
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
                          final results = HangarReaderResults(
                            key: const Key('hangar-reader-live-results'),
                            view: reader.view,
                            complete: false,
                            arrivals: reader.arrivals,
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
