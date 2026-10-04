import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../direct_messages/communication_time_formatter.dart';

/// Room lifecycle events are notices, never people with an avatar or bubble.
class RoomSystemMessage extends StatelessWidget {
  const RoomSystemMessage({super.key, required this.text, required this.time});
  final String text;
  final DateTime time;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: Text(
      '$text · ${communicationTime(time, AppStrings.of(context).locale)}',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall,
    ),
  );
}
