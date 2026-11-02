import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'achievement_ideas_port.dart';

final class BridgeAchievementIdeas implements AchievementIdeasPort {
  const BridgeAchievementIdeas(this.session);
  final BridgeClientSession session;
  @override
  bool get available =>
      session.hostCapabilities.contains('account.achievementIdeaSubmit');
  @override
  bool get canPickImage =>
      available && session.hostCapabilities.contains('achievementIdeas.images');

  Future<BridgeEnvelope> _request(
    String name,
    int generation,
    Map<String, Object?> body,
  ) async {
    if (!available || generation != session.activeGeneration) {
      throw const AchievementIdeaFailure('unavailable');
    }
    final current = await session.request(
      'account.getCurrent',
      payload: const {'schemaVersion': 1},
    );
    if (current.payload['state'] != 'signedIn' ||
        current.accountContext == null ||
        current.sessionGeneration != generation ||
        session.activeGeneration != generation) {
      throw const AchievementIdeaFailure('signIn');
    }
    BridgeEnvelope response;
    try {
      response = await session.request(
        name,
        payload: {'schemaVersion': 1, ...body},
        accountContext: current.accountContext,
        timeout: name == 'achievementIdeas.pickImage'
            ? const Duration(minutes: 5)
            : const Duration(seconds: 60),
      );
    } on BridgeClientException catch (error) {
      throw AchievementIdeaFailure(switch (error.code) {
        'ideas.sign_in' => 'signIn',
        'ideas.rate_limited' => 'rateLimited',
        'ideas.busy' => 'busy',
        'ideas.invalid_request' => 'invalidRequest',
        'ideas.restricted' => 'restricted',
        'ideas.unavailable' => 'unavailable',
        _ => 'unconfirmed',
      });
    }
    final returned = response.accountContext, owner = current.accountContext!;
    if (session.activeGeneration != generation ||
        response.sessionGeneration != generation ||
        returned == null ||
        returned.environment != owner.environment ||
        returned.authority != owner.authority ||
        returned.subject != owner.subject ||
        response.payload['schemaVersion'] != 1) {
      throw const AchievementIdeaFailure('unconfirmed');
    }
    return response;
  }

  @override
  Future<String?> pickImage({required int generation}) async {
    if (!canPickImage) throw const AchievementIdeaFailure('unavailable');
    final payload = (await _request(
      'achievementIdeas.pickImage',
      generation,
      const {},
    )).payload;
    if (payload['status'] == 'cancelled') return null;
    final data = payload['imageData'];
    if (payload['status'] != 'selected' ||
        data is! String ||
        data.length > 700000 ||
        !data.startsWith('data:image/png;base64,')) {
      throw const AchievementIdeaFailure('imageFailed');
    }
    return data;
  }

  @override
  Future<void> submit({
    required int generation,
    required String submissionId,
    required String name,
    required String condition,
    String? imageData,
  }) async {
    final payload = (await _request(
      'account.achievementIdeaSubmit',
      generation,
      {
        'submissionId': submissionId,
        'name': name,
        'condition': condition,
        'imageData': imageData,
      },
    )).payload;
    if (payload['sent'] != true || payload.length != 2) {
      throw const AchievementIdeaFailure('unconfirmed');
    }
  }
}
