# starbridge_interaction

StarBridge 自有 Flutter 交互组件，包含 standard、rail、scan、glow 四套风格，
按 Apache-2.0 随仓库公开。完整许可见 [LICENSE](LICENSE)，来源说明见
[VENDORED.md](VENDORED.md)。

提供按钮、切换、选择轨道、导航、弹层、提示和输入反馈。宿主负责业务状态、
主题和持久化；组件保留键盘、读屏和减少动态的独立输入语义。

要求 Dart ^3.13.2、Flutter >=3.47.0。客户端通过仓库内路径依赖使用本包：

```yaml
dependencies:
  starbridge_interaction:
    path: packages/starbridge_interaction
```

本包不单独发布到 pub.dev。导入入口为
`package:starbridge_interaction/starbridge_interaction.dart`。

## Client verified extension: delete-only chips (2026-10-13)

`SuiteChipGroup(onToggle: null, ...)` renders a deletion-only face: its label
does not toggle or delete. Use `onRemoveWithSource` instead of `onRemove` when
the host needs pointer/keyboard origin; the two callbacks are exclusive.
`changeSource` makes keyboard/reader clear or uncheck land without an exit tail.
`SuiteChipData.side`, `backgroundColor` and `removeLabel` preserve the host's
classification colours and localized removal label without owning selection.

If a host supplies `focusNodeForId`, it owns those nodes and keeps them alive
through removal/restore until the group is unmounted. The group repairs focus,
but does not dispose supplied nodes. `fallbackFocus` receives keyboard focus
when the last focused chip leaves. Removal/restore reuses the existing single
controller/element per id; leaving faces retain their colour and cannot act.

The 20 `delete_only_chips_test.dart` cases cover all four suites, exact input
source, delete-only body, keyboard focus repair, external focus ownership,
remove/restore colour and live reduced-motion exit. These are synthetic checks,
not real screen-reader or device acceptance.

## Client verified extension: inline disclosure focus (2026-10-17)

An inline `SuiteExpander` body tracks descendant focus with a non-traversable
`Focus` node, not an independent `FocusScope`. Tab skips a text-only body but
still reaches its real fields/actions; the containing page or dialog retains
its own traversal boundary. Collapsing a focused body still returns focus to
the existing enabled header, and `maintainState` does not change.

Eight `expander_text_traversal_test.dart` cases exercise real Tab/Shift+Tab and
Enter for text-only bodies across all suites and both retain-state modes.
Existing traversal/field-identity/modal-loop tests remain the adjacent gates.
These automated checks do not establish real screen-reader/device acceptance.

## Client verified extension: passive hint dismissal (2026-10-17)

Passive text/tag hints can be hovered without giving them keyboard focus.
While a hint is waiting or visible, it observes Escape through the focus
manager without moving focus; hide/dispose removes that observer. A hint with
`consumeEscape: false` still lets the same key reach its modal owner. Background
route hints do not consume a foreground route's Escape. Other keys are untouched.

The 28 `tooltip_passive_escape_test.dart` checks cover all four suites,
pending/visible hints, consuming/non-consuming dismissal, a subsequent Escape,
unmount during a wait/display, and foreground dialog dismissal. The latter
allows a fresh hover to appear after the foreground route has gone, rather than
mistaking that new pointer entry for a stale bubble. Client room checks also
exercise real passive labels, edges, live reduced motion, and the avatar menu.
These are bounded automated checks, not real device or screen-reader acceptance.
