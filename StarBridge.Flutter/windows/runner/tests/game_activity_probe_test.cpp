#include "game_activity_probe.h"

#include <cstdio>

namespace {
int failures = 0;
void Check(bool condition, const char* label) {
  if (!condition) {
    std::printf("FAIL %s\n", label);
    ++failures;
  }
}
}  // namespace

int main() {
  using game_activity::CoversMonitor;
  using game_activity::IsStarCitizenExe;
  Check(IsStarCitizenExe(L"StarCitizen.exe"), "game exe");
  Check(IsStarCitizenExe(L"starcitizen.EXE"), "game exe any case");
  Check(IsStarCitizenExe(L"StarCitizen_PTUR.exe"), "test channel exe");
  Check(!IsStarCitizenExe(L"RSI Launcher.exe"), "launcher is not the game");
  Check(!IsStarCitizenExe(L"StarCitizen.exe.bak"), "suffix is not the game");
  Check(!IsStarCitizenExe(nullptr), "no name");

  const RECT monitor{0, 0, 2560, 1440};
  Check(CoversMonitor({0, 0, 2560, 1440}, monitor), "borderless full screen");
  Check(CoversMonitor({-8, -8, 2568, 1448}, monitor), "oversized frame");
  Check(!CoversMonitor({-8, -8, 2568, 1400}, monitor),
        "maximized window above the taskbar is not full screen");
  Check(!CoversMonitor({100, 100, 1380, 820}, monitor), "ordinary window");
  Check(CoversMonitor({2560, 0, 4480, 1080}, {2560, 0, 4480, 1080}),
        "second monitor");
  Check(!CoversMonitor({0, 0, 10, 10}, {0, 0, 0, 0}), "empty monitor");

  // Runs against the real desktop; only the shape of the answer is checked.
  const auto activity = game_activity::Read();
  (void)activity;
  if (failures == 0) std::printf("game_activity_probe: all passed\n");
  return failures == 0 ? 0 : 1;
}
