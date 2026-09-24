import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app_composition.dart';
import 'session_warmup.dart';
import '../../features/communities/community_ships_copy.dart'
    show communityShipsCulture;

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
    final warmup = _warmup = SessionWarmup(
      account: app.account.projection,
      jobs: [
        ?app.features.all
            .where((feature) => feature.id == 'hangar')
            .firstOrNull
            ?.prefetch,
        app.friends.prefetch,
        app.communities.prefetch,
      ],
      workChanges: app.communities,
      continueWork: () =>
          app.communities.prepareNextWorkspace(communityShipsCulture(context)),
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
