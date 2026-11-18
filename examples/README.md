# Examples

Minimal scripts that create a bcli cloud session, open a page, take a screenshot over CDP and stop the session again.
Both need `bcli` on your `PATH` and a signed-in environment (`bcli whoami`).

| Example | Run |
|---|---|
| [Node.js + Playwright](node/connect.mjs) | `cd node && PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install && node connect.mjs https://example.com` |
| [Python + Playwright](python/connect.py) | `pip install playwright && python python/connect.py https://example.com` |

The scripts never print `cdp_url` or `view_url`, because both contain a session access token.
