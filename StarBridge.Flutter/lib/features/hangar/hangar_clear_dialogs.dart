import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import 'hangar_reader_copy.dart';

// Wait for the exit animation too: a native child must not reappear while
// the dialog is still painted, including when its root Navigator differs.
Future<T?> _show<T>(
  BuildContext context,
  InteractionSource source,
  WidgetBuilder builder,
) async {
  StarBridgeDialogRoute<T>? route;
  final result = await showStarBridgeDialog<T>(
    context,
    source: source,
    builder: builder,
    onRouteCreated: (created) => route = created,
  );
  await route?.completed;
  return result;
}

Future<bool?> showHangarClearConfirmation(
  BuildContext context,
  InteractionSource source,
) {
  final copy = HangarReaderCopy(context);
  return _show<bool>(
    context,
    source,
    (context) => AlertDialog(
      title: Text(copy.clearData),
      content: Text(copy.clearConfirmation),
      actions: [
        StarBridgeActionButton(
          controlKey: const Key('hangar-clear-cancel'),
          onActivate: (source) =>
              dismissStarBridgeDialog(context, source: source, result: false),
          child: Text(copy.keepData),
        ),
        StarBridgeActionButton(
          controlKey: const Key('hangar-clear-confirm'),
          kind: StarBridgeActionKind.primary,
          onActivate: (source) =>
              dismissStarBridgeDialog(context, source: source, result: true),
          child: Text(copy.clearData),
        ),
      ],
    ),
  );
}

Future<void> showHangarClearResult(
  BuildContext context,
  InteractionSource source,
  String phase,
) async {
  final copy = HangarReaderCopy(context);
  await _show<void>(
    context,
    source,
    (context) => AlertDialog(
      title: Text(
        phase == 'cleared' ? copy.status(phase) : copy.clearFailedTitle,
      ),
      content: Text(
        phase == 'cleared' ? copy.clearSuccess : copy.status(phase),
      ),
      actions: [
        StarBridgeActionButton(
          controlKey: const Key('hangar-clear-result-ok'),
          kind: StarBridgeActionKind.primary,
          onActivate: (source) =>
              dismissStarBridgeDialog(context, source: source),
          child: Text(copy.acknowledge),
        ),
      ],
    ),
  );
}
