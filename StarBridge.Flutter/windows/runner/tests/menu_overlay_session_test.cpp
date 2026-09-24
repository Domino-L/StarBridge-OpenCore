#include "menu_overlay_session.h"
#include <cstdio>

int main() {
  int failed = 0;
  auto check = [&failed](bool condition, const char* name) {
    printf("%s|%s\n", condition ? "PASS" : "FAIL", name);
    if (!condition) ++failed;
  };
  MenuOverlaySession session;
  check(!session.wanted(), "initially hidden");
  check(!session.AcceptFrame(0), "unsolicited frame rejected");
  const auto first = session.Begin();
  check(session.wanted() && session.phase() == MenuOverlaySession::Phase::awaiting_frame,
      "begin does not reveal");
  check(!session.AcceptFrame(first + 1), "future frame rejected");
  session.Dismiss();
  check(!session.AcceptFrame(first), "late frame after cancellation rejected");
  const auto second = session.Begin();
  check(second > first && !session.AcceptFrame(first), "old opening cannot reveal new session");
  check(session.AcceptFrame(second), "matching first frame accepted");
  check(!session.AcceptFrame(second), "duplicate frame cannot reactivate");
  session.Dismiss();
  session.Dismiss();
  check(!session.wanted() && session.phase() == MenuOverlaySession::Phase::hidden,
      "close is idempotent");
  return failed == 0 ? 0 : 1;
}
