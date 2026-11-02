import '../../features/settings/application_support_module.dart';
import '../../features/settings/bridge_application_support.dart';
import '../../features/settings/host_unavailable_application_support.dart';
import '../../platform/bridge/bridge_client_session.dart';

/// Select the existing adapter from real Host capability; no fallback request
/// or additional diagnostics owner is created.
ApplicationSupportModule composeApplicationSupport(
  BridgeClientSession? session,
) => createApplicationSupportModule(
  session == null ||
          !session.hostCapabilities.contains('diagnostics.safeSummary')
      ? HostUnavailableApplicationSupport()
      : BridgeApplicationSupport(session),
);
