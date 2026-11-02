import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app_composition.dart';
import 'session_warmup.dart';
import '../../features/account/account_read_preparation.dart';
import '../../features/communities/community_ships_copy.dart'
    show communityShipsCulture;

/// Feature prefetches queued after the communities job, in this order. The
/// marketplace one reads the sidebar attention badge once instead of on a fixed
/// post-login timer (2026-10-21); a feature without a prefetch is skipped.
const sessionWarmupFeatureIds = ['marketplace', 'achievements', 'party-rooms'];

class SessionWarmupListener extends StatefulWidget {
  const SessionWarmupListener({
    required this.composition,
    required this.child,
    super.key,
  });
  final AppComposition composition;
  final Widget child;
  @override
  State<SessionWarmupListener> createState() => _SessionWarmupListenerState();
}

class _SessionWarmupListenerState extends State<SessionWarmupListener>
    with WidgetsBindingObserver {
  late SessionWarmup _warmup;

  void _bind() {
    final app = widget.composition;
    final preparation =
        app.account is AccountReadPreparation &&
            (app.account as AccountReadPreparation).supportsPreparedReads
        ? app.account as AccountReadPreparation
        : null;
    final warmup = _warmup = SessionWarmup(
      account: app.account.projection,
      jobs: [
        if (preparation != null)
          () async {
            await preparation.prepareNextRead();
          },
        ?app.features.all
            .where((feature) => feature.id == 'hangar')
            .firstOrNull
            ?.prefetch,
        app.friends.prefetch,
        app.communities.prefetch,
        // Frequently opened destinations whose first visit otherwise waits on
        // a full read (device traces: achievements 7 s median). Same bounded
        // one-job-at-a-time queue; interaction still defers it.
        for (final id in sessionWarmupFeatureIds)
          ?app.features.all
              .where((feature) => feature.id == id)
              .firstOrNull
              ?.prefetch,
      ],
      workChanges: preparation == null
          ? app.communities
          : Listenable.merge([app.communities, app.account.projection]),
      cancelWork: preparation?.cancelReadPreparation,
      continueWork: () async {
        if (!mounted) return false;
        final culture = communityShipsCulture(context);
        if (preparation != null && await preparation.prepareNextRead()) {
          return true;
        }
        if (!mounted) return false;
        return app.communities.prepareNextWorkspace(culture);
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(warmup, _warmup)) return;
      final state = WidgetsBinding.instance.lifecycleState;
      warmup.setForeground(state == null || state == AppLifecycleState.resumed);
      warmup.start();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_key);
    _bind();
  }

  bool _key(KeyEvent event) {
    if (!event.synthesized) _warmup.deferForInteraction();
    return false;
  }

  @override
  void didUpdateWidget(SessionWarmupListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.composition != widget.composition) {
      _warmup.dispose();
      _bind();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _warmup.setForeground(state == AppLifecycleState.resumed);

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_key);
    WidgetsBinding.instance.removeObserver(this);
    _warmup.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _warmup.deferForInteraction(),
    onPointerSignal: (_) => _warmup.deferForInteraction(),
    child: widget.child,
  );
}
