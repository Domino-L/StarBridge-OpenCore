import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'onboarding_models.dart';
import 'onboarding_port.dart';

/// Device-local bridge contract. No invented account/legacy identity is sent.
/// Host advertises this capability only after all required owners are connected.
final class BridgeOnboardingAdapter implements OnboardingPort {
  BridgeOnboardingAdapter(this.session, {this.onGenerationAdvanced});
  static const capability = 'onboarding.firstUse.v1';
  final BridgeClientSession session;
  final Future<void> Function()? onGenerationAdvanced;
  String? _stateKey;
  OnboardingFacts? _facts;
  int _operation = 0;
  int? _generation;

  void _invalidate() {
    _operation++;
    _stateKey = null;
    _facts = null;
    _generation = null;
  }

  @override
  Stream<void> get invalidations => session.events
      .where(
        (event) => const {
          'onboarding.changed',
          'account.changed',
          'bootstrap.invalidated',
        }.contains(event.name),
      )
      .map((event) {
        _invalidate();
      });

  @override
  Future<OnboardingReply> read() async {
    if (!session.hostCapabilities.contains(capability)) {
      _invalidate();
      return const OnboardingReply(facts: OnboardingFacts());
    }
    return _request('onboarding.read', const {});
  }

  @override
  Future<OnboardingReply> execute(
    OnboardingAction action,
    OnboardingCheckpoint checkpoint,
  ) {
    final payload = {..._expected(checkpoint), 'action': action.name};
    final operation = _operation;
    return action == OnboardingAction.applyMode
        ? session.runConnectionModeChange(() {
            if (operation != _operation ||
                !session.hostCapabilities.contains(capability)) {
              throw StateError(
                'Onboarding observation changed while draining.',
              );
            }
            return _request('onboarding.execute', payload);
          })
        : _request('onboarding.execute', payload);
  }

  @override
  Future<OnboardingReply> save(OnboardingCheckpoint checkpoint) =>
      _request('onboarding.saveProgress', _expected(checkpoint));

  @override
  Future<OnboardingReply> finish(OnboardingCheckpoint checkpoint) =>
      _request('onboarding.finish', _expected(checkpoint));

  Map<String, Object?> _expected(OnboardingCheckpoint checkpoint) {
    if (!session.hostCapabilities.contains(capability) ||
        _stateKey == null ||
        _facts == null ||
        _generation != session.activeGeneration ||
        checkpoint.sourceKey != _facts!.sourceKey ||
        checkpoint.evidenceKey != _facts!.evidenceKey) {
      throw StateError('Onboarding observation is no longer current.');
    }
    return {
      'expectedStateKey': _stateKey,
      'checkpoint': checkpointWire(checkpoint),
    };
  }

  Future<OnboardingReply> _request(
    String name,
    Map<String, Object?> payload,
  ) async {
    final generation = session.activeGeneration;
    final operation = ++_operation;
    late final BridgeEnvelope response;
    try {
      response = await session.request(
        name,
        payload: {'schemaVersion': 1, ...payload},
      );
    } on Object {
      if (operation == _operation) _invalidate();
      rethrow;
    }
    if (operation != _operation ||
        !session.hostCapabilities.contains(capability) ||
        session.activeGeneration != generation ||
        response.sessionGeneration != generation ||
        response.status != 'ok' ||
        response.accountContext != null ||
        response.error != null) {
      if (operation == _operation) _invalidate();
      throw StateError('Onboarding request was not confirmed.');
    }
    try {
      final parsed = OnboardingWire.parse(response.payload);
      final control = response.payload['controlGeneration'] ?? generation;
      if (control is! int ||
          control < generation ||
          control > 9223372036854775807) {
        throw const FormatException('Invalid setup generation.');
      }
      if (control > generation) {
        session.advanceGeneration(control);
        await onGenerationAdvanced?.call();
        if (operation != _operation || session.activeGeneration != control) {
          throw StateError('Setup context changed after installation.');
        }
      }
      _stateKey = parsed.$1;
      _facts = parsed.$2.facts;
      _generation = control;
      return parsed.$2;
    } on Object {
      _invalidate();
      rethrow;
    }
  }

  static Map<String, Object?> checkpointWire(OnboardingCheckpoint checkpoint) =>
      {
        // The optional check is not a stored page: resuming opens the summary.
        'step': checkpoint.step == OnboardingStep.verify
            ? OnboardingStep.summary.name
            : checkpoint.step.name,
        'mode': checkpoint.mode?.name,
        'sourceKey': checkpoint.sourceKey,
        'evidenceKey': checkpoint.evidenceKey,
      };
}

/// Fail-closed decoder: omitted/unknown fields never become ready defaults.
abstract final class OnboardingWire {
  static (String, OnboardingReply) parse(Map<String, Object?> payload) {
    if (payload.containsKey('controlGeneration') &&
        (payload['controlGeneration'] is! int ||
            (payload['controlGeneration']! as int) < 0 ||
            (payload['controlGeneration']! as int) > 9223372036854775807)) {
      _bad();
    }
    _shape({...payload}..remove('controlGeneration'), const {
      'schemaVersion',
      'stateKey',
      'facts',
      'restored',
      'saved',
      'completed',
    });
    if (payload['schemaVersion'] is! int || payload['schemaVersion'] != 1) {
      _bad();
    }
    final state = _token(payload['stateKey']);
    if (state == null) _bad();
    final raw = _map(payload['facts']);
    _shape(raw, const {
      'eligibility',
      'available',
      'canSave',
      'sourceKey',
      'evidenceKey',
      'version',
      'logReady',
      'evidence',
      'origin',
      'handle',
      'observedAt',
      'scopeChecked',
      'requiresFreshEvidence',
      'localIdentityConfirmed',
      'localSettingsReady',
      'signedIn',
      'onlineIdentityMatched',
      'onlineChoicesReviewed',
      'activeMode',
      'publicationSuspended',
      'onlineSetupPending',
    });
    final facts = OnboardingFacts(
      eligibility: _enum(raw['eligibility'], OnboardingEligibility.values),
      available: _bool(raw, 'available'),
      canSave: _bool(raw, 'canSave'),
      sourceKey: _token(raw['sourceKey']),
      evidenceKey: _token(raw['evidenceKey']),
      version: _version(raw['version']),
      logReady: _bool(raw, 'logReady'),
      evidence: _enum(raw['evidence'], OnboardingEvidence.values),
      origin: raw['origin'] == null
          ? null
          : _enum(raw['origin'], OnboardingEvidenceOrigin.values),
      handle: _handle(raw['handle']),
      observedAt: _time(raw['observedAt']),
      scopeChecked: _bool(raw, 'scopeChecked'),
      requiresFreshEvidence: _bool(raw, 'requiresFreshEvidence'),
      localIdentityConfirmed: _bool(raw, 'localIdentityConfirmed'),
      localSettingsReady: _bool(raw, 'localSettingsReady'),
      signedIn: _bool(raw, 'signedIn'),
      onlineIdentityMatched: _bool(raw, 'onlineIdentityMatched'),
      onlineChoicesReviewed: _bool(raw, 'onlineChoicesReviewed'),
      activeMode: raw['activeMode'] == null
          ? null
          : _enum(raw['activeMode'], OnboardingMode.values),
      publicationSuspended: _bool(raw, 'publicationSuspended'),
      onlineSetupPending: _bool(raw, 'onlineSetupPending'),
    );
    if (facts.evidenceKey != null && facts.sourceKey == null ||
        facts.logReady && (facts.sourceKey == null || facts.version == null) ||
        facts.evidence == OnboardingEvidence.candidate && !facts.hasCandidate ||
        facts.evidence != OnboardingEvidence.candidate &&
            facts.handle != null ||
        facts.localIdentityConfirmed && !facts.hasCandidate ||
        facts.origin == OnboardingEvidenceOrigin.confirmedLocal &&
            facts.requiresFreshEvidence ||
        facts.onlineIdentityMatched && !facts.signedIn ||
        facts.onlineSetupPending &&
            (facts.activeMode != OnboardingMode.local ||
                !facts.publicationSuspended)) {
      _bad();
    }
    final completed = _checkpoint(payload['completed']);
    if (completed != null && completed.step != OnboardingStep.summary) _bad();
    return (
      state,
      OnboardingReply(
        facts: facts,
        restored: _checkpoint(payload['restored']),
        saved: _checkpoint(payload['saved']),
        completed: completed,
      ),
    );
  }

  static OnboardingCheckpoint? _checkpoint(Object? value) {
    if (value == null) return null;
    final raw = _map(value);
    _shape(raw, const {'step', 'mode', 'sourceKey', 'evidenceKey'});
    final step = _enum(raw['step'], OnboardingStep.values);
    final mode = raw['mode'] == null
        ? null
        : _enum(raw['mode'], OnboardingMode.values);
    final source = _token(raw['sourceKey']);
    final evidence = _token(raw['evidenceKey']);
    if (step.index > OnboardingStep.mode.index && mode == null ||
        step == OnboardingStep.online && mode != OnboardingMode.online ||
        evidence != null && source == null) {
      _bad();
    }
    return OnboardingCheckpoint(
      step: step,
      mode: mode,
      sourceKey: source,
      evidenceKey: evidence,
    );
  }

  static Map<String, Object?> _map(Object? value) =>
      value is Map<String, Object?> ? value : _bad();
  static Never _bad() =>
      throw const FormatException('Invalid first-use Host contract.');
  static void _shape(Map<String, Object?> value, Set<String> fields) {
    if (value.length != fields.length || !fields.every(value.containsKey)) {
      _bad();
    }
  }

  static bool _bool(Map<String, Object?> value, String key) =>
      value[key] is bool ? value[key] as bool : _bad();
  static T _enum<T extends Enum>(Object? value, List<T> values) {
    for (final item in values) {
      if (item.name == value) return item;
    }
    return _bad();
  }

  static String? _token(Object? value) {
    if (value == null) return null;
    if (value is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(value)) {
      _bad();
    }
    return value;
  }

  static String? _handle(Object? value) {
    if (value == null) return null;
    if (value is! String ||
        !RegExp(r'^[\p{L}\p{N}_.-]{2,64}$', unicode: true).hasMatch(value)) {
      _bad();
    }
    return value;
  }

  static String? _version(Object? value) {
    if (value == null) return null;
    if (value is! String || !RegExp(r'^[A-Za-z0-9_-]{1,32}$').hasMatch(value)) {
      _bad();
    }
    return value;
  }

  static DateTime? _time(Object? value) {
    if (value == null) return null;
    if (value is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$')
            .hasMatch(value)) {
      _bad();
    }
    final parsed = DateTime.tryParse(value);
    // DateTime.tryParse normalizes overflow dates; those are not valid evidence.
    if (parsed == null ||
        parsed.isBefore(DateTime.utc(1970)) ||
        parsed.toIso8601String().substring(0, 19) != value.substring(0, 19) ||
        parsed.isAfter(DateTime.now().toUtc())) {
      _bad();
    }
    return parsed;
  }
}
