#ifndef RUNNER_MENU_IMAGE_EPOCH_H_
#define RUNNER_MENU_IMAGE_EPOCH_H_
#include <cstdint>
// Resource ordering only; never opening or account authority.
class MenuImageEpoch {
 public:
  static constexpr int64_t kMaximum = 9007199254740991LL;
  bool Observe(int64_t value) {
    if (value < 0 || value > kMaximum) return false;
    if (value > epoch_) epoch_ = value;
    return true;
  }
  bool Request(int64_t value) { return value > 0 && Observe(value); }
  int64_t value() const { return epoch_; }
 private:
  int64_t epoch_ = 0;
};
#endif
