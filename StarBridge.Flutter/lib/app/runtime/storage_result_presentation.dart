import 'package:flutter/material.dart';

import '../../features/settings/data_location_copy.dart';
import '../../design_system/interaction/starbridge_timed_snack_bar.dart';

/// Presentation only: result acknowledgement/retry remain in the runtime.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason>?
showStorageMigrationResult(BuildContext context, String state) =>
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      starBridgeTimedSnackBar(
        content: Text(
          dataLocationCopy(
            context,
            state == 'migrated' ? 'migrationCompleted' : 'migrationFailed',
          ),
        ),
      ),
    );
