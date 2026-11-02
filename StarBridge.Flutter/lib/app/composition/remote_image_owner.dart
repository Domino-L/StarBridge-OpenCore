import 'package:flutter/foundation.dart';

import '../../features/account/account_models.dart';
import '../../shared/remote_image_loader.dart';

/// Cache lifetime follows the original account projection. Offline transitions
/// retain display bytes; an online owner change clears all borrowed windows.
/// This binding grants no profile access and performs no account mutation.
final class RemoteImageOwner {
  RemoteImageOwner(this.account, this.loader) {
    account.addListener(_changed);
    loader.addListener(_changed);
    _changed();
  }
  final ValueListenable<AccountProjection> account;
  final RemoteImageLoader loader;
  Object? _owner;
  void _changed() {
    if (!loader.online) return;
    final current = account.value;
    final owner = (
      current.generation,
      current.isSignedIn || current.isLegacyAccount,
    );
    if (_owner != owner) {
      _owner = owner;
      loader.clear();
    }
  }

  void dispose() {
    account.removeListener(_changed);
    loader.removeListener(_changed);
  }
}
