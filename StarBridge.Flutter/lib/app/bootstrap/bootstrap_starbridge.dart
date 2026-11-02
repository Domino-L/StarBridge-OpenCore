import 'dart:io';

import 'package:flutter/widgets.dart';

import '../runtime/starbridge_runtime_host.dart';
import '../legal/starbridge_third_party_licenses.dart';
import '../diagnostics/loading_diagnostics.dart';

void bootstrapStarBridge() {
  LoadingDiagnostics.run(Platform.environment, () {
    StarBridgeThirdPartyLicenses.registerAtStartup();
    runApp(StarBridgeRuntimeHost(environment: Platform.environment));
  });
}
