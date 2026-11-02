#include "taskbar_attention.h"
#include <shobjidl.h>
#include <wrl/client.h>
#include <limits>

namespace {
constexpr UINT_PTR kAttentionTimer = 0x5344;
}
namespace taskbar_attention_detail {
HICON MakeUnreadIcon() {
  // Six-pixel pure-red dot on the Shell's existing transparent 16px canvas.
  // Supersample only coverage: no outline, shadow, text or second color.
  BITMAPV5HEADER header{};
  header.bV5Size = sizeof(header); header.bV5Width = 16; header.bV5Height = -16;
  header.bV5Planes = 1; header.bV5BitCount = 32; header.bV5Compression = BI_BITFIELDS;
  header.bV5RedMask = 0x00ff0000; header.bV5GreenMask = 0x0000ff00;
  header.bV5BlueMask = 0x000000ff; header.bV5AlphaMask = 0xff000000;
  void* pixels = nullptr;
  HDC dc = GetDC(nullptr);
  HBITMAP color = CreateDIBSection(dc, reinterpret_cast<BITMAPINFO*>(&header),
      DIB_RGB_COLORS, &pixels, nullptr, 0);
  ReleaseDC(nullptr, dc);
  if (!color || !pixels) { if (color) DeleteObject(color); return nullptr; }
  auto* data = static_cast<unsigned long*>(pixels);
  for (int y = 0; y < 16; ++y) for (int x = 0; x < 16; ++x) {
    int covered = 0;
    for (int sy = 0; sy < 4; ++sy) for (int sx = 0; sx < 4; ++sx) {
      const int dx = 8*x+2*sx+1-64, dy = 8*y+2*sy+1-64;
      if (dx*dx+dy*dy <= 24*24) ++covered;
    }
    const unsigned long alpha = (covered*255+8)/16;
    // Windows alpha icons require premultiplied BGRA pixels.
    data[y*16+x] = (alpha << 24) | (alpha << 16);
  }
  const unsigned char mask_bits[32]{};
  HBITMAP mask = CreateBitmap(16, 16, 1, 1, mask_bits);
  ICONINFO info{}; info.fIcon = TRUE; info.hbmColor = color; info.hbmMask = mask;
  HICON icon = mask ? CreateIconIndirect(&info) : nullptr;
  if (mask) DeleteObject(mask);
  DeleteObject(color);
  return icon;
}
}
class TaskbarAttention::Impl {
 public:
  explicit Impl(HWND window) : window_(window),
      button_created_(RegisterWindowMessageW(L"TaskbarButtonCreated")),
      state_([this](bool pending) { Mark(pending); },
             [this](TaskbarAttentionState::Flash flash) { Flash(flash); }) {}
  ~Impl() {
    KillTimer(window_, kAttentionTimer);
    state_.Set(false, true, false, true);
    if (icon_) DestroyIcon(icon_);
  }
  void Set(bool pending, bool reduce) {
    pending_ = pending; reduce_ = reduce;
    if (pending_) SetTimer(window_, kAttentionTimer, 1000, nullptr);
    else KillTimer(window_, kAttentionTimer);
    Update();
  }
  bool Message(UINT message, WPARAM wparam) {
    if (message == button_created_) { taskbar_.Reset(); Update(true); return true; }
    if (message == WM_TIMER && wparam == kAttentionTimer) { Update(); return true; }
    if (message == WM_ACTIVATEAPP || message == WM_ACTIVATE) Update();
    return false;
  }
 private:
  void Update(bool force = false) {
    DWORD foreground = 0;
    GetWindowThreadProcessId(GetForegroundWindow(), &foreground);
    BOOL animations = TRUE;
    SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &animations, 0);
    state_.Set(pending_, reduce_ || !animations, foreground != GetCurrentProcessId(), force);
    if (pending_ && !marked_) Mark(true); // Retry a temporarily unavailable shell.
  }
  void Mark(bool pending) {
    if (!taskbar_) {
      if (FAILED(CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER,
          IID_PPV_ARGS(taskbar_.GetAddressOf()))) || FAILED(taskbar_->HrInit())) {
        taskbar_.Reset(); return;
      }
    }
    if (pending && !icon_) icon_ = taskbar_attention_detail::MakeUnreadIcon();
    if (pending && !icon_) { marked_ = false; return; }
    marked_ = SUCCEEDED(taskbar_->SetOverlayIcon(window_, pending ? icon_ : nullptr,
        pending ? L"Unread messages or pending tasks" : L""));
  }
  void Flash(TaskbarAttentionState::Flash state) {
    FLASHWINFO info{sizeof(info), window_, FLASHW_STOP, 0, 0};
    if (state != TaskbarAttentionState::Flash::stop) {
      info.dwFlags = FLASHW_TRAY; info.uCount = 1;
      if (state == TaskbarAttentionState::Flash::continuous) {
        info.dwFlags |= FLASHW_TIMER; info.uCount = std::numeric_limits<UINT>::max();
      }
    }
    FlashWindowEx(&info); // No focus/restore; return value describes prior state.
  }
  HWND window_;
  UINT button_created_;
  bool pending_ = false, reduce_ = false;
  bool marked_ = false;
  HICON icon_ = nullptr;
  Microsoft::WRL::ComPtr<ITaskbarList3> taskbar_;
  TaskbarAttentionState state_;
};
TaskbarAttention::TaskbarAttention(HWND window) : impl_(std::make_unique<Impl>(window)) {}
TaskbarAttention::~TaskbarAttention() = default;
void TaskbarAttention::Set(bool pending, bool reduce) { impl_->Set(pending, reduce); }
bool TaskbarAttention::HandleMessage(UINT message, WPARAM wparam) { return impl_->Message(message, wparam); }
