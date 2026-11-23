const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const PAGES = ['/', '/404.html'];

for (const url of PAGES) {
  test(`no console errors or failed requests on ${url}`, async ({ page }) => {
    const problems = [];
    page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') problems.push(`${m.type()}: ${m.text()}`); });
    page.on('pageerror', (e) => problems.push(`pageerror: ${e.message}`));
    page.on('requestfailed', (r) => problems.push(`requestfailed: ${r.url()}`));
    page.on('response', (r) => { if (r.status() >= 400) problems.push(`${r.status()}: ${r.url()}`); });
    const origin = 'http://127.0.0.1:4173';
    page.on('request', (r) => { if (!r.url().startsWith(origin) && !r.url().startsWith('data:')) problems.push(`external request: ${r.url()}`); });
    await page.goto(url);
    await page.waitForLoadState('networkidle');
    expect(problems).toEqual([]);
  });
}

for (const width of [375, 1440]) {
  test(`no horizontal overflow at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 });
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    const m = await page.evaluate(() => ({
      doc: document.documentElement.scrollWidth,
      body: document.body.scrollWidth,
      client: document.documentElement.clientWidth,
    }));
    expect(m.doc).toBeLessThanOrEqual(m.client);
    expect(m.body).toBeLessThanOrEqual(m.client);
    // Nothing visible should poke past the right edge, except inside a scrollable table or code box.
    const leaks = await page.evaluate(() => {
      const out = [];
      const vw = document.documentElement.clientWidth;
      document.querySelectorAll('main *, header *, footer *').forEach((el) => {
        if (el.closest('.tablewrap, pre, .aurora')) return;
        const r = el.getBoundingClientRect();
        if (r.width > 0 && r.right > vw + 1) out.push(el.tagName + '.' + el.className);
      });
      return out;
    });
    expect(leaks).toEqual([]);
  });
}

test('reduced motion shows every section and turns animation off', async ({ browser }) => {
  const ctx = await browser.newContext({ reducedMotion: 'reduce', viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  await page.goto('/');
  expect(await page.evaluate(() => document.documentElement.classList.contains('js'))).toBe(false);
  const sections = page.locator('main > section');
  expect(await sections.count()).toBeGreaterThanOrEqual(6);
  for (const s of await sections.all()) {
    await expect(s).toBeVisible();
    expect(await s.evaluate((el) => getComputedStyle(el).opacity)).toBe('1');
  }
  const anim = await page.evaluate(() => [...document.querySelectorAll('.node, .pkt, .aurora i')].map((e) => getComputedStyle(e).animationName));
  expect(anim.every((n) => n === 'none')).toBe(true);
  await ctx.close();
});

test('without JavaScript every section is visible', async ({ browser }) => {
  const ctx = await browser.newContext({ javaScriptEnabled: false });
  const page = await ctx.newPage();
  await page.goto('/');
  for (const s of await page.locator('main > section').all()) {
    await expect(s).toBeVisible();
    expect(await s.evaluate((el) => getComputedStyle(el).opacity)).toBe('1');
  }
  await ctx.close();
});

test('with motion allowed, sections reveal after scrolling', async ({ page }) => {
  await page.goto('/');
  await page.evaluate(async () => {
    for (let y = 0; y < document.body.scrollHeight; y += 400) { window.scrollTo(0, y); await new Promise((r) => setTimeout(r, 60)); }
  });
  for (const s of await page.locator('main > section').all()) {
    await expect.poll(() => s.evaluate((el) => parseFloat(getComputedStyle(el).opacity))).toBeGreaterThan(0.99);
  }
});

test('copy button puts the commands on the clipboard', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.goto('/');
  const btn = page.locator('button.copy[data-target="c4"]');
  await btn.scrollIntoViewIfNeeded();
  await expect(btn).toBeVisible();
  await btn.click();
  await expect(btn).toHaveText('Copied');
  const text = await page.evaluate(() => navigator.clipboard.readText());
  expect(text).toContain('python3 scripts/airgap_bundle.py create --images scripts/images.txt');
  expect(text).toContain('verify --bundle bundle.tar');
  expect(text).not.toContain('$ ');
});

test('internal links and anchors resolve', async ({ page, request }) => {
  await page.goto('/');
  const hrefs = await page.$$eval('a[href]', (as) => as.map((a) => a.getAttribute('href')));
  const ids = new Set(await page.$$eval('[id]', (els) => els.map((e) => e.id)));
  const internal = hrefs.filter((h) => !/^(https?:|mailto:)/.test(h));
  expect(internal.length).toBeGreaterThan(5);
  for (const h of internal) {
    if (h.startsWith('#')) { expect(ids.has(h.slice(1)), `anchor ${h}`).toBe(true); continue; }
    const res = await request.get(new URL(h, page.url()).toString());
    expect(res.status(), h).toBe(200);
  }
  // Every external link opens safely.
  const ext = await page.$$eval('a[href^="http"]', (as) => as.map((a) => ({ h: a.href, rel: a.rel })));
  for (const l of ext) expect(l.rel, l.h).toContain('noopener');
  // Linked assets exist.
  for (const sel of ['link[rel="stylesheet"]', 'link[rel="icon"]', 'script[src]', 'meta[property="og:image"]']) {
    const v = await page.$eval(sel, (e) => e.getAttribute('href') || e.getAttribute('src') || e.getAttribute('content'));
    if (v.startsWith('http')) continue;
    expect((await request.get(new URL(v, page.url()).toString())).status(), v).toBe(200);
  }
});

test('metadata and static files are present', async ({ page, request }) => {
  await page.goto('/');
  await expect(page).toHaveTitle(/airgap-platform-kit/);
  expect(await page.locator('meta[name="description"]').getAttribute('content')).toBeTruthy();
  expect(await page.locator('link[rel="canonical"]').getAttribute('href')).toBe('https://gerardrecinto.github.io/airgap-platform-kit/');
  for (const p of ['og:title', 'og:description', 'og:image', 'og:url']) await expect(page.locator(`meta[property="${p}"]`)).toHaveCount(1);
  for (const n of ['twitter:card', 'twitter:image']) await expect(page.locator(`meta[name="${n}"]`)).toHaveCount(1);
  const ld = JSON.parse(await page.locator('script[type="application/ld+json"]').textContent());
  expect(ld['@type']).toBe('SoftwareSourceCode');
  expect(await page.locator('a.skip').getAttribute('href')).toBe('#main');
  for (const f of ['/robots.txt', '/sitemap.xml', '/favicon.svg', '/404.html', '/og-image.png']) {
    expect((await request.get(f)).status(), f).toBe(200);
  }
  const png = fs.readFileSync(path.join(__dirname, '..', 'docs', 'og-image.png'));
  expect(png.readUInt32BE(16)).toBe(1200);
  expect(png.readUInt32BE(20)).toBe(630);
});
