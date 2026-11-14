"""
Schwarznote signing service.

Runs a real Chromium browser with the Xiaohongshu / rednote web page open. For each
request the app wants to make, the page's own HTTP client builds the request, so the
site's interceptors add every header they normally add (X-s, X-t, X-S-Common, trace ids).
`capture_headers.js` records those headers and aborts the request before it is sent.
Nothing is reimplemented or de-obfuscated.

The Apple TV app calls:

    POST /sign   {"region": "china"|"international", "path": "/api/...", "body": {...} | null}
    -> {"headers": {"X-s": "...", ...}, "cookies": {"a1": "...", ...}, "userAgent": "...",
        "path": "/api/...?..."}

`body: null` means a GET request; `path` then includes the query string. The returned `path`
is the one the site actually signed: its client can add query parameters (for example
`client_public_key_base64` on the QR login status call), so the app must send that path.

The signature is bound to the browser's device cookies (a1, webId, ...), so the app must
send those same cookies and the same User-Agent; the response includes both.

Usage:
    ./run.sh                       # listens on 0.0.0.0:8790
    SIGNER_TOKEN=secret ./run.sh   # require "Authorization: Bearer secret"
"""

import asyncio
import json
import logging
import os
from urllib.parse import urlsplit
from pathlib import Path

from aiohttp import web
from playwright.async_api import Browser, Page, async_playwright

ORIGINS = {
    "china": "https://www.xiaohongshu.com/explore",
    "international": "https://www.rednote.com/explore",
}
# Device cookies the signature depends on. Session cookies (web_session) stay on the TV.
DEVICE_COOKIES = {"a1", "webId", "gid", "websectiga", "sec_poison_id", "xsecappid"}

CAPTURE_JS = (Path(__file__).parent / "capture_headers.js").read_text()
# The app sets these itself.
SKIPPED_HEADERS = {"accept", "content-type"}

HOST = os.environ.get("SIGNER_HOST", "0.0.0.0")
PORT = int(os.environ.get("SIGNER_PORT", "8790"))
TOKEN = os.environ.get("SIGNER_TOKEN")
HEADLESS = os.environ.get("SIGNER_HEADLESS", "1") != "0"

log = logging.getLogger("signer")


class Signer:
    def __init__(self, browser: Browser):
        self.browser = browser
        self.pages: dict[str, Page] = {}
        self.locks: dict[str, asyncio.Lock] = {r: asyncio.Lock() for r in ORIGINS}

    async def page_for(self, region: str) -> Page:
        page = self.pages.get(region)
        if page and not page.is_closed():
            return page
        context = await self.browser.new_context(locale="zh-CN")
        page = await context.new_page()
        log.info("loading %s", ORIGINS[region])
        await page.goto(ORIGINS[region], wait_until="domcontentloaded")
        await page.wait_for_function("typeof window._webmsxyw === 'function'", timeout=30_000)
        self.pages[region] = page
        return page

    async def sign(self, region: str, path: str, body):
        async with self.locks[region]:
            page = await self.page_for(region)
            request = {"method": "GET" if body is None else "POST", "path": path, "body": body}
            try:
                result = await page.evaluate(CAPTURE_JS, request)
            except Exception:
                # Page navigated or crashed: reload once and retry.
                log.exception("signing failed, reloading page")
                self.pages.pop(region, None)
                await page.context.close()
                page = await self.page_for(region)
                result = await page.evaluate(CAPTURE_JS, request)

            cookies = {
                c["name"]: c["value"]
                for c in await page.context.cookies()
                if c["name"] in DEVICE_COOKIES
            }
            user_agent = await page.evaluate("navigator.userAgent")

        signed = urlsplit(result["url"])
        signed_path = signed.path + (f"?{signed.query}" if signed.query else "")
        return {
            "path": signed_path or path,
            "headers": {
                k: v for k, v in result["headers"].items() if k.lower() not in SKIPPED_HEADERS
            },
            "cookies": cookies,
            "userAgent": user_agent,
        }


@web.middleware
async def auth_middleware(request: web.Request, handler):
    if TOKEN and request.headers.get("Authorization") != f"Bearer {TOKEN}":
        return web.json_response({"error": "unauthorized"}, status=401)
    return await handler(request)


async def handle_sign(request: web.Request) -> web.Response:
    try:
        payload = await request.json()
        region = payload.get("region", "international")
        path = payload["path"]
        body = payload.get("body")
    except (json.JSONDecodeError, KeyError):
        return web.json_response({"error": "expected {region, path, body}"}, status=400)
    if region not in ORIGINS:
        return web.json_response({"error": f"unknown region {region}"}, status=400)

    signer: Signer = request.app["signer"]
    try:
        result = await signer.sign(region, path, body)
    except Exception as exc:  # noqa: BLE001
        log.exception("sign error")
        return web.json_response({"error": str(exc)}, status=502)
    log.info("signed %s %s", region, path)
    return web.json_response(result)


async def handle_health(_: web.Request) -> web.Response:
    return web.json_response({"ok": True})


async def main():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    async with async_playwright() as pw:
        browser = await pw.chromium.launch(headless=HEADLESS)
        app = web.Application(middlewares=[auth_middleware])
        app["signer"] = Signer(browser)
        app.router.add_post("/sign", handle_sign)
        app.router.add_get("/health", handle_health)

        runner = web.AppRunner(app)
        await runner.setup()
        await web.TCPSite(runner, HOST, PORT).start()
        log.info("signer listening on http://%s:%d (token %s)", HOST, PORT, "on" if TOKEN else "off")
        await asyncio.Event().wait()


if __name__ == "__main__":
    asyncio.run(main())
