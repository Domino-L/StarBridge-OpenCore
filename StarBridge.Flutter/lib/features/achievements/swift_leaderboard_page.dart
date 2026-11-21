import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_switch.dart';
import 'swift_leaderboard.dart';

String _failureKey(SwiftLeaderboardController c) => c.rateLimited
    ? 'rateLimited'
    : c.writeFailed
    ? 'saveFailed'
    : 'loadFailed';
String _s(BuildContext context, String key) =>
    AppStrings.of(context).text('leaderboard.$key');
String swiftTime(BuildContext context, int ms) => _s(context, 'time')
    .replaceAll('{hours}', '${ms ~/ 3600000}')
    .replaceAll('{minutes}', '${ms ~/ 60000 % 60}');
String _date(DateTime at) =>
    '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
Widget _action(BuildContext context, String key, VoidCallback? run) =>
    StarBridgeActionButton(
      onActivate: run == null ? null : (_) => run(),
      child: Text(_s(context, key)),
    );

Future<void> askSwiftConsent(
  BuildContext context,
  SwiftLeaderboardController c, {
  bool explicit = false,
}) async {
  if (!explicit && !c.claimPrompt()) return;
  final epoch = c.epoch;
  StarBridgeDialogRoute<void>? route;
  void guard() {
    if (c.epoch != epoch || c.supported == false) {
      retireStarBridgeDialog(route, includeClosing: true);
    }
  }

  c.addListener(guard);
  try {
    await showStarBridgeDialog<void>(
      context,
      barrierDismissible: false,
      onRouteCreated: (value) => route = value,
      builder: (context) => ListenableBuilder(
        listenable: c,
        builder: (context, _) => AlertDialog(
          title: Text(_s(context, 'title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_s(context, 'disclosure')),
                if (c.failed) Text(_s(context, _failureKey(c))),
              ],
            ),
          ),
          actions: [
            for (final optIn in [true, false])
              _action(
                context,
                optIn ? 'join' : 'later',
                c.busy
                    ? null
                    : () async {
                        final ok = await c.choose(optIn);
                        if (ok && context.mounted && c.epoch == epoch) {
                          dismissStarBridgeDialog(context);
                        }
                      },
              ),
          ],
        ),
      ),
    );
  } finally {
    c.removeListener(guard);
  }
}

class SwiftLeaderboardEntry extends StatefulWidget {
  const SwiftLeaderboardEntry({required this.controller, super.key});
  final SwiftLeaderboardController controller;
  @override
  State<SwiftLeaderboardEntry> createState() => _SwiftLeaderboardEntryState();
}

class _SwiftLeaderboardEntryState extends State<SwiftLeaderboardEntry> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.controller.load());
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      // Only a server that answered "supported" shows the entry. A failed
      // first read (old relay JAR, identity not yet confirmed, offline) stays
      // hidden instead of opening a board that can only say "failed".
      if (c.supported != true) return const SizedBox.shrink();
      return _action(context, 'open', () async {
        await c.load();
        if (!context.mounted || c.supported == false) return;
        await askSwiftConsent(context, c);
        if (!context.mounted) return;
        final epoch = c.epoch;
        StarBridgeDialogRoute<void>? route;
        void guard() {
          if (c.epoch != epoch || c.supported == false) {
            retireStarBridgeDialog(route, includeClosing: true);
          }
        }

        c.addListener(guard);
        try {
          await showStarBridgeDialog<void>(
            context,
            onRouteCreated: (value) => route = value,
            builder: (_) => SwiftLeaderboardPage(controller: c),
          );
        } finally {
          c.removeListener(guard);
        }
      });
    },
  );
}

class SwiftLeaderboardPage extends StatefulWidget {
  const SwiftLeaderboardPage({required this.controller, super.key});
  final SwiftLeaderboardController controller;
  @override
  State<SwiftLeaderboardPage> createState() => _SwiftLeaderboardPageState();
}

class _SwiftLeaderboardPageState extends State<SwiftLeaderboardPage>
    with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_read());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.closePage();
    super.dispose();
  }

  Future<void> _read() async {
    await widget.controller.load(includeBoard: true);
    if (mounted) await askSwiftConsent(context, widget.controller);
  }

  @override
  void initState() {
    super.initState();
    widget.controller.openPage();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_read());
    });
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final c = widget.controller, b = c.board;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _s(context, 'title'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(_s(context, 'basis')),
                Text(_s(context, 'rules')),
                const SizedBox(height: 16),
                if (c.failed) ...[
                  Text(_s(context, _failureKey(c))),
                  _action(context, 'retry', c.busy ? null : () => _read()),
                ],
                if (c.busy) Text(_s(context, 'loading')),
                if (b != null || c.bestMs != null) ...[
                  Text(
                    _s(context, 'me'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (b?.rank != null)
                    Text(
                      _s(context, 'rank').replaceAll('{rank}', '${b?.rank}'),
                    ),
                  Text(
                    c.bestMs == null
                        ? _s(context, 'noBest')
                        : swiftTime(context, c.bestMs!),
                  ),
                  if (c.consent?.optedIn != true)
                    Text(_s(context, 'notJoined')),
                ],
                if (c.consent != null)
                  _action(
                    context,
                    c.consent!.optedIn ? 'withdraw' : 'join',
                    c.busy
                        ? null
                        : () async {
                            if (c.consent!.optedIn) {
                              await c.choose(false);
                            } else {
                              await askSwiftConsent(context, c, explicit: true);
                            }
                            await c.load();
                          },
                  ),
                const Divider(height: 32),
                if (b != null && b.entries.isEmpty) Text(_s(context, 'empty')),
                if (b != null)
                  for (final e in b.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '${e.rank}  ${e.handle}',
                            key: ValueKey('swift-rank-${e.rank}'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Wrap(
                            spacing: 20,
                            runSpacing: 4,
                            children: [
                              Text(swiftTime(context, e.bestMs)),
                              Text(_date(e.achievedOn)),
                            ],
                          ),
                        ],
                      ),
                    ),
                _action(
                  context,
                  'close',
                  () => dismissStarBridgeDialog(context),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class SwiftLeaderboardSetting extends StatefulWidget {
  const SwiftLeaderboardSetting({required this.controller, super.key});
  final SwiftLeaderboardController controller;
  @override
  State<SwiftLeaderboardSetting> createState() =>
      _SwiftLeaderboardSettingState();
}

class _SwiftLeaderboardSettingState extends State<SwiftLeaderboardSetting> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.controller.load());
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      if (c.supported != true) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StarBridgeSwitch.tile(
              value: c.consent?.optedIn == true,
              label: _s(context, 'setting'),
              subtitle: _s(context, 'disclosure'),
              onChanged: c.busy
                  ? null
                  : (value) async {
                      if (value) {
                        await askSwiftConsent(context, c, explicit: true);
                      } else {
                        await c.choose(false);
                      }
                    },
            ),
            if (c.failed) Text(_s(context, _failureKey(c))),
          ],
        ),
      );
    },
  );
}

/// Watches the shared account-scoped state without activating a destination.
class SwiftAwardPrompt extends StatefulWidget {
  const SwiftAwardPrompt({
    required this.controller,
    required this.child,
    super.key,
  });
  final SwiftLeaderboardController? controller;
  final Widget child;
  @override
  State<SwiftAwardPrompt> createState() => _SwiftAwardPromptState();
}

class _SwiftAwardPromptState extends State<SwiftAwardPrompt> {
  bool scheduled = false;
  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_changed);
    _changed();
  }

  @override
  void didUpdateWidget(SwiftAwardPrompt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_changed);
      widget.controller?.addListener(_changed);
      _changed();
    }
  }

  void _changed() {
    if (!mounted || scheduled || widget.controller?.awardPending != true) {
      return;
    }
    scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      scheduled = false;
      if (mounted && widget.controller?.awardPending == true) {
        await askSwiftConsent(context, widget.controller!);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
