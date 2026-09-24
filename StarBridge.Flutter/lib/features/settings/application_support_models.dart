import 'package:flutter/foundation.dart';

enum ApplicationSupportCheckState { healthy, actionRequired, unavailable }

enum ApplicationSupportFailure {
  hostUnavailable,
  timeout,
  inspectionFailed,
  invalidResponse,
}

enum ApplicationSupportActionResult { completed, hostUnavailable, failed }

@immutable
class ApplicationSupportCheck {
  const ApplicationSupportCheck({required this.state, required this.detail});

  final ApplicationSupportCheckState state;
  final String detail;
}

@immutable
class ApplicationStartupCheck extends ApplicationSupportCheck {
  const ApplicationStartupCheck({
    required super.state,
    required super.detail,
    required this.registered,
    required this.targetExists,
    required this.targetsCurrentExecutable,
  });

  final bool registered;
  final bool? targetExists;
  final bool? targetsCurrentExecutable;
}

@immutable
class ApplicationInstallationCheck extends ApplicationSupportCheck {
  const ApplicationInstallationCheck({
    required super.state,
    required super.detail,
    required this.mode,
    required this.currentInstallations,
    required this.otherInstallations,
    required this.orphanedRegistrations,
    required this.scanWarnings,
  });

  final String mode;
  final int currentInstallations;
  final int otherInstallations;
  final int orphanedRegistrations;
  final int scanWarnings;
}

@immutable
class ApplicationSupportSnapshot {
  const ApplicationSupportSnapshot({
    required this.hasIssues,
    required this.hasUnavailableChecks,
    required this.dataDirectory,
    required this.gameLog,
    required this.startup,
    required this.installation,
    this.connection,
  });

  final bool hasIssues;
  final bool hasUnavailableChecks;
  final ApplicationSupportCheck dataDirectory;
  final ApplicationSupportCheck gameLog;
  final ApplicationStartupCheck startup;
  final ApplicationInstallationCheck installation;
  final ApplicationSupportCheck? connection;

  List<ApplicationSupportCheck> get checks => [
    dataDirectory,
    gameLog,
    startup,
    installation,
    ?connection,
  ];
}

@immutable
class ApplicationSupportProjection {
  const ApplicationSupportProjection._({
    required this.loading,
    this.snapshot,
    this.failure,
  });

  const ApplicationSupportProjection.loading() : this._(loading: true);

  const ApplicationSupportProjection.ready(ApplicationSupportSnapshot value)
    : this._(loading: false, snapshot: value);

  const ApplicationSupportProjection.failed(ApplicationSupportFailure value)
    : this._(loading: false, failure: value);

  final bool loading;
  final ApplicationSupportSnapshot? snapshot;
  final ApplicationSupportFailure? failure;
}

class ApplicationSupportException implements Exception {
  const ApplicationSupportException(this.failure, {this.retryable = false});

  final ApplicationSupportFailure failure;
  final bool retryable;
}
