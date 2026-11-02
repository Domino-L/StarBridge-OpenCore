import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import 'application_support_module.dart';
import 'application_support_page.dart';
import 'settings_entry_catalog.dart';

Future<void> showApplicationSupportDialog(
  BuildContext context,
  ApplicationSupportModule module,
) => showStarBridgeDialog<void>(
  context,
  builder: (context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    child: SizedBox(
      width: 780,
      height: MediaQuery.sizeOf(context).height * .85,
      child: Column(
        children: [
          Expanded(child: ApplicationSupportPage(module: module)),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: StarBridgeActionButton(
                kind: StarBridgeActionKind.quiet,
                controlKey: const Key('application-support-close'),
                onActivate: (source) =>
                    dismissStarBridgeDialog(context, source: source),
                child: Text(settingsEntryText(AppStrings.of(context), 'close')),
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);
