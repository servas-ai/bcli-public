"""Create a bcli cloud session, open a page, take a screenshot over CDP, stop the session.

    pip install playwright        # no `playwright install` needed: we attach to the cloud browser
    python connect.py https://example.com

Requires bcli on PATH and a signed-in environment (bcli whoami).
"""
import base64
import json
import subprocess
import sys

from playwright.sync_api import sync_playwright

url = sys.argv[1] if len(sys.argv) > 1 else "https://example.com"
session = json.loads(subprocess.run(["bcli", "session", "create", "--wait"],
                                    check=True, capture_output=True, text=True).stdout)
print(f"session {session['id']} {session['state']}")  # never print cdp_url/view_url: they contain a token

try:
    with sync_playwright() as p:
        browser = p.chromium.connect_over_cdp(session["cdp_url"], timeout=30_000)
        context = browser.contexts[0] if browser.contexts else browser.new_context()
        page = context.pages[0] if context.pages else context.new_page()

        page.goto(url, wait_until="domcontentloaded", timeout=60_000)
        print("title:", page.title())

        cdp = context.new_cdp_session(page)
        shot = cdp.send("Page.captureScreenshot", {"format": "png"})
        with open("screenshot.png", "wb") as f:
            f.write(base64.b64decode(shot["data"]))
        print("wrote screenshot.png")

        browser.close()  # disconnects only
finally:
    subprocess.run(["bcli", "session", "stop", session["id"]], capture_output=True)
    print(f"session {session['id']} stopped")
