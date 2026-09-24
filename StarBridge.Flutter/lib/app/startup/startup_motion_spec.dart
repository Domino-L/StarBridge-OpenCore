import 'dart:math';

enum StartupMotionDirection { soft, clear, technical, tension, spectacular }

/// Approved gallery timings, chosen once by the process-level startup session.
class StartupMotionSpec {
  const StartupMotionSpec(this.direction);

  final StartupMotionDirection direction;

  static StartupMotionSpec choose([Random? random]) => StartupMotionSpec(
    StartupMotionDirection.values[(random ?? Random()).nextInt(5)],
  );

  Duration get spinDuration => Duration(
    milliseconds: switch (direction) {
      StartupMotionDirection.soft => 1000,
      StartupMotionDirection.clear => 760,
      StartupMotionDirection.technical => 860,
      StartupMotionDirection.tension => 920,
      StartupMotionDirection.spectacular => 680,
    },
  );

  Duration get spinPause => Duration(
    milliseconds: switch (direction) {
      StartupMotionDirection.soft => 700,
      StartupMotionDirection.clear => 520,
      StartupMotionDirection.technical => 620,
      StartupMotionDirection.tension => 660,
      StartupMotionDirection.spectacular => 420,
    },
  );

  Duration get assemblyDuration => Duration(
    milliseconds: switch (direction) {
      StartupMotionDirection.soft => 420,
      StartupMotionDirection.clear => 300,
      StartupMotionDirection.technical => 440,
      StartupMotionDirection.tension ||
      StartupMotionDirection.spectacular => 500,
    },
  );

  Duration get handoffDuration => Duration(
    milliseconds: switch (direction) {
      StartupMotionDirection.soft => 180,
      StartupMotionDirection.clear => 150,
      StartupMotionDirection.technical => 160,
      StartupMotionDirection.tension => 170,
      StartupMotionDirection.spectacular => 190,
    },
  );
}
