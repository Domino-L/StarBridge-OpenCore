#ifndef RUNNER_MENU_TOOL_PAGE_INTENT_H_
#define RUNNER_MENU_TOOL_PAGE_INTENT_H_
#include "menu_exec_hangar_intent.h"

// One fixed client page (信息浮层 settings), named by the method itself. Same
// opening/ownership fence as the hangar destination, but no capability flag:
// the page always exists. No route, payload or window handle is accepted.
inline bool ValidMenuToolPageIntent(const flutter::EncodableMap& args,
    uint64_t opening, bool live, bool wanted, bool modal) {
  return ValidMenuExecHangarIntent(args, opening, true, live, wanted, modal);
}
#endif
