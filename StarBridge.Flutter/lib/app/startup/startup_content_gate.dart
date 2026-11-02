import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../features/account/account_models.dart';
import 'startup_session.dart';

/// Cached content can reveal the shell, but only real readiness completes boot.
class StartupContentGate extends StatefulWidget {
  const StartupContentGate({
    required this.session,
    required this.account,
    required this.preferencesConfirmed,
    required this.loading,
    required this.shell,
    super.key,
  });
  final StartupSession session;
  final ValueListenable<AccountProjection> account;
  final bool preferencesConfirmed;
  final WidgetBuilder loading, shell;

  @override
  State<StartupContentGate> createState() => _StartupContentGateState();
}

class _StartupContentGateState extends State<StartupContentGate> {
  bool _displayed = false;
  bool _enterScheduled = false;

  @override
  void didUpdateWidget(StartupContentGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session) ||
        !identical(oldWidget.account, widget.account)) {
      _displayed = false;
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<StartupPhase>(
    valueListenable: widget.session,
    builder: (context, phase, _) => ValueListenableBuilder<AccountProjection>(
      valueListenable: widget.account,
      builder: (context, account, _) {
        if (widget.preferencesConfirmed &&
            phase == StartupPhase.account &&
            account.isPreparingDisplay) {
          _displayed = true;
        }
        // The startup screen exists so the user enters a usable app (user,
        // 2026-10-20): a cached display is never shown while sign-in or the
        // first-glance reads are still pending. It is shown only when the
        // account cannot be confirmed, so earlier content is retained.
        final show =
            phase == StartupPhase.complete ||
            widget.preferencesConfirmed &&
                _displayed &&
                phase == StartupPhase.accountUnavailable;
        // Build the shell behind the startup screen as early as there is
        // something to read, so its own reads start without painting it.
        final build =
            show ||
            widget.preferencesConfirmed &&
                (phase == StartupPhase.content ||
                    phase == StartupPhase.ready ||
                    _displayed && phase == StartupPhase.account);
        if (show &&
            _displayed &&
            phase == StartupPhase.ready &&
            !_enterScheduled) {
          _enterScheduled = true;
          final session = widget.session;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _enterScheduled = false;
            if (mounted &&
                identical(session, widget.session) &&
                session.value == StartupPhase.ready) {
              session.enter();
            }
          });
        }
        // Keyed layers keep the same shell element across offstage content,
        // pending, real Ready and complete, and the startup animation intact.
        return Stack(
          fit: StackFit.expand,
          children: [
            if (build)
              KeyedSubtree(
                key: const ValueKey('startup-shell'),
                child: Offstage(
                  offstage: !show,
                  child: TickerMode(
                    enabled: show,
                    child: Builder(builder: widget.shell),
                  ),
                ),
              ),
            if (!show)
              KeyedSubtree(
                key: const ValueKey('startup-loading'),
                child: Builder(builder: widget.loading),
              ),
          ],
        );
      },
    ),
  );
}
