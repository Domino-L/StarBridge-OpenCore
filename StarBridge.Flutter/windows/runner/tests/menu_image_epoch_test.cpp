#include "menu_image_epoch.h"
#include <stdexcept>
#include <iostream>
int main() {
  MenuImageEpoch epoch;
  auto check = [](bool ok) { if (!ok) throw std::runtime_error("Resource epoch regression"); };
  check(epoch.value() == 0);
  check(!epoch.Request(0) && !epoch.Request(-1));
  check(!epoch.Request(MenuImageEpoch::kMaximum + 1));
  check(epoch.Request(2) && epoch.value() == 2);
  check(epoch.Request(1) && epoch.value() == 2);
  check(epoch.Request(2) && epoch.value() == 2);
  check(epoch.Observe(0) && epoch.value() == 2);
  check(epoch.Request(3) && epoch.value() == 3);
  std::cout << "PASS resource epoch does not regress or grant window authority\n";
}
