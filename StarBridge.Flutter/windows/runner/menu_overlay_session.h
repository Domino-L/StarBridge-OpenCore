#ifndef RUNNER_MENU_OVERLAY_SESSION_H_
#define RUNNER_MENU_OVERLAY_SESSION_H_

#include <cstdint>

// Window-independent opening lease. Late Dart/engine frames cannot reopen a
// dismissed menu, including after another opening has begun.
class MenuOverlaySession {
 public:
  enum class Phase { hidden, awaiting_frame, visible };
  uint64_t Begin() {
    ++generation_;
    phase_ = Phase::awaiting_frame;
    return generation_;
  }
  bool AcceptFrame(uint64_t generation) {
    if (phase_ != Phase::awaiting_frame || generation != generation_) return false;
    phase_ = Phase::visible;
    return true;
  }
  void Dismiss() { phase_ = Phase::hidden; }
  bool wanted() const { return phase_ != Phase::hidden; }
  Phase phase() const { return phase_; }
  uint64_t generation() const { return generation_; }

 private:
  uint64_t generation_ = 0;
  Phase phase_ = Phase::hidden;
};
#endif
