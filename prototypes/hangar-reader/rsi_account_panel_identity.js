// Adapter for the expanded RSI account panel observed in the 2026-09-02
// owner-supplied hangar snapshot. Native code must separately validate origin,
// document generation and current app account before consuming these claims.
function readRsiAccountPanelHandles(documentRoot = document) {
  const panels = documentRoot.querySelectorAll('.accountPanel[data-cy-id="account-sidepanel"]');
  if (panels.length !== 1) return [];
  const identities = panels[0].querySelectorAll(
    ':scope > .accountPanelUser > .accountPanelUser__identity > .m-identity[data-cy-id="identity"]'
  );
  const handles = [];
  for (const identity of identities) {
    const fields = identity.querySelectorAll(':scope > span.a-handleName[data-cy-id="handleName"]');
    if (fields.length === 0) handles.push(null);
    for (const field of fields) {
      const displayed = field.textContent.trim();
      // Only this explicit field owns the presentation prefix. Do not change
      // general Handle normalization or strip arbitrary punctuation/characters.
      const handle = displayed.startsWith('@') ? displayed.slice(1) : displayed;
      handles.push(field.childElementCount === 0 && /^[^\s@]+$/u.test(handle) ? handle : null);
      if (handles.length > 8) return handles;
    }
    if (handles.length > 8) return handles;
  }
  return handles;
}
