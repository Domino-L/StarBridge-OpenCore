#include "manual_status_commands.h"
#include <cstdio>
#include <initializer_list>
int main() {
  int failed = 0;
  auto check = [&failed](bool good, const char* name) {
    std::printf("%s|%s\n", good ? "PASS" : "FAIL", name);
    if (!good) ++failed;
  };
  check(IsMenuFriendAction("offlineMode"), "friend forwards exact mode intent");
  check(IsTrayPrimaryAction("offlineMode"), "tray forwards exact mode intent");
  check(IsMenuFriendAction("resumeOnline"), "friend forwards exact restoration intent");
  check(IsTrayPrimaryAction("resumeOnline"), "tray forwards exact restoration intent");
  check(IsMenuFriendAction("presence") && IsTrayPrimaryAction("presence"), "original presence route retained");
  for (const char* bad : {"offline", "logout", "offlineMode.extra", "resumeOnline.extra", "onboarding.mode.offline", "presence.offline", ""}) {
    check(!IsMenuFriendAction(bad) && !IsTrayPrimaryAction(bad), "unknown transport action rejected");
  }
  return failed ? 1 : 0;
}
