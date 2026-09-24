import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import 'application_support_module.dart';
import 'application_support_page.dart';
import 'settings_entry_catalog.dart';

Future<void> showApplicationSupportDialog(
  BuildContext context,
  ApplicationSupportModule module,
) => showDialog<void>(
  context: context,
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
              child: TextButton(
                key: const Key('application-support-close'),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(settingsEntryText(AppStrings.of(context), 'close')),
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);
