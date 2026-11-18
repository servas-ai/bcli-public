# Examples

Minimal scripts that create a bcli cloud session, open a page, take a screenshot over CDP and stop the session again.
They need `bcli` on your `PATH` and a signed-in environment (`bcli whoami`). Run the commands from the `examples/`
folder of a clone of this repository.

Neither example downloads a browser: Playwright only attaches to the cloud browser over CDP.

## Node.js + Playwright — [node/connect.mjs](node/connect.mjs)

Needs [Node.js](../docs/installation.md#nodejs-for-agent-web-and-the-examples).

```bash
# Linux / macOS
cd node
PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install
node connect.mjs https://example.com
```

```powershell
# Windows PowerShell
cd node
$env:PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1"
npm.cmd install                      # npm.cmd also works when the execution policy blocks npm.ps1
node connect.mjs https://example.com
```

## Python + Playwright — [python/connect.py](python/connect.py)

Use a virtual environment. Recent distributions (e.g. Debian 13) refuse `pip install` into the system Python
(PEP 668, "externally-managed-environment").

```bash
# Linux / macOS  (Debian/Ubuntu: sudo apt install python3-venv first)
python3 -m venv .venv
. .venv/bin/activate
pip install playwright               # no "playwright install": we attach to the cloud browser
python python/connect.py https://example.com
```

```powershell
# Windows PowerShell  (Python from python.org or the Microsoft Store)
py -m venv .venv
.\.venv\Scripts\python.exe -m pip install playwright
.\.venv\Scripts\python.exe python\connect.py https://example.com
```

Calling `.venv\Scripts\python.exe` directly avoids `Activate.ps1`, which a `Restricted` execution policy blocks.

The scripts never print `cdp_url` or `view_url`, because both contain a session access token, and they stop the
session in a `finally` block — also when the page fails to load.
