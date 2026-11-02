#ifndef STARBRIDGE_MANUAL_STATUS_COMMANDS_H_
#define STARBRIDGE_MANUAL_STATUS_COMMANDS_H_
#include <string_view>

// These gates only forward bounded UI intent to the primary owner. They never
// accept a remote presence value named offline or perform a mode transition.
inline bool IsMenuFriendAction(std::string_view action) {
  return action == "prepare" || action == "confirm" || action == "dismiss" ||
      action == "refresh" || action == "section" || action == "search" ||
      action == "presence" || action == "offlineMode" || action == "resumeOnline";
}
inline bool IsTrayPrimaryAction(std::string_view action) {
  return action == "overlaySettings" || action == "toggleOverlay" ||
      action == "presence" || action == "offlineMode" || action == "resumeOnline";
}
#endif
