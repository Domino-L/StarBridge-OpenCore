#ifndef RUNNER_MENU_OVERLAY_FOCUS_H_
#define RUNNER_MENU_OVERLAY_FOCUS_H_

#include <windows.h>

// Flutter can transfer focus to its own native view while preparing a frame.
// That handoff is not an external application switch. Never accept a different
// top-level window merely because it belongs to the same process.
inline bool IsMenuRevealForeground(HWND foreground, HWND target, HWND menu) {
  return foreground && (foreground == target ||
      (menu && (foreground == menu || IsChild(menu, foreground))));
}

#endif
