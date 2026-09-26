// Build-time helpers only. This JavaScript is NOT executed on the glasses.
export const text = (id, value, x, y, w, font = 20) =>
  ({ id, kind: 'text', text: value, x, y, w, h: font + 4, font });
export const button = (id, value, x, y, w, action) =>
  ({ ...text(id, value, x, y, w), kind: 'button', action });
export const page = (id, components) => ({ id, components });
export const app = (id, name, pages, permissions = []) =>
  ({ schema: 1, id, name, version: 1, entry: pages[0].id, pages, permissions, assets: {} });
