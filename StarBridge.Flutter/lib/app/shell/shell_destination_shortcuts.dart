import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../feature_registry.dart';
import '../routing/open_destination_intent.dart';

/// Keyboard and intent bindings share the shell's guarded selection commands.
/// Search runs only after selection succeeds; a leave veto keeps its draft.
Widget shellDestinationShortcuts({
  required BuildContext context,
  required FeatureRegistry features,
  required Future<bool> Function(FeatureDescriptor) selectForSearch,
  required Future<void> Function(String) openDestination,
  required Widget child,
}) => CallbackShortcuts(
  bindings: {
    const SingleActivator(LogicalKeyboardKey.keyK, control: true): () async {
      if (ModalRoute.of(context)?.isCurrent == false) return;
      final destination = features.byRoute('/marketplace');
      final selected = await selectForSearch(destination);
      if (context.mounted && selected) {
        await (destination.onSearchShortcut ?? destination.onPrimaryNavigation)
            ?.call();
      }
    },
  },
  child: Actions(
    actions: {
      OpenDestinationIntent: CallbackAction<OpenDestinationIntent>(
        onInvoke: (intent) {
          unawaited(openDestination(intent.route));
          return null;
        },
      ),
    },
    child: child,
  ),
);
