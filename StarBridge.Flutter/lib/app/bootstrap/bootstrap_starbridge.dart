import 'dart:io';

import 'package:flutter/widgets.dart';

import '../runtime/starbridge_runtime_host.dart';
import '../legal/starbridge_third_party_licenses.dart';

void bootstrapStarBridge() {
  WidgetsFlutterBinding.ensureInitialized();
  StarBridgeThirdPartyLicenses.registerAtStartup();
  runApp(StarBridgeRuntimeHost(environment: Platform.environment));
}
