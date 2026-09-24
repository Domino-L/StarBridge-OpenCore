import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/application_support_models.dart';
import 'package:starbridge_flutter/features/settings/application_support_module.dart';
import 'package:starbridge_flutter/features/settings/application_support_port.dart';
import 'package:starbridge_flutter/features/settings/host_unavailable_application_support.dart';

void main() {
  test('module publishes a confirmed support snapshot', () async {
    final port = _ApplicationSupportPort();
    final module = createApplicationSupportModule(port);
    addTearDown(module.dispose);

    await module.initialize();

    expect(module.projection.value.loading, isFalse);
    expect(module.projection.value.snapshot, same(_healthySnapshot));
    expect(port.inspectCount, 1);
  });

  test('refresh requests are coalesced while a check is running', () async {
    final first = Completer<ApplicationSupportSnapshot>();
    final second = Completer<ApplicationSupportSnapshot>();
    final port = _ApplicationSupportPort(
      responses: [first.future, second.future],
    );
    final module = createApplicationSupportModule(port);
    addTearDown(module.dispose);

    final initialization = module.initialize();
    await Future<void>.delayed(Duration.zero);
    final refreshA = module.refresh();
    final refreshB = module.refresh();
    expect(port.inspectCount, 1);

    first.complete(_healthySnapshot);
    await Future.wait([refreshA, refreshB]);
    await Future<void>.delayed(Duration.zero);
    expect(port.inspectCount, 2);

    second.complete(_healthySnapshot);
    await initialization;
    expect(port.inspectCount, 2);
  });

  test('module maps a host failure without inventing a snapshot', () async {
    final port = _ApplicationSupportPort(
      failure: const ApplicationSupportException(
        ApplicationSupportFailure.hostUnavailable,
        retryable: true,
      ),
    );
    final module = createApplicationSupportModule(port);
    addTearDown(module.dispose);

    await module.initialize();

    expect(module.projection.value.snapshot, isNull);
    expect(
      module.projection.value.failure,
      ApplicationSupportFailure.hostUnavailable,
    );
  });

  test('disconnected product adapter stays explicit and retryable', () async {
    final module = createApplicationSupportModule(
      HostUnavailableApplicationSupport(),
    );
    addTearDown(module.dispose);

    await module.initialize();

    expect(
      module.projection.value.failure,
      ApplicationSupportFailure.hostUnavailable,
    );
    expect(module.projection.value.snapshot, isNull);
    expect(
      await module.openDataDirectory(),
      ApplicationSupportActionResult.hostUnavailable,
    );
  });

  test(
    'module exposes the owned directory action without a path parameter',
    () async {
      final port = _ApplicationSupportPort();
      final module = createApplicationSupportModule(port);
      addTearDown(module.dispose);

      final result = await module.openDataDirectory();

      expect(result, ApplicationSupportActionResult.completed);
      expect(port.openCount, 1);
    },
  );
}

final class _ApplicationSupportPort implements ApplicationSupportPort {
  _ApplicationSupportPort({this.responses = const [], this.failure});

  final List<Future<ApplicationSupportSnapshot>> responses;
  final ApplicationSupportException? failure;
  int inspectCount = 0;
  int openCount = 0;

  @override
  Future<ApplicationSupportSnapshot> inspect() {
    final index = inspectCount++;
    final selectedFailure = failure;
    if (selectedFailure != null) {
      return Future.error(selectedFailure);
    }
    if (responses.isNotEmpty) return responses[index];
    return Future.value(_healthySnapshot);
  }

  @override
  Future<void> openDataDirectory() async {
    final selectedFailure = failure;
    if (selectedFailure != null) throw selectedFailure;
    openCount++;
  }

  @override
  Future<void> close() async {}
}

const _healthySnapshot = ApplicationSupportSnapshot(
  hasIssues: false,
  hasUnavailableChecks: false,
  dataDirectory: ApplicationSupportCheck(
    state: ApplicationSupportCheckState.healthy,
    detail: 'writable',
  ),
  gameLog: ApplicationSupportCheck(
    state: ApplicationSupportCheckState.healthy,
    detail: 'readable',
  ),
  startup: ApplicationStartupCheck(
    state: ApplicationSupportCheckState.healthy,
    detail: 'notEnabled',
    registered: false,
    targetExists: null,
    targetsCurrentExecutable: null,
  ),
  installation: ApplicationInstallationCheck(
    state: ApplicationSupportCheckState.healthy,
    detail: 'portable',
    mode: 'portable',
    currentInstallations: 0,
    otherInstallations: 0,
    orphanedRegistrations: 0,
    scanWarnings: 0,
  ),
);
