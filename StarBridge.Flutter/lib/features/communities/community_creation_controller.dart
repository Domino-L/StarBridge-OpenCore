import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'community_creation_port.dart';

/// Owns one account-scoped creation draft. It does not own the shared port.
/// Unknown writes stay locked; a UI may refresh the directory, never auto-resubmit.
final class CommunityCreationController extends ChangeNotifier {
  CommunityCreationController(this.port, Stream<void> invalidations) {
    _subscription = invalidations.listen((_) => invalidate());
  }
  final CommunityCreationPort port;
  late final StreamSubscription<void> _subscription;
  CommunityCreationOptions? options;
  Map<String, Object?>? _draft;
  Map<String, Object?>? get draft => _draft;
  CommunityCreationOutcome? outcome;
  String? error;
  bool loading = false, submitting = false, invalidated = false;
  bool dirty = false;
  bool _closed = false;
  int _epoch = 0;
  bool get locked =>
      _closed ||
      invalidated ||
      loading ||
      submitting ||
      outcome?.status == 'unknown' ||
      outcome?.status == 'accepted';

  Future<void> load() async {
    if (locked || options != null) return;
    final epoch = ++_epoch;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final value = await port.creationOptions();
      if (!_current(epoch)) return;
      options = value;
      _draft = Map.unmodifiable({
        'schemaVersion': 1,
        'name': '',
        'code': '',
        'description': '',
        'joinPolicy': 'Open',
        'tagIds': const <String>[],
        'activeSystemIds': List<String>.unmodifiable([value.defaultSystem]),
        'activeFrom': value.defaultActiveFrom,
        'activeTo': value.defaultActiveTo,
        'timeZoneId': value.defaultTimeZoneId,
      });
    } catch (_) {
      if (_current(epoch)) error = 'optionsUnavailable';
    } finally {
      if (_current(epoch)) {
        loading = false;
        notifyListeners();
      }
    }
  }

  // Only form fields can be changed; callers cannot inject membership/authority.
  bool update(String field, Object? value) {
    if (locked ||
        _draft == null ||
        !const {
          'name',
          'code',
          'description',
          'joinPolicy',
          'tagIds',
          'activeSystemIds',
          'activeFrom',
          'activeTo',
          'timeZoneId',
          'logoImageData',
        }.contains(field)) {
      return false;
    }
    if (field == 'tagIds' || field == 'activeSystemIds') {
      if (value is! List<String>) return false;
      final allowed = field == 'tagIds'
          ? options!.tags.map((tag) => tag.id).toSet()
          : const {'stanton', 'pyro', 'nyx'};
      if (value.toSet().length != value.length ||
          value.any((item) => !allowed.contains(item)) ||
          value.length > (field == 'tagIds' ? options!.maxTags : 3)) {
        return false;
      }
      value = List<String>.unmodifiable(value);
    } else if (value is! String &&
        !(field == 'logoImageData' && value == null)) {
      return false;
    }
    if (_draft![field] == value) return true;
    _draft = Map.unmodifiable({..._draft!, field: value});
    dirty = true;
    error = null;
    outcome = null;
    notifyListeners();
    return true;
  }

  Future<void> submit() async {
    if (locked || _draft == null) return;
    final epoch = ++_epoch;
    // A new intent exists only on an explicit submit, never on a transport retry.
    final random = Random.secure();
    final requestId = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final payload = Map<String, Object?>.unmodifiable({
      ..._draft!,
      'name': (_draft!['name'] as String).trim(),
      'code': (_draft!['code'] as String).trim().toUpperCase(),
      'activeFrom': (_draft!['activeFrom'] as String).trim(),
      'activeTo': (_draft!['activeTo'] as String).trim(),
    });
    submitting = true;
    error = null;
    notifyListeners();
    try {
      final result = await port.createCommunity(requestId, payload);
      if (!_current(epoch)) return;
      // Port implementations must not turn a missing ownership readback into success.
      outcome = switch (result.status) {
        'accepted' when result.organization?.relationship == 'owner' => result,
        'rejected' => result,
        _ => const CommunityCreationOutcome('unknown', error: 'outcomeUnknown'),
      };
      error = outcome!.error;
      if (outcome!.status == 'accepted') dirty = false;
    } catch (_) {
      if (_current(epoch)) {
        outcome = const CommunityCreationOutcome(
          'unknown',
          error: 'outcomeUnknown',
        );
        error = 'outcomeUnknown';
      }
    } finally {
      if (_current(epoch)) {
        submitting = false;
        notifyListeners();
      }
    }
  }

  bool _current(int epoch) => !_closed && !invalidated && epoch == _epoch;
  void invalidate() {
    if (_closed || invalidated) return;
    _epoch++;
    invalidated = true;
    loading = submitting = dirty = false;
    options = null;
    _draft = null;
    outcome = null;
    error = 'identityUnavailable';
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    _epoch++;
    _draft = null;
    options = null;
    outcome = null;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
