import 'package:flutter/foundation.dart';

import 'account_models.dart';

/// In-memory, account-generation-scoped edits. Leaving the page does not save
/// or discard them; only a confirmed profile snapshot establishes a baseline.
final class AccountPreferencesDraft extends ChangeNotifier {
  AccountPreferencesDraft(this._source) {
    _source.addListener(_sync);
    _sync();
  }

  final ValueListenable<AccountProjection> _source;
  int? _generation;
  String _baselineLocale = '', _baselineTimeZone = '';
  String locale = '', timeZone = '';
  bool get hasChanges =>
      locale != _baselineLocale || timeZone != _baselineTimeZone;

  void setLocale(String value) {
    if (!_source.value.canEditPreferences || locale == value) return;
    locale = value;
    notifyListeners();
  }

  void setTimeZone(String value) {
    if (!_source.value.canEditPreferences || timeZone == value) return;
    timeZone = value;
    notifyListeners();
  }

  void discard() {
    locale = _baselineLocale;
    timeZone = _baselineTimeZone;
    notifyListeners();
  }

  void _sync() {
    final projection = _source.value;
    if (!projection.isSignedIn) {
      _generation = null;
      _baselineLocale = _baselineTimeZone = locale = timeZone = '';
      notifyListeners();
      return;
    }
    final changedAccount = _generation != projection.generation;
    final dirty = hasChanges;
    _generation = projection.generation;
    // A missing profile during a same-account read is not an empty preference.
    if (projection.profile == null && !changedAccount) return;
    _baselineLocale = projection.profile?.locale ?? '';
    _baselineTimeZone = projection.profile?.timeZone ?? '';
    if (changedAccount || !dirty) {
      locale = _baselineLocale;
      timeZone = _baselineTimeZone;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _source.removeListener(_sync);
    super.dispose();
  }
}
