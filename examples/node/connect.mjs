// Create a bcli cloud session, open a page, take a screenshot over CDP, stop the session.
//
//   npm i playwright            (PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 – we attach to the cloud browser)
//   node connect.mjs https://example.com
//
// Requires bcli on PATH and a signed-in environment (bcli whoami).
import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { chromium } from 'playwright';

const url = process.argv[2] ?? 'https://example.com';
const session = JSON.parse(execFileSync('bcli', ['session', 'create', '--wait'], { encoding: 'utf8' }));
console.log(`session ${session.id} ${session.state}`); // never print cdp_url/view_url: they contain a token

try {
  const browser = await chromium.connectOverCDP(session.cdp_url, { timeout: 30_000 });
  const context = browser.contexts()[0] ?? (await browser.newContext());
  const page = context.pages()[0] ?? (await context.newPage());

  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60_000 });
  console.log('title:', await page.title());

  const cdp = await context.newCDPSession(page);
  const { data } = await cdp.send('Page.captureScreenshot', { format: 'png' });
  writeFileSync('screenshot.png', Buffer.from(data, 'base64'));
  console.log('wrote screenshot.png');

  await browser.close(); // disconnects only
} finally {
  execFileSync('bcli', ['session', 'stop', session.id], { stdio: 'ignore' });
  console.log(`session ${session.id} stopped`);
}
