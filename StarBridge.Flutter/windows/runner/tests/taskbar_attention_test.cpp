#include "taskbar_attention.h"
#include <vector>
#include <stdexcept>
#include <iostream>
void Check(bool value, const char* reason = "Taskbar attention regression") {
  if (!value) throw std::runtime_error(reason);
}
void CheckUnreadPixels() {
  HICON icon = taskbar_attention_detail::MakeUnreadIcon();
  Check(icon != nullptr);
  ICONINFO info{};
  Check(GetIconInfo(icon, &info) != FALSE);
  BITMAP bitmap{};
  Check(GetObjectW(info.hbmColor, sizeof(bitmap), &bitmap) == sizeof(bitmap));
  Check(bitmap.bmWidth == 16 && bitmap.bmHeight == 16 && bitmap.bmBitsPixel == 32);
  DWORD pixels[16 * 16]{};
  BITMAPINFO header{};
  header.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  header.bmiHeader.biWidth = 16; header.bmiHeader.biHeight = -16;
  header.bmiHeader.biPlanes = 1; header.bmiHeader.biBitCount = 32;
  header.bmiHeader.biCompression = BI_RGB;
  HDC dc = GetDC(nullptr);
  const int rows = GetDIBits(dc, info.hbmColor, 0, 16, pixels, &header, DIB_RGB_COLORS);
  ReleaseDC(nullptr, dc);
  DeleteObject(info.hbmColor); DeleteObject(info.hbmMask); DestroyIcon(icon);
  Check(rows == 16);
  int min_x = 16, min_y = 16, max_x = -1, max_y = -1, coverage = 0;
  bool opaque_red = false;
  for (int y = 0; y < 16; ++y) for (int x = 0; x < 16; ++x) {
    const DWORD pixel = pixels[y * 16 + x], alpha = pixel >> 24;
    // Premultiplied pure red, including antialiased edge samples. No white
    // outline, dark border, shadow or hidden RGB in transparent pixels.
    Check((pixel & 0xffff) == 0 && ((pixel >> 16) & 0xff) == alpha,
        "Unread dot must be pure red without a border or shadow");
    Check(pixel == pixels[y * 16 + (15 - x)] && pixel == pixels[(15 - y) * 16 + x]);
    if (!alpha) continue;
    if (x < min_x) min_x = x; if (x > max_x) max_x = x;
    if (y < min_y) min_y = y; if (y > max_y) max_y = y;
    coverage += static_cast<int>(alpha);
    opaque_red = opaque_red || pixel == 0xffff0000;
  }
  Check(min_x == 5 && max_x == 10 && min_y == 5 && max_y == 10,
      "Unread dot must occupy a centered six-pixel diameter");
  Check(opaque_red && coverage > 24 * 255 && coverage < 30 * 255);
}
int RunChecks() {
  CheckUnreadPixels();
  using Flash = TaskbarAttentionState::Flash;
  std::vector<bool> marks;
  std::vector<Flash> flashes;
  TaskbarAttentionState state([&](bool value) { marks.push_back(value); },
      [&](Flash value) { flashes.push_back(value); });
  state.Set(true, false, true);
  Check(marks.size() == 1 && marks.back() && flashes.back() == Flash::continuous);
  for (int i = 0; i < 100; ++i) state.Set(true, false, true);
  Check(marks.size() == 1 && flashes.size() == 1); // Burst/timer does not restart.
  state.Set(true, false, false);
  Check(marks.size() == 1 && flashes.back() == Flash::stop); // Focus keeps badge.
  state.Set(true, false, true);
  Check(marks.size() == 1 && flashes.back() == Flash::continuous); // Still unread.
  state.Set(true, true, true);
  Check(marks.back() && flashes.back() == Flash::once);
  state.Set(true, true, true);
  Check(flashes.size() == 4); // Reduced motion not repeated by each poll.
  state.Set(true, true, false, true);
  Check(marks.size() == 2 && marks.back()); // Explorer recreates persistent badge.
  state.Set(false, true, false);
  Check(marks.size() == 3 && !marks.back());
  state.Set(false, true, false);
  Check(marks.size() == 3);
  // Compile/exercise the actual adapter only against an invisible tool HWND,
  // never the acceptance client's window or real taskbar button.
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  HWND window = CreateWindowExW(WS_EX_TOOLWINDOW, L"STATIC", L"Taskbar fixture",
      WS_POPUP | WS_DISABLED, 0, 0, 1, 1, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
  Check(window != nullptr);
  HWND foreground = GetForegroundWindow();
  {
    TaskbarAttention attention(window);
    attention.Set(true, false);
    attention.HandleMessage(RegisterWindowMessageW(L"TaskbarButtonCreated"), 0);
    attention.Set(false, true);
  }
  Check(GetForegroundWindow() == foreground && !IsWindowVisible(window));
  DestroyWindow(window);
  CoUninitialize();
  std::cout << "PASS persistent attention, focus/read separation, coalescing, reduced motion, restore and hidden adapter\n";
  return 0;
}
int main() {
  try { return RunChecks(); }
  catch (const std::exception& error) {
    std::cerr << "FAIL " << error.what() << '\n';
    return 1;
  }
}
