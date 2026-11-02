import 'dart:math';

abstract interface class AchievementIdeasPort {
  bool get available;
  bool get canPickImage;
  Future<String?> pickImage({required int generation});
  Future<void> submit({
    required int generation,
    required String submissionId,
    required String name,
    required String condition,
    String? imageData,
  });
}

final class UnavailableAchievementIdeas implements AchievementIdeasPort {
  const UnavailableAchievementIdeas();
  @override
  bool get available => false;
  @override
  bool get canPickImage => false;
  @override
  Future<String?> pickImage({required int generation}) =>
      Future.error(const AchievementIdeaFailure('unavailable'));
  @override
  Future<void> submit({
    required int generation,
    required String submissionId,
    required String name,
    required String condition,
    String? imageData,
  }) => Future.error(const AchievementIdeaFailure('unavailable'));
}

final class AchievementIdeaFailure implements Exception {
  const AchievementIdeaFailure(this.code);
  final String code;
}

String achievementIdeaSubmissionId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
