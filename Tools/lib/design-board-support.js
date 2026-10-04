// Minimal local stand-in for the Design canvas runtime, so Tools/design-board can
// render boards that use renderVals(), {{holes}}, <sc-for> and <sc-if>.
// Static only: no state changes, no events.
window.DCLogic = class DCLogic {
  constructor(props) { this.props = props || {}; this.state = {}; }
  setState(s) { Object.assign(this.state, typeof s === 'function' ? s(this.state, this.props) : s); }
  forceUpdate() {}
};
(function () {
  const HOLE = /\{\{\s*([^}]*?)\s*\}\}/g;
  function literal(p) {
    if (p === 'true') return { v: true }; if (p === 'false') return { v: false }; if (p === 'null') return { v: null };
    if (/^-?\d+(\.\d+)?$/.test(p)) return { v: Number(p) };
    if (/^'.*'$|^".*"$/.test(p)) return { v: p.slice(1, -1) };
    return null;
  }
  function lookup(path, scopes) {
    const lit = literal(path); if (lit) return lit.v;
    const parts = path.split('.');
    let base;
    for (let i = scopes.length - 1; i >= 0; i--) { if (scopes[i] && parts[0] in Object(scopes[i])) { base = scopes[i][parts[0]]; break; } }
    for (let k = 1; k < parts.length && base != null; k++) base = base[parts[k]];
    return base;
  }
  function interp(str, scopes) {
    const whole = str.match(/^\s*\{\{\s*([^}]*?)\s*\}\}\s*$/);
    if (whole) return lookup(whole[1], scopes);
    return str.replace(HOLE, (_, p) => { const v = lookup(p, scopes); return v == null || typeof v === 'function' ? '' : String(v); });
  }
  function expand(node, scopes) {
    for (const child of [...node.childNodes]) {
      if (child.nodeType === 3) {
        if (child.nodeValue.includes('{{')) { const v = interp(child.nodeValue, scopes); child.nodeValue = v == null || typeof v === 'function' ? '' : String(v); }
        continue;
      }
      if (child.nodeType !== 1) continue;
      const tag = child.localName;
      if (tag === 'sc-for') {
        const list = lookup((child.getAttribute('list') || '').replace(/^\s*\{\{\s*|\s*\}\}\s*$/g, ''), scopes) || [];
        const as = child.getAttribute('as') || 'item';
        const frag = document.createDocumentFragment();
        [...list].forEach((it, i) => {
          const box = document.createElement('div');
          for (const c of child.childNodes) box.appendChild(c.cloneNode(true));
          expand(box, scopes.concat([{ [as]: it, $index: i }]));
          while (box.firstChild) frag.appendChild(box.firstChild);
        });
        child.replaceWith(frag);
        continue;
      }
      if (tag === 'sc-if') {
        const raw = child.getAttribute('value') || '';
        const v = raw.includes('{{') ? interp(raw, scopes) : raw;
        if (v) { expand(child, scopes); child.replaceWith(...child.childNodes); } else child.remove();
        continue;
      }
      if (tag === 'dc-import') { child.remove(); continue; }
      for (const a of [...child.attributes]) {
        if (!a.value.includes('{{')) continue;
        if (/^on/i.test(a.name)) { child.removeAttribute(a.name); continue; }
        const v = interp(a.value, scopes);
        if (v == null || v === false || typeof v === 'function') child.removeAttribute(a.name);
        else child.setAttribute(a.name, v === true ? '' : String(v));
      }
      expand(child, scopes);
    }
  }
  document.addEventListener('DOMContentLoaded', () => {
    const host = document.querySelector('x-dc');
    const sc = document.querySelector('script[data-dc-script]');
    if (!host || !sc) return;
    host.querySelectorAll('helmet').forEach(h => { h.querySelectorAll('style, link').forEach(s => document.head.appendChild(s)); h.remove(); });
    let props = {};
    try { props = JSON.parse(sc.getAttribute('data-props') || '{}'); } catch (e) {}
    const defaults = {};
    for (const [k, v] of Object.entries(props)) if (k !== '$preview' && v && 'default' in v) defaults[k] = v.default;
    if (window.__DC_PROPS) Object.assign(defaults, window.__DC_PROPS);
    let vals = {};
    try {
      const C = new Function('DCLogic', sc.textContent + '\n;return Component;')(window.DCLogic);
      const inst = new C(defaults); inst.props = defaults;
      vals = inst.renderVals() || {};
    } catch (e) { document.title = 'RENDER ERROR ' + e.message; console.error(e); }
    expand(host, [vals]);
  });
})();
