#ifndef RUNNER_RSI_TOOL_NOTICE_ASYNC_H_
#define RUNNER_RSI_TOOL_NOTICE_ASYNC_H_

#include <windows.h>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <thread>
#include <utility>
#include <vector>

namespace rsi_tool_notice {

// Runs marker file work off the platform thread. A slow or disconnected
// redirected AppData must never stall the window: Submit returns at once.
// Workers only record an id and a bool; a thread timer on the creating thread
// collects them and replies there. No window messages are sent. Results that
// arrive after destruction are dropped and never touch a stale channel.
class AsyncWork {
 public:
  AsyncWork() : shared_(std::make_shared<Shared>()) {}
  ~AsyncWork() {
    StopTimer();
    pending_.clear();  // Late workers write into `shared_` only; nobody reads it.
  }
  AsyncWork(const AsyncWork&) = delete;
  AsyncWork& operator=(const AsyncWork&) = delete;

  // `work` runs on a worker thread and must not touch the channel; `done`
  // runs later on this thread. Without a timer, `done(false)` runs now.
  void Submit(std::function<bool()> work, std::function<void(bool)> done) {
    if (!timer_) {
      timer_ = SetTimer(nullptr, 0, kPollMilliseconds, OnTimer);
      if (!timer_) { done(false); return; }
      Timers().emplace(timer_, this);
    }
    const auto id = ++last_id_;
    pending_.emplace(id, std::move(done));
    std::thread([shared = shared_, id, work = std::move(work)] {
      bool outcome = false;
      try { outcome = work(); } catch (...) {}
      const std::lock_guard<std::mutex> lock(shared->mutex);
      shared->finished.emplace_back(id, outcome);
    }).detach();
  }
  size_t Pending() const { return pending_.size(); }

 private:
  struct Shared {
    std::mutex mutex;
    std::vector<std::pair<size_t, bool>> finished;
  };
  static constexpr UINT kPollMilliseconds = 50;

  static std::map<UINT_PTR, AsyncWork*>& Timers() {
    static std::map<UINT_PTR, AsyncWork*> timers;
    return timers;
  }
  static void CALLBACK OnTimer(HWND, UINT, UINT_PTR id, DWORD) {
    const auto found = Timers().find(id);
    if (found != Timers().end()) found->second->Collect();
  }
  void Collect() {
    std::vector<std::pair<size_t, bool>> finished;
    {
      const std::lock_guard<std::mutex> lock(shared_->mutex);
      finished.swap(shared_->finished);
    }
    for (const auto& [id, outcome] : finished) {
      const auto found = pending_.find(id);
      if (found == pending_.end()) continue;
      auto done = std::move(found->second);
      pending_.erase(found);
      done(outcome);
    }
    if (pending_.empty()) StopTimer();
  }
  void StopTimer() {
    if (!timer_) return;
    Timers().erase(timer_);
    KillTimer(nullptr, timer_);
    timer_ = 0;
  }

  std::shared_ptr<Shared> shared_;
  UINT_PTR timer_ = 0;
  size_t last_id_ = 0;
  std::map<size_t, std::function<void(bool)>> pending_;
};

}  // namespace rsi_tool_notice

#endif  // RUNNER_RSI_TOOL_NOTICE_ASYNC_H_
