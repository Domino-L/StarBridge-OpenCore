import 'application_support_models.dart';

abstract interface class ApplicationSupportPort {
  Future<ApplicationSupportSnapshot> inspect();

  Future<void> openDataDirectory();

  Future<void> close();
}
