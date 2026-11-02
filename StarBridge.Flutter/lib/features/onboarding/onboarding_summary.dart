import 'app_behavior_choice_controller.dart';
import 'device_review_controller.dart';
import 'device_review_port.dart';
import 'local_history_controller.dart';
import 'local_history_port.dart';
import 'local_statistics_controller.dart';
import 'local_statistics_port.dart';
import 'onboarding_models.dart';
import 'online_review_controller.dart';
import 'recognition_check_controller.dart';

/// The four outcomes the finish page may claim. Each is derived from a Host
/// observation; pressing "Next" on a step never counts as saved.
enum SummaryStatus { saved, skipped, incomplete, failed }

enum SummaryItem {
  mode,
  log,
  identity,
  onlineIdentity,
  appBehavior,
  device,
  recording,
  history,
  onlineChoices,
  recognition,
}

final class SummaryEntry {
  const SummaryEntry(this.item, this.status, this.detail);
  final SummaryItem item;
  final SummaryStatus status;

  /// Copy key for the specific reason, e.g. `summary.detail.recording.declined`.
  final String detail;
}

List<SummaryEntry> buildOnboardingSummary({
  required OnboardingView view,
  AppBehaviorChoiceView? appBehavior,
  DeviceReviewView? device,
  LocalStatisticsView? statistics,
  LocalHistoryView? history,
  OnlineReviewView? online,
  RecognitionCheckView? recognition,
}) {
  final f = view.facts;
  final onlineMode = view.mode == OnboardingMode.online;
  SummaryEntry entry(SummaryItem item, SummaryStatus status, String detail) =>
      SummaryEntry(item, status, 'summary.detail.${item.name}.$detail');

  final recording = statistics == null
      ? entry(SummaryItem.recording, SummaryStatus.incomplete, 'unavailable')
      : statistics.error ||
            statistics.snapshot.state == LocalStatisticsState.retryRequired
      ? entry(SummaryItem.recording, SummaryStatus.failed, 'failed')
      : statistics.snapshot.choiceSaved
      ? entry(
          SummaryItem.recording,
          SummaryStatus.saved,
          statistics.snapshot.consent.name,
        )
      : entry(SummaryItem.recording, SummaryStatus.incomplete, 'pending');

  final SummaryEntry historyEntry;
  if (onlineMode) {
    // The online account keeps its own statistics; import there after setup.
    historyEntry = entry(
      SummaryItem.history,
      SummaryStatus.incomplete,
      'online',
    );
  } else if (history == null) {
    historyEntry = entry(
      SummaryItem.history,
      SummaryStatus.incomplete,
      'unavailable',
    );
  } else {
    historyEntry = switch (history.outcome) {
      LocalHistoryOutcome.saved => entry(
        SummaryItem.history,
        SummaryStatus.saved,
        'imported',
      ),
      LocalHistoryOutcome.failed => entry(
        SummaryItem.history,
        SummaryStatus.failed,
        'failed',
      ),
      LocalHistoryOutcome.skipped => entry(
        SummaryItem.history,
        SummaryStatus.skipped,
        'skipped',
      ),
      LocalHistoryOutcome.incomplete => entry(
        SummaryItem.history,
        SummaryStatus.incomplete,
        history.lastResult == LocalHistoryState.empty
            ? 'empty'
            : history.snapshot.state == LocalHistoryState.recordingRequired
            ? 'recordingRequired'
            : 'pending',
      ),
    };
  }

  return [
    view.modeApplied
        ? entry(SummaryItem.mode, SummaryStatus.saved, view.mode!.name)
        : entry(SummaryItem.mode, SummaryStatus.incomplete, 'pending'),
    f.available && f.logReady
        ? entry(SummaryItem.log, SummaryStatus.saved, 'ready')
        : entry(SummaryItem.log, SummaryStatus.incomplete, 'pending'),
    view.identityReady
        ? entry(SummaryItem.identity, SummaryStatus.saved, 'confirmed')
        : f.evidence == OnboardingEvidence.failed
        ? entry(SummaryItem.identity, SummaryStatus.failed, 'failed')
        : entry(SummaryItem.identity, SummaryStatus.incomplete, 'pending'),
    if (onlineMode)
      view.onlineIdentityReady
          ? entry(SummaryItem.onlineIdentity, SummaryStatus.saved, 'matched')
          : online?.error == true
          ? entry(SummaryItem.onlineIdentity, SummaryStatus.failed, 'failed')
          : entry(
              SummaryItem.onlineIdentity,
              SummaryStatus.incomplete,
              'pending',
            ),
    if (appBehavior != null)
      appBehavior.saved
          ? entry(
              SummaryItem.appBehavior,
              SummaryStatus.saved,
              '${appBehavior.savedLaunchAtStartup! ? 'auto' : 'manual'}'
              '${appBehavior.savedKeepInTray! ? 'Tray' : 'Exit'}',
            )
          : appBehavior.failed
          ? entry(SummaryItem.appBehavior, SummaryStatus.failed, 'failed')
          : entry(SummaryItem.appBehavior, SummaryStatus.incomplete, 'pending'),
    device == null
        ? f.localSettingsReady
              ? entry(SummaryItem.device, SummaryStatus.saved, 'reviewed')
              : entry(SummaryItem.device, SummaryStatus.incomplete, 'pending')
        : device.error
        ? entry(SummaryItem.device, SummaryStatus.failed, 'failed')
        : device.snapshot.state == DeviceReviewState.reviewed
        ? entry(SummaryItem.device, SummaryStatus.saved, 'reviewed')
        : entry(SummaryItem.device, SummaryStatus.incomplete, 'pending'),
    recording,
    historyEntry,
    if (onlineMode)
      f.onlineChoicesReviewed
          ? entry(SummaryItem.onlineChoices, SummaryStatus.saved, 'reviewed')
          : entry(
              SummaryItem.onlineChoices,
              SummaryStatus.incomplete,
              'pending',
            ),
    // Optional: only an observed ready read is a pass; otherwise an honest skip.
    switch (recognition?.outcome) {
      RecognitionCheckOutcome.passed => entry(
        SummaryItem.recognition,
        SummaryStatus.saved,
        'passed',
      ),
      RecognitionCheckOutcome.unavailable || null => entry(
        SummaryItem.recognition,
        SummaryStatus.skipped,
        'unavailable',
      ),
      RecognitionCheckOutcome.skipped => entry(
        SummaryItem.recognition,
        SummaryStatus.skipped,
        'skipped',
      ),
    },
  ];
}
