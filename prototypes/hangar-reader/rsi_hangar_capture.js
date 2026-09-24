// Shared production capture. Identity is read only once, before the locked scan.
// Never click account controls, cache a Handle, or copy it onto another document.
function readRsiHangarCapture(documentRoot = document, documentUrl = location.href, includeIdentity = true) {
  const capture = { page: readRsiHangarPage(documentRoot, documentUrl) };
  if (includeIdentity) capture.identity = {
    schemaVersion: 1,
    sourceKind: 'current-account',
    documentUrl: location.href,
    handles: readRsiAccountPanelHandles(documentRoot)
  };
  return capture;
}
