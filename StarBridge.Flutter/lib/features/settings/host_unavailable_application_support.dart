import 'application_support_models.dart';
import 'application_support_port.dart';

final class HostUnavailableApplicationSupport
    implements ApplicationSupportPort {
  static const _failure = ApplicationSupportException(
    ApplicationSupportFailure.hostUnavailable,
    retryable: true,
  );

  @override
  Future<ApplicationSupportSnapshot> inspect() => Future.error(_failure);

  @override
  Future<void> openDataDirectory() => Future.error(_failure);

  @override
  Future<void> close() async {}
}
