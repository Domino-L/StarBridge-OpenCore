import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'account_models.dart';
import 'account_port.dart';
import 'account_payload_decoder.dart';
import 'bridge_account_failure.dart';
import 'bridge_account_profile_read_failure.dart';

enum _Read { profile, directory, identity, compatibility }

/// One owner descriptor and a bounded work list. The Adapter remains the single
/// owner of its display snapshot; no completed account response is cached here.
final class AccountStagedRead {
  AccountStagedRead(this._session);
  final BridgeClientSession _session;
  BridgeAccountContext? _owner;
  int _generation = -1, _epoch = 0;
  final _pending = <_Read>[];
  final _retry = <_Read>{};
  final _failures = <_Read, AccountFailure>{};
  BridgeRequestOperation? _operation;
  bool _directoryAllowsWrite = false;
  DateTime? observedAtUtc;

  bool get supported =>
      _session.hostCapabilities.contains('profile.stagedRead');
  bool get hasPending => _pending.isNotEmpty;
  bool get shouldRetry => _retry.isNotEmpty;
  int get revision => _epoch;

  void cancel() {
    ++_epoch;
    final operation = _operation;
    _operation = null;
    if (operation != null) unawaited(operation.cancel());
  }

  void clear() {
    cancel();
    _owner = null;
    _pending.clear();
    _retry.clear();
    _failures.clear();
    _directoryAllowsWrite = false;
    observedAtUtc = null;
  }

  Future<AccountHostSnapshot> readCached(
    BridgeEnvelope account,
    AccountHostSnapshot? previous,
    AccountProfileReadSnapshot? retention,
  ) async {
    try {
      return await _readCached(account, previous, retention);
    } on Object catch (error) {
      if (error is BridgeStaleGenerationException ||
          account.sessionGeneration != _session.activeGeneration) {
        rethrow;
      }
      clear();
      final owner = account.accountContext!;
      throw AccountProfileSnapshotFailure(
        accountProfileReadFailureSnapshot(
          error: error,
          generation: account.sessionGeneration,
          route: AccountRoute(
            environment: owner.environment,
            authority: owner.authority,
            subject: owner.subject,
          ),
          previous: retention,
        ),
        error,
      );
    }
  }

  Future<AccountHostSnapshot> _readCached(
    BridgeEnvelope account,
    AccountHostSnapshot? previous,
    AccountProfileReadSnapshot? retention,
  ) async {
    clear();
    final owner = account.accountContext!;
    final epoch = _epoch;
    final response = await _session.request(
      'profile.readDisplayCache',
      payload: const {'schemaVersion': 1},
      accountContext: owner,
      timeout: const Duration(seconds: 5),
    );
    if (epoch != _epoch ||
        account.sessionGeneration != _session.activeGeneration) {
      throw BridgeStaleGenerationException(
        account.sessionGeneration,
        _session.activeGeneration,
      );
    }
    AccountPayloadDecoder.requireSchema(response.payload);
    final missing =
        response.payload['source'] == 'unavailable' &&
        response.payload['profile'] == null;
    final data = missing
        ? null
        : AccountPayloadDecoder.profile(response.payload);
    if (data != null && data.freshness != AccountProfileFreshness.cached) {
      throw const BridgeFormatException(
        'Local display must be an explicit cached profile.',
      );
    }
    _owner = owner;
    _generation = account.sessionGeneration;
    observedAtUtc = data?.cachedAt;
    _pending.addAll([
      _Read.profile,
      _Read.directory,
      _Read.identity,
      if (_session.hostCapabilities.contains('account.compatibility.read'))
        _Read.compatibility,
    ]);
    final sameLive =
        data != null &&
        previous != null &&
        retention != null &&
        previous.generation == _generation &&
        previous.route?.environment == owner.environment &&
        previous.route?.authority == owner.authority &&
        previous.route?.subject == owner.subject &&
        previous.profileFreshness == AccountProfileFreshness.live &&
        retention.observedAtUtc == data.cachedAt;
    // Keep an already displayed, confirmed live field set while revalidating
    // that exact persisted observation. A miss/retirement cannot revive it.
    if (sameLive) {
      return previous.copyWith(
        supportsPreferenceWrite: false,
        timeZoneOptions: const [],
      );
    }
    return AccountHostSnapshot(
      generation: _generation,
      sessionState: AccountSessionState.signedIn,
      route: AccountRoute(
        environment: owner.environment,
        authority: owner.authority,
        subject: owner.subject,
      ),
      profile: data?.profile.copyWith(
        displayName: AccountPayloadDecoder.displayCallSign(
          account.payload['displayName'],
        ),
        avatarImageData: account.payload['avatarImageData'] as String?,
      ),
      profileFreshness: data?.freshness ?? AccountProfileFreshness.unavailable,
      cachedAt: data?.cachedAt,
      identity: const AccountIdentityProjection.unavailable(),
      compatibility:
          _session.hostCapabilities.contains('account.compatibility.read')
          ? const AccountCompatibilityProjection.unavailable()
          : const AccountCompatibilityProjection.retired(),
      localeOptions: data?.localeOptions ?? const [],
      timeZoneOptions: const [],
      supportsCacheClear: _session.hostCapabilities.contains(
        'account.profileCache.clear',
      ),
    );
  }

  Future<AccountPortResult?> prepare(
    AccountHostSnapshot baseline,
    AccountProfileReadSnapshot? retention, {
    required bool retry,
  }) async {
    final owner = _owner;
    if (owner == null ||
        _generation != _session.activeGeneration ||
        baseline.generation != _generation ||
        baseline.route?.environment != owner.environment ||
        baseline.route?.authority != owner.authority ||
        baseline.route?.subject != owner.subject) {
      return null;
    }
    if (retry && _pending.isEmpty) {
      _pending.addAll(_retry);
      _retry.clear();
      if (_pending.contains(_Read.profile)) {
        _directoryAllowsWrite = false;
        if (!_pending.contains(_Read.directory)) _pending.add(_Read.directory);
      }
    }
    if (_pending.isEmpty || _operation != null) return null;
    final step = _pending.first, epoch = _epoch;
    final name = switch (step) {
      _Read.profile => 'profile.getDisplayData',
      _Read.directory => 'profile.getTimeZoneDirectory',
      _Read.identity => 'gameIdentity.getPolicy',
      _Read.compatibility => 'account.getCompatibilityState',
    };
    BridgeRequestOperation? operation;
    AccountHostSnapshot next;
    try {
      operation = _operation = _session.beginRequest(
        name,
        payload: const {'schemaVersion': 1},
        accountContext: owner,
        timeout: const Duration(seconds: 60),
      );
      final response = await operation.future;
      if (epoch != _epoch || _generation != _session.activeGeneration) {
        return null;
      }
      AccountPayloadDecoder.requireSchema(response.payload);
      _failures.remove(step);
      _retry.remove(step);
      switch (step) {
        case _Read.profile:
          final data = AccountPayloadDecoder.profile(response.payload);
          observedAtUtc =
              data.observedAt ?? data.cachedAt ?? DateTime.now().toUtc();
          if (data.freshness == AccountProfileFreshness.cached) {
            _retry.add(step);
            _failures[step] = const AccountFailure(
              code: 'profile.read_transient',
              messageKey: 'account.error.unavailable',
              retryable: true,
            );
          }
          next = baseline.copyWith(
            profile: data.profile.copyWith(
              displayName:
                  _session.hostCapabilities.contains('account.avatar.read')
                  ? baseline.profile?.displayName
                  : null,
              avatarImageData: baseline.profile?.avatarImageData,
            ),
            profileFreshness: data.freshness,
            cachedAt: data.cachedAt,
            clearCachedAt: data.cachedAt == null,
            localeOptions: data.localeOptions,
            supportsPreferenceWrite:
                _directoryAllowsWrite &&
                data.freshness == AccountProfileFreshness.live,
            supportsCacheClear: data.supportsCacheClear,
          );
        case _Read.directory:
          final directory = AccountPayloadDecoder.profileDirectory(
            response.payload,
          );
          _directoryAllowsWrite = directory.allowsWrite;
          next = baseline.copyWith(
            timeZoneOptions: directory.options,
            supportsPreferenceWrite:
                _directoryAllowsWrite &&
                baseline.profileFreshness == AccountProfileFreshness.live,
          );
        case _Read.identity:
          next = baseline.copyWith(
            identity: AccountPayloadDecoder.identity(response.payload),
          );
        case _Read.compatibility:
          next = baseline.copyWith(
            compatibility: AccountPayloadDecoder.compatibility(
              response.payload,
              canLinkExisting: _session.hostCapabilities.contains(
                'account.compatibility.linkExisting',
              ),
            ),
          );
      }
    } on Object catch (error) {
      if (epoch != _epoch || _generation != _session.activeGeneration) {
        return null;
      }
      if (error is BridgeCancelledException) {
        _pending.clear();
        _retry.clear();
        _failures.clear();
        return AccountPortResult(
          outcome: AccountActionOutcome.failed,
          snapshot: baseline.copyWith(supportsPreferenceWrite: false),
          failure: const AccountFailure(
            code: 'bridge.cancelled',
            messageKey: 'account.error.unavailable',
            retryable: false,
          ),
        );
      }
      final failure = mapAccountBridgeFailure(error);
      if (step == _Read.profile ||
          error is BridgeClientException &&
              const {
                'account.reauthorization_required',
                'bridge.account_context_required',
                'bridge.stale_generation',
              }.contains(error.code)) {
        next = accountProfileReadFailureSnapshot(
          error: error,
          generation: _generation,
          route: baseline.route!,
          previous: retention,
        );
        if (next.profile == null ||
            next.sessionState != AccountSessionState.signedIn) {
          _pending.clear();
          _retry.clear();
          _failures.clear();
          return AccountPortResult(
            outcome: AccountActionOutcome.failed,
            snapshot: next,
            failure: failure,
          );
        }
      } else {
        // An auxiliary failure cannot invalidate an independently confirmed profile.
        next = switch (step) {
          _Read.directory => baseline.copyWith(
            timeZoneOptions: const [],
            supportsPreferenceWrite: false,
          ),
          _Read.identity => baseline.copyWith(
            identity: const AccountIdentityProjection.unavailable(),
          ),
          _Read.compatibility => baseline.copyWith(
            compatibility: const AccountCompatibilityProjection.unavailable(),
          ),
          _ => baseline,
        };
      }
      _failures[step] = failure;
      if (failure.retryable) _retry.add(step);
    } finally {
      if (identical(_operation, operation)) _operation = null;
    }
    if (epoch != _epoch || _generation != _session.activeGeneration) {
      return null;
    }
    _pending.removeAt(0);
    final failure = _failures.values.firstOrNull;
    return AccountPortResult(
      outcome: failure == null
          ? AccountActionOutcome.completed
          : AccountActionOutcome.failed,
      snapshot: next,
      failure: failure,
    );
  }
}
