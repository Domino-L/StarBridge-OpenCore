#ifndef RUNNER_TASKBAR_ATTENTION_H_
#define RUNNER_TASKBAR_ATTENTION_H_
#include <functional>
#include <windows.h>
#include <memory>

// Native rendering seam shared with pixel-level regression tests. The caller
// owns the returned icon and must release it with DestroyIcon.
namespace taskbar_attention_detail {
HICON MakeUnreadIcon();
}

// Focus and popup dismissal never acknowledge unread/pending work.
class TaskbarAttentionState {
 public:
  enum class Flash { stop, once, continuous };
  TaskbarAttentionState(std::function<void(bool)> mark, std::function<void(Flash)> flash)
      : mark_(std::move(mark)), flash_(std::move(flash)) {}
  void Set(bool pending, bool reduce, bool background, bool force = false) {
    if (force || pending != pending_) mark_(pending);
    const auto next = !pending || !background ? Flash::stop
        : reduce ? Flash::once : Flash::continuous;
    if (force || next != flashing_) flash_(next);
    pending_ = pending; flashing_ = next;
  }
 private:
  std::function<void(bool)> mark_;
  std::function<void(Flash)> flash_;
  bool pending_ = false;
  Flash flashing_ = Flash::stop;
};
class TaskbarAttention {
 public:
  explicit TaskbarAttention(HWND window);
  ~TaskbarAttention();
  void Set(bool pending, bool reduce);
  bool HandleMessage(UINT message, WPARAM wparam);
 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};
#endif
