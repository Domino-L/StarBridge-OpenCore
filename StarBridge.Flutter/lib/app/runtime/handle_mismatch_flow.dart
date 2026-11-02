import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../features/account/account_models.dart';
import '../../features/common/social_read_activity.dart';
import '../composition/handle_mismatch_module.dart';
import '../../features/account/handle_mismatch_port.dart';
import '../localization/app_strings.dart';
import '../composition/handle_mismatch_banner.dart';
import 'startup_prompt_queue.dart';

/// The module owns evidence; this coordinator owns transient prompts only.
/// One difference can be submitted once in the background or shown once in the
/// foreground. Opening/closing alone never clears or mutates the account;
/// a prepared compatibility update requires a separate explicit confirmation.
final class HandleMismatchFlow with WidgetsBindingObserver {
  HandleMismatchFlow({
    required this.module,
    required this.queue,
    required this.ready,
    required this.onOpenAccount,
  }) {
    module.addListener(wake);
    WidgetsBinding.instance.addObserver(this);
    wake();
  }
  final HandleMismatchModule module;
  final StartupPromptQueue queue;
  final bool Function() ready;
  final VoidCallback onOpenAccount;
  final _promptKey = Object();
  final _seen = <HandleMismatchKey>{};
  final _backgroundAttempted = <HandleMismatchKey>{};
  final _backgroundInFlight = <HandleMismatchKey>{};
  int? _generation;
  StarBridgeDialogRoute<bool>? _route;
  HandleMismatchKey? _openKey;
  bool _disposed = false;
  bool get _foreground => switch (WidgetsBinding.instance.lifecycleState) {
    null || AppLifecycleState.resumed => true,
    _ => false,
  };

  void wake() {
    if (_disposed) return;
    final notice = module.notice;
    final generation = module.currentGeneration;
    if (_generation != generation) {
      _generation = generation;
      _seen.clear();
      _backgroundAttempted.clear();
    }
    if (_openKey != null && !module.isCurrent(_openKey!)) _dismissStale();
    queue.cancel(_promptKey);
    if (notice == null || !notice.hasPair || _seen.contains(notice.key)) return;
    if (!_foreground) {
      if (_backgroundAttempted.add(notice.key)) {
        _backgroundInFlight.add(notice.key);
        unawaited(_notify(notice.key));
      }
      return;
    }
    queue.enqueue(
      _promptKey,
      priority: 140,
      eligible: () =>
          !_disposed &&
          ready() &&
          module.isCurrent(notice.key) &&
          !_seen.contains(notice.key) &&
          !_backgroundInFlight.any((key) => key.$1 == notice.generation) &&
          _foreground &&
          _route == null,
      show: () => _open(automatic: true),
    );
  }

  Future<void> _notify(HandleMismatchKey key) async {
    final receipt = await module.notifyBackground(key);
    _backgroundInFlight.remove(key);
    if (_disposed || module.currentGeneration != key.$1) return;
    if (receipt != null && receipt.generation == module.currentGeneration) {
      _seen.add(receipt.key);
    }
    wake();
  }

  Future<void> open() => _open();

  Future<void> _open({bool automatic = false}) async {
    final notice = module.notice, navigator = queue.navigator;
    if (_disposed ||
        notice == null ||
        navigator == null ||
        !navigator.mounted ||
        _route != null) {
      return;
    }
    queue.cancel(_promptKey);
    _seen.add(notice.key);
    _openKey = notice.key;
    final source = captureStarBridgeActivationSource()();
    final route = StarBridgeDialogRoute<bool>(
      data:
          InteractionScope.maybeOf(navigator.context) ??
          resolveStarBridgeInteraction(navigator.context),
      link: InteractionScope.linkOf(navigator.context),
      barrierLabel: MaterialLocalizations.of(navigator.context)
          .modalBarrierDismissLabel,
      // Legacy/manual delegates do not always publish their input source.
      // Unknown is static; the queue's automatic opening is a separate fact.
      instant: !automatic && source != InteractionSource.pointer,
      dismissible: false,
      builder: (_) => _HandleMismatchDialog(module: module, notice: notice),
    );
    _route = route;
    final openAccount = await navigator.push(route);
    module.dismissConfirmation(notice.key);
    if (identical(_route, route)) {
      _route = null;
      _openKey = null;
    }
    if (!_disposed && openAccount == true && module.isCurrent(notice.key)) {
      onOpenAccount();
    }
  }

  void _dismissStale() {
    final route = _route;
    if (route == null) return;
    _route = null;
    _openKey = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route.isActive) route.navigator?.removeRoute(route);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => wake();

  void dispose() {
    _disposed = true;
    queue.cancel(_promptKey);
    module.removeListener(wake);
    WidgetsBinding.instance.removeObserver(this);
    _dismissStale();
  }
}

class _HandleMismatchDialog extends StatefulWidget {
  const _HandleMismatchDialog({required this.module, required this.notice});
  final HandleMismatchModule module;
  final HandleMismatchNotice notice;

  @override
  State<_HandleMismatchDialog> createState() => _HandleMismatchDialogState();
}

class _HandleMismatchDialogState extends State<_HandleMismatchDialog> {
  HandleMismatchModule get module => widget.module;
  HandleMismatchNotice get notice => widget.notice;
  late SocialReadActivityBinding _activity;

  @override
  void initState() {
    super.initState();
    _bindActivity();
  }

  void _bindActivity() {
    _activity = SocialReadActivityBinding(
      module,
      () => module.busy,
      initialRead: false,
    );
  }

  @override
  void didUpdateWidget(covariant _HandleMismatchDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.module, module)) {
      _activity.dispose();
      _bindActivity();
    }
  }

  @override
  void dispose() {
    _activity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: module,
    builder: (context, _) {
      final strings = AppStrings.of(context);
      final current = module.isCurrent(notice.key);
      final state =
          module.checkState ??
          (notice.binding == AccountScmBindingState.bound
              ? HandleCheckState.bound
              : HandleCheckState.unknown);
      return PopScope(
        canPop: !module.busy,
        child: AlertDialog(
          key: const ValueKey('handle-mismatch-dialog'),
          scrollable: true,
          title: Text(strings.text('identity.notice.title')),
          content: SizedBox(
            width: 480,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(handleMismatchPair(strings, notice)),
                    const SizedBox(height: 16),
                    Text(strings.text('identity.notice.body')),
                    const SizedBox(height: 12),
                    Text(strings.text('identity.notice.${state.name}')),
                    const SizedBox(height: 12),
                    Text(
                      strings.text(
                        state == HandleCheckState.ready ||
                                state == HandleCheckState.outcomeUnknown
                            ? 'identity.notice.consequence'
                            : 'identity.notice.readOnly',
                      ),
                    ),
                    if (module.failed)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(strings.text('identity.notice.failed')),
                      ),
                    const SizedBox(height: 8),
                    StarBridgeActionButton(
                      controlKey: const ValueKey('handle-mismatch-recheck'),
                      kind: StarBridgeActionKind.quiet,
                      onActivate: current && !module.busy
                          ? (_) => unawaited(module.recheck())
                          : null,
                      child: Text(
                        strings.text(
                          module.busy
                              ? 'identity.notice.busy'
                              : 'identity.notice.retry',
                        ),
                      ),
                    ),
                  ],
                ),
                if (module.busy)
                  Positioned(
                    top: -8,
                    left: 0,
                    right: 0,
                    child: ExcludeSemantics(
                      child: SocialReadActivity(
                        key: ValueKey((
                          'handle-mismatch-activity',
                          _activity.revision,
                        )),
                        source: _activity.source,
                        opening: false,
                        label: strings.text('identity.notice.busy'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            StarBridgeActionButton(
              controlKey: const ValueKey('handle-mismatch-later'),
              kind: StarBridgeActionKind.quiet,
              onActivate: module.busy
                  ? null
                  : (source) => dismissStarBridgeDialog(
                      context,
                      source: source,
                      result: false,
                    ),
              child: Text(strings.text('identity.notice.later')),
            ),
            if (state == HandleCheckState.ready ||
                state == HandleCheckState.outcomeUnknown)
              StarBridgeActionButton(
                controlKey: const ValueKey('handle-mismatch-confirm'),
                kind: StarBridgeActionKind.primary,
                onActivate: current && module.canConfirm
                    ? (_) => unawaited(module.confirm())
                    : null,
                child: Text(strings.text('identity.notice.confirm')),
              ),
            StarBridgeActionButton(
              controlKey: const ValueKey('handle-mismatch-account'),
              kind: StarBridgeActionKind.primary,
              onActivate: current && !module.busy
                  ? (source) => dismissStarBridgeDialog(
                      context,
                      source: source,
                      result: true,
                    )
                  : null,
              child: Text(strings.text('identity.notice.open')),
            ),
          ],
        ),
      );
    },
  );
}
