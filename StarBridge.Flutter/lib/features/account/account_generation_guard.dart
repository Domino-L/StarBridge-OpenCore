import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_dialog.dart';
import 'account_models.dart';

/// Shows a dialog that belongs to one account session. [generation] is taken
/// by the caller when it decides to show, never read later from [account], so
/// a session that changes even before the dialog's first frame cannot adopt
/// it. Once [account] signs out or moves to another generation, only this
/// dialog's own route is removed: never a route opened above it, and nothing
/// while it is already closing. The future then completes with null.
Future<T?> showAccountBoundDialog<T>(
  BuildContext context, {
  required ValueListenable<AccountProjection> account,
  required int generation,
  required WidgetBuilder builder,
  InteractionSource? source,
}) {
  StarBridgeDialogRoute<T>? route;
  bool lost() {
    final current = account.value;
    return !current.isSignedIn || current.generation != generation;
  }

  void check() {
    if (lost()) retireStarBridgeDialog(route);
  }

  account.addListener(check);
  final shown = showStarBridgeDialog<T>(
    context,
    source: source,
    builder: builder,
    onRouteCreated: (created) => route = created,
  );
  // Changed between the caller's decision and the push.
  check();
  return shown.whenComplete(() => account.removeListener(check));
}
