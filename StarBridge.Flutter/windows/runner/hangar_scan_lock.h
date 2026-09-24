#pragma once
#include <string>
#include <utility>

// Native-owned lifetime and navigation fence. Neither DOM nor user navigation
// may extend or resume it. Only a new explicit start creates another scan.
class HangarScanLock {
 public:
  bool Begin(std::string id) {
    if (active_ || id.empty()) return false;
    active_ = true; invalid_ = false; id_ = std::move(id); target_.clear(); return true;
  }
  void End() { active_ = false; invalid_ = false; id_.clear(); target_.clear(); }
  bool Active() const { return active_; }
  bool Valid() const { return active_ && !invalid_; }
  const std::string& Id() const { return id_; }
  void Invalidate() { if (active_) invalid_ = true; target_.clear(); }
  bool ExpectNavigation(const std::wstring& target) {
    if (!Valid() || !target_.empty()) return false;
    target_ = target; return true;
  }
  bool NavigationStarting(const std::wstring& target, bool user, bool redirected) {
    if (!active_) return true;
    // WebView2 also marks native Navigate() as user initiated. The one-use exact
    // target is the authorization; disabled native input excludes manual clicks.
    // Script-initiated navigation remains rejected even for the pending target.
    const bool allowed = Valid() && user && !redirected && !target_.empty() && target == target_;
    target_.clear(); if (!allowed) Invalidate(); return allowed;
  }
 private:
  bool active_ = false, invalid_ = false;
  std::string id_;
  std::wstring target_;
};
