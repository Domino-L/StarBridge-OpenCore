import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_dialog.dart';
import '../localization/app_strings.dart';
import 'menu_tool_page.dart';

/// Tells the user that what they just asked for is done in the client, inside
/// the page's panel, with a way there when the client has that page.
Future<void> showMenuClientOnlyNotice(
  BuildContext context, {
  String? clientPage,
}) {
  final opener = clientPage == null ? null : MenuToolPageScope.of(context);
  final strings = AppStrings.of(context);
  return showStarBridgeDialog<void>(
    context,
    builder: (dialog) => AlertDialog(
      key: const Key('menu-client-only'),
      title: Text(strings.text('menu.overlay.clientOnly.title')),
      content: Text(strings.text('menu.overlay.clientOnly.body')),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(),
          child: Text(strings.text('menu.overlay.clientOnly.close')),
        ),
        if (opener != null)
          FilledButton(
            key: const Key('menu-client-only-open'),
            onPressed: () {
              Navigator.of(dialog).pop();
              unawaited(opener.openClientPage(clientPage!));
            },
            child: Text(strings.text('menu.overlay.clientOnly.open')),
          ),
      ],
    ),
  );
}
