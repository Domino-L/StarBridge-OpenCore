import '../../app/localization/app_strings.dart';
import 'gameplay_time_controller.dart';

String gameplayAccountTotal(AppStrings strings, GameplayTimeView state) =>
    switch ((state.accountTotalState, state.accountTotalSeconds)) {
      ('available', final int seconds) =>
        strings
            .text('gameplay.accountTotal')
            .replaceAll('{hours}', '${seconds ~/ 3600}') +
            (state.accountTotalStale || state.connectionUnavailable
                ? strings.text('gameplay.updatesLater') : ''),
      ('empty', _) => strings.text('gameplay.accountEmpty'),
      _ when state.scmOnly => strings.text('gameplay.accountScmOnly'),
      _ => strings.text('gameplay.accountUnavailable'),
    };

/// The owner's account total in minutes: the total the gameplay controller
/// read for this account, else the profile document's [documentMinutes].
int? ownerAccountMinutes(GameplayTimeView? state, int? documentMinutes) {
  final seconds = state?.accountTotalSeconds;
  return state?.accountTotalState == 'available' && seconds != null
      ? seconds ~/ 60
      : documentMinutes;
}

/// The hours the owner's header and side rail show: the account total
/// ([ownerAccountMinutes]), else this PC's total. A PC that only just started
/// recording must not replace the account's hours with its few (617 h shown
/// as 0 h). The playtime showcase labels both totals itself. Visitors keep the
/// profile document's value. A saved "show on profile" choice is ignored
/// (user 11-08: the profile's own visibility governs everything on it).
int? ownerGameplayHours(GameplayTimeView? state, int? documentMinutes) {
  final minutes = ownerAccountMinutes(state, documentMinutes);
  if (minutes != null) return minutes ~/ 60;
  final local = state?.visible == true ? state?.seconds : null;
  return local == null ? null : local ~/ 3600;
}
