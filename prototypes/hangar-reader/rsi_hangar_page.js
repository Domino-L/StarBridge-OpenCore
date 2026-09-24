// Read-only adapter for the three supplied RSI snapshots. The native caller
// separately verifies account identity, source and capture generation.
function readRsiHangarPage(documentRoot = document, pageAddress = location.href) {
  const result = { schemaVersion: 1, documentUrl: location.href, status: 'unsupported',
    page: null, totalPages: null, nextPage: null, unfiltered: false, pledges: [], issue: null };
  const fail = issue => { throw new Error(issue); };
  const only = (root, selector) => {
    const matches = root.querySelectorAll(selector);
    return matches.length === 1 ? matches[0] : fail('structure');
  };
  const text = (node, limit, required = false) => {
    const value = node?.textContent.replace(/\s+/gu, ' ').trim() ?? '';
    if ((required && !value) || value.length > limit || /[\u0000-\u001f\u007f]/u.test(value)) fail('field');
    return value || null;
  };
  const address = (value, isLink = false) => {
    const url = new URL(value, pageAddress);
    if (url.origin !== 'https://robertsspaceindustries.com' || url.username || url.password || url.hash ||
        !['/account/pledges', '/en/account/pledges'].includes(url.pathname)) fail('source');
    for (const key of url.searchParams.keys()) {
      if (url.searchParams.getAll(key).length !== 1) fail('query');
      if (!['page', 'product-type'].includes(key) || key === 'product-type' && url.searchParams.get(key)) fail('filtered');
    }
    const page = url.searchParams.get('page');
    if (page === null) return isLink ? fail('page-link') : 1;
    if (!/^[1-9][0-9]{0,2}$/.test(page) || Number(page) > 100) fail('page-limit');
    return Number(page);
  };
  const pager = node => {
    const links = Array.from(node.querySelectorAll('a'));
    if (links.length === 0 || links.length > 110) fail('pager');
    const pages = links.map(a => ({ node: a, page: address(a.getAttribute('href') || '', true) }));
    const find = cls => {
      const matches = pages.filter(p => p.node.classList.contains(cls));
      if (matches.length > 1) fail('pager');
      return matches[0]?.page ?? null;
    };
    const active = find('active'), next = find('gt'), last = find('raquo');
    if (active === null || next !== null && next !== active + 1 || last !== null && last < active) fail('pager');
    if (last !== null && last > active && next === null) fail('pager-next');
    const numbers = [];
    for (const link of pages) {
      if (link.node.classList.contains('btn')) {
        if (!['gt', 'raquo', 'lt', 'laquo'].some(c => link.node.classList.contains(c))) fail('pager-button');
      } else {
        if (text(link.node, 3, true) !== String(link.page)) fail('pager-label');
        numbers.push(link.page);
      }
    }
    if (new Set(numbers).size !== numbers.length || !numbers.includes(active) || numbers.some(p => last !== null && p > last)) fail('pager');
    if (find('lt') !== (active > 1 ? active - 1 : null) || find('laquo') !== (active > 1 ? 1 : null)) fail('pager-previous');
    return { active, next, last, numbers };
  };
  try {
    const urlPage = address(pageAddress);
    const root = only(documentRoot, '#billing.pledges > .content > .inner-content');
    const filter = only(root, ':scope > .billing-title-pager-wrapper .js-product-type-filter');
    const select = only(filter, ':scope > a.js-selectlist');
    const selected = only(select, ':scope > ul.body > li.js-option.selected');
    const selection = new URL(selected.getAttribute('rel') || '', pageAddress);
    address(selection.href);
    if (select.getAttribute('rel') !== '' || selection.searchParams.get('product-type') !== '' ||
        [...selection.searchParams.keys()].some(k => !['page', 'product-type'].includes(k))) fail('filtered');
    if (Array.from(root.querySelectorAll('input[type="search"]')).some(n => n.value.trim())) fail('filtered');
    result.unfiltered = true;
    const pagers = Array.from(root.querySelectorAll(':scope > .billing-title-pager-wrapper .pager'));
    if (pagers.length !== 2) fail('pager-count');
    const first = pager(pagers[0]), second = pager(pagers[1]);
    if (JSON.stringify(first) !== JSON.stringify(second) || first.active !== urlPage) fail('pager-disagrees');
    result.page = first.active;
    result.totalPages = first.last; // Not the maximum of the visible numeric links.
    result.nextPage = first.next;   // Last-page total is carried from previous accepted pages.
    const list = only(root, ':scope > ul.list-items');
    const rows = Array.from(list.children);
    if (rows.length > 200) fail('row-limit');
    if (rows.length === 0) { result.status = 'unconfirmedEmpty'; return result; }
    const keys = new Set();
    let itemCount = 0;
    for (const li of rows) {
      if (li.tagName !== 'LI') fail('row');
      const row = only(li, ':scope > .row');
      const keyField = only(row, ':scope > .basic-infos .title-col > input.js-pledge-id');
      const sourceKey = keyField.value;
      if (!sourceKey || sourceKey.length > 128 || /[\s\u0000-\u001f]/u.test(sourceKey) || keys.has(sourceKey)) fail('pledge-key');
      keys.add(sourceKey);
      const date = only(row, ':scope > .basic-infos .date-col');
      const acquiredText = text(date, 160)?.replace(/^(Created|Acquired|创建|建立|入库|获得|获取)\s*:?\s*/iu, '').trim() || null;
      if (acquiredText?.length > 128) fail('date');
      const container = only(row, ':scope > .items');
      const blocks = container.querySelectorAll(':scope > .content-block1');
      const items = [];
      // Observed pledge with only a heading and clearing span: preserve an
      // unclassified pledge. It is NOT evidence that it contains no ships.
      if (blocks.length === 0) {
        if (Array.from(container.children).some(n => n.tagName !== 'H2' && !(n.tagName === 'SPAN' && n.classList.contains('clear')))) fail('item-structure');
        result.pledges.push({ sourceKey, acquiredText, items });
        continue;
      }
      if (blocks.length !== 1) fail('item-structure');
      const entries = Array.from(blocks[0].querySelectorAll(':scope > .with-images > .item, :scope > .without-images > .item'));
      if (entries.length !== container.querySelectorAll('.item').length) fail('item-structure');
      for (const entry of entries) {
        if (++itemCount > 2000) fail('item-limit');
        const kinds = entry.querySelectorAll('.kind'), liners = entry.querySelectorAll('.liner');
        if (kinds.length > 1 || liners.length > 1) fail('item-field');
        items.push({ title: text(only(entry, '.title'), 256, true), kind: text(kinds[0], 64), liner: text(liners[0], 256) });
      }
      result.pledges.push({ sourceKey, acquiredText, items });
    }
    result.status = 'ready';
    if (JSON.stringify(result).length > 256 * 1024) fail('payload-limit');
    return result;
  } catch (error) {
    result.status = error.message === 'filtered' ? 'filtered' : 'unsupported';
    result.issue = error.message;
    result.pledges = []; // No caller can mistake a partially parsed page for a complete one.
    return result;
  }
}
