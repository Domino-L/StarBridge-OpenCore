import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'app_strings.dart';

/// The title the account card in Settings › Account & identity shows right
/// now, so prompts that send the user there name the card they will find.
/// The card and this scope read the same judgment: whether the relay offers
/// the old-account migration (plan item 9). Without the scope, or before the
/// first reading, the card is the existing compatibility card.
final class AccountCardTitle extends InheritedNotifier<ValueListenable<bool>> {
  const AccountCardTitle({
    required ValueListenable<bool> migrationOffered,
    required super.child,
    super.key,
  }) : super(notifier: migrationOffered);

  static const compatibilityKey = 'account.compatibility.title';
  static const migrationKey = 'account.migrate.title';

  /// The strings key of the card's current title.
  static String keyOf(BuildContext context) =>
      context
              .dependOnInheritedWidgetOfExactType<AccountCardTitle>()
              ?.notifier
              ?.value ==
          true
      ? migrationKey
      : compatibilityKey;
}

/// [text] with `{accountCard}` replaced by the card's current title.
String withAccountCardTitle(BuildContext context, String text) {
  if (!text.contains('{accountCard}')) return text;
  return text.replaceAll(
    '{accountCard}',
    AppStrings.of(context).text(AccountCardTitle.keyOf(context)),
  );
}
