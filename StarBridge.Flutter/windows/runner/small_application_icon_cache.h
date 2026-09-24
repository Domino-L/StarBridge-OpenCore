#ifndef RUNNER_SMALL_APPLICATION_ICON_CACHE_H_
#define RUNNER_SMALL_APPLICATION_ICON_CACHE_H_

#include <array>
#include "small_application_icon.h"

// Reject pointer-sized/invalid message values before narrowing or multiplying.
inline bool IsSmallIconDpi(LPARAM dpi) noexcept { return dpi >= 48 && dpi <= 1024; }

inline UINT ResolveSmallIconDpi(LPARAM requested, UINT shell, UINT monitor,
                               UINT window) noexcept {
  if (IsSmallIconDpi(requested)) return static_cast<UINT>(requested);
  if (IsSmallIconDpi(shell)) return shell;
  if (IsSmallIconDpi(monitor)) return monitor;
  if (IsSmallIconDpi(window)) return window;
  return 96;
}

// Borrowed HICONs remain alive across subsequent DPI/theme requests. No eviction
// while a Shell consumer or WM_SETICON may still reference one. Bounded to two
// themes x 241 physical sizes, allocated lazily; all released with the window.
class SmallApplicationIconCache {
 public:
  SmallApplicationIconCache() = default;
  SmallApplicationIconCache(const SmallApplicationIconCache&) = delete;
  SmallApplicationIconCache& operator=(const SmallApplicationIconCache&) = delete;
  ~SmallApplicationIconCache() { Clear(); }

  HICON Get(UINT dpi, bool dark_foreground) noexcept {
    int pixels = MulDiv(24, static_cast<int>(ResolveSmallIconDpi(dpi, 0, 0, 0)), 96);
    if (pixels < 16) pixels = 16;
    if (pixels > 256) pixels = 256;
    HICON& icon = icons_[(pixels - 16) * 2 + (dark_foreground ? 1 : 0)];
    if (!icon) icon = LoadSmallApplicationIcon(pixels, dark_foreground);
    return icon;
  }

  void Clear() noexcept {
    for (auto& icon : icons_) {
      if (icon) DestroyIcon(icon);
      icon = nullptr;
    }
  }

 private:
  std::array<HICON, 482> icons_{};
};

#endif
