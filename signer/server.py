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

Logging in goes through the web page's own login dialog, in a tab of the same browser:

    POST /login/start {"region": "china"}  -> {"id": "..."}
    POST /login/poll  {"id": "..."}
    -> {"status": "loading"|"waiting"|"scanned"|"confirmed"|"done"|"failed",
        "qrURL": "...", "site": "rednote.com", "error": "...",
        "cookies": {...}, "userAgent": "..."}

The TV draws `qrURL` (the link inside the page's QR code) and the phone scans it. When the
page has logged in, the poll answers "done" once, with the site's cookies (web_session
included); only the TV that started that login knows its id. `site` is where the page really
is: from outside mainland China, xiaohongshu.com redirects to rednote.com, and the status is
then "failed" with error "other_site", so the TV can say to switch region.

Each region's browser profile lives in `profiles/<region>`, so the device cookies survive
restarts. Delete `profiles/` to start over.

Usage:
    ./run.sh                       # listens on 0.0.0.0:8790
    SIGNER_TOKEN=secret ./run.sh   # require "Authorization: Bearer secret"
"""

import asyncio
import json
import logging
import os
import secrets
import time
from pathlib import Path
from typing import Optional
from urllib.parse import urlsplit

from aiohttp import web
from playwright.async_api import BrowserContext, Page, Playwright, Response, async_playwright

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
PROFILES = Path(__file__).parent / "profiles"

# A login nobody polls for this long is given up, and none lasts longer than LOGIN_LIFETIME.
LOGIN_IDLE = 60
LOGIN_LIFETIME = 10 * 60
# The web page's QR status codes.
QR_STATUSES = {0: "waiting", 1: "scanned", 2: "confirmed", 3: "expired"}

log = logging.getLogger("signer")


def base_domain(url: str) -> str:
    return ".".join((urlsplit(url).hostname or "").split(".")[-2:])


class Login:
    """One run of the web page's QR login dialog."""

    def __init__(self, region: str):
        self.id = secrets.token_urlsafe(16)
        self.region = region
        self.page: Optional[Page] = None
        self.task: Optional[asyncio.Task] = None
        self.status = "loading"
        self.qr_url: Optional[str] = None
        self.site: Optional[str] = None
        self.error: Optional[str] = None
        self.cookies: Optional[dict] = None
        self.user_agent: Optional[str] = None
        self.last_poll = time.monotonic()
        # Set when the page's own user/me call says the account is logged in.
        self.logged_in = False

    def snapshot(self) -> dict:
        result = {"status": self.status, "qrURL": self.qr_url, "site": self.site, "error": self.error}
        if self.status == "done":
            result.update(cookies=self.cookies, userAgent=self.user_agent)
        return result

    async def on_request_failed(self, request):
        if self.status in ("scanned", "confirmed"):
            log.info("%s login: request failed %s %s", self.region, urlsplit(request.url).path, request.failure)

    async def on_response(self, response: Response):
        url = response.url
        path = urlsplit(url).path
        if self.status in ("scanned", "confirmed") and "/api/" in url and "qrcode/userinfo" not in url:
            # After the scan, note every API call the page makes, to see where a login stops.
            log.info("%s login: after scan %s -> HTTP %d", self.region, path, response.status)
        if "/api/" not in url or not any(k in url for k in ("login", "qrcode", "user/me")):
            return
        try:
            body = await response.json()
        except Exception:  # noqa: BLE001 - a body we can't read just isn't a status update
            log.info("%s login: %s -> HTTP %d", self.region, path, response.status)
            return
        data = body.get("data") or {}
        if "/login/qrcode/create" in url:
            if data.get("url"):
                self.qr_url = data["url"]
                self.set_status("waiting")
        elif "/api/qrcode/userinfo" in url:
            code = data.get("codeStatus")
            if code not in (0, None) or self.status not in ("waiting", "loading"):
                log.info("%s login: codeStatus %s", self.region, code)
            status = QR_STATUSES.get(code)
            if status:
                self.set_status(status)
        elif "/user/me" in url:
            # The page checks who's logged in after the scan; not a guest means done.
            if data.get("guest") is False:
                self.logged_in = True
            log.info("%s login: user/me guest=%s", self.region, data.get("guest"))
        else:
            # Codes and messages only; no cookies or tokens.
            log.info("%s login: %s -> code %s %s", self.region, path, body.get("code"), body.get("msg"))

    def set_status(self, status: str):
        if self.status != status and self.status != "done":
            log.info("%s login: %s", self.region, status)
            self.status = status


class Signer:
    def __init__(self, playwright: Playwright):
        self.playwright = playwright
        self.contexts: dict = {}
        self.pages: dict = {}
        self.logins: dict = {}
        self.locks = {r: asyncio.Lock() for r in ORIGINS}

    async def context_for(self, region: str) -> BrowserContext:
        context = self.contexts.get(region)
        if context:
            return context
        profile = PROFILES / region
        profile.mkdir(parents=True, exist_ok=True)
        context = await self.playwright.chromium.launch_persistent_context(
            profile, headless=HEADLESS, locale="zh-CN"
        )
        context.on("close", lambda _: self.forget(region, context))
        self.contexts[region] = context
        return context

    def forget(self, region: str, context: BrowserContext):
        if self.contexts.get(region) is context:
            self.contexts.pop(region, None)
            self.pages.pop(region, None)

    async def page_for(self, region: str) -> Page:
        """The tab used for signing, kept apart from login tabs."""
        page = self.pages.get(region)
        if page and not page.is_closed():
            return page
        context = await self.context_for(region)
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
                # Page navigated or crashed: open a fresh signing tab once and retry.
                log.exception("signing failed, reloading page")
                self.pages.pop(region, None)
                if not page.is_closed():
                    await page.close()
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

    # MARK: Login

    async def start_login(self, region: str) -> Login:
        # One login per region at a time; a new one replaces the old.
        for old in [l for l in self.logins.values() if l.region == region]:
            await self.end_login(old)
        login = Login(region)
        async with self.locks[region]:
            context = await self.context_for(region)
            # Log the browser out first, so the dialog always asks for a fresh scan and
            # nobody can collect an earlier login.
            await context.clear_cookies(name="web_session")
            login.page = await context.new_page()
        login.page.on("response", login.on_response)
        login.page.on("requestfailed", login.on_request_failed)
        login.page.on("framenavigated", lambda frame: frame == login.page.main_frame
                      and log.info("%s login: page now at %s", region, urlsplit(frame.url).path))
        self.logins[login.id] = login
        login.task = asyncio.create_task(self.run_login(login))
        log.info("%s login started", region)
        return login

    async def open_dialog(self, login: Login):
        page = login.page
        await page.goto(ORIGINS[login.region], wait_until="domcontentloaded")
        await page.wait_for_function("typeof window._webmsxyw === 'function'", timeout=30_000)
        login.site = base_domain(page.url)
        if login.site != base_domain(ORIGINS[login.region]):
            raise LoginFailed("other_site")
        # Turn down the optional cookies if the site asks (it does in the EU).
        decline = page.locator(".cookie-banner__btn--secondary")
        try:
            await decline.click(timeout=3_000)
        except Exception:  # noqa: BLE001 - no banner
            pass
        qr = page.locator(".qrcode-img")
        if not await qr.is_visible():
            await page.locator(".login-btn").first.click(timeout=15_000)
        await qr.wait_for(timeout=15_000)

    async def run_login(self, login: Login):
        started = time.monotonic()
        try:
            await self.open_dialog(login)
            context = login.page.context
            guest = await self.session_cookie(context)
            confirmed_at = None
            while True:
                await asyncio.sleep(1)
                now = time.monotonic()
                if now - login.last_poll > LOGIN_IDLE or now - started > LOGIN_LIFETIME:
                    log.info("%s login abandoned", login.region)
                    await self.end_login(login)
                    return
                if login.status == "expired":
                    login.status, login.qr_url = "loading", None
                    await self.open_dialog(login)
                    guest = await self.session_cookie(context)
                    continue
                if login.status == "confirmed":
                    confirmed_at = confirmed_at or now
                    if now - confirmed_at > 5 and not getattr(login, "shot", False):
                        login.shot = True
                        shot = PROFILES / f"{login.region}-login.png"
                        try:
                            await login.page.screenshot(path=str(shot), timeout=5_000)
                            log.info("%s login: confirmed but not logged in yet; page saved to %s",
                                     login.region, shot)
                        except Exception:  # noqa: BLE001 - a stuck page can't be drawn
                            log.info("%s login: confirmed but not logged in yet; page not responding",
                                     login.region)
                session = await self.session_cookie(context)
                # Done when the page says it's logged in, or a new session arrived after the
                # phone confirmed. The page may also skip straight past "confirmed".
                new_session = bool(session) and session != guest
                if login.logged_in or (new_session and login.status in ("scanned", "confirmed")):
                    site = login.site
                    login.cookies = {
                        c["name"]: c["value"]
                        for c in await context.cookies()
                        if c["domain"].lstrip(".") == site or c["domain"].endswith("." + site)
                    }
                    login.user_agent = await login.page.evaluate("navigator.userAgent")
                    login.status = "done"
                    log.info("%s login done", login.region)  # never log the cookies
                    await login.page.close()
                    return
        except LoginFailed as failure:
            login.status, login.error = "failed", str(failure)
        except asyncio.CancelledError:
            raise
        except Exception as exc:  # noqa: BLE001
            log.exception("%s login failed", login.region)
            login.status, login.error = "failed", str(exc)
        if login.page and not login.page.is_closed():
            await login.page.close()

    @staticmethod
    async def session_cookie(context: BrowserContext) -> Optional[str]:
        return next((c["value"] for c in await context.cookies() if c["name"] == "web_session"), None)

    def poll_login(self, login_id: str) -> Optional[dict]:
        login = self.logins.get(login_id)
        if not login:
            return None
        login.last_poll = time.monotonic()
        result = login.snapshot()
        if login.status in ("done", "failed"):
            # The cookies go out once.
            self.logins.pop(login.id, None)
        return result

    async def end_login(self, login: Login):
        self.logins.pop(login.id, None)
        if login.task and not login.task.done() and login.task is not asyncio.current_task():
            login.task.cancel()
        if login.page and not login.page.is_closed():
            await login.page.close()


class LoginFailed(Exception):
    pass


@web.middleware
async def auth_middleware(request: web.Request, handler):
    if TOKEN and request.headers.get("Authorization") != f"Bearer {TOKEN}":
        return web.json_response({"error": "unauthorized"}, status=401)
    return await handler(request)


async def read_json(request: web.Request) -> dict:
    try:
        payload = await request.json()
    except json.JSONDecodeError:
        return {}
    return payload if isinstance(payload, dict) else {}


async def handle_sign(request: web.Request) -> web.Response:
    payload = await read_json(request)
    region = payload.get("region", "international")
    path = payload.get("path")
    body = payload.get("body")
    if not path:
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


async def handle_login_start(request: web.Request) -> web.Response:
    region = (await read_json(request)).get("region")
    if region not in ORIGINS:
        return web.json_response({"error": "expected {region}"}, status=400)
    signer: Signer = request.app["signer"]
    try:
        login = await signer.start_login(region)
    except Exception as exc:  # noqa: BLE001
        log.exception("login start error")
        return web.json_response({"error": str(exc)}, status=502)
    return web.json_response({"id": login.id})


async def handle_login_poll(request: web.Request) -> web.Response:
    login_id = (await read_json(request)).get("id")
    signer: Signer = request.app["signer"]
    result = signer.poll_login(login_id) if isinstance(login_id, str) else None
    if result is None:
        return web.json_response({"error": "unknown login"}, status=404)
    return web.json_response(result)


async def handle_health(_: web.Request) -> web.Response:
    return web.json_response({"ok": True})


async def main():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    async with async_playwright() as pw:
        app = web.Application(middlewares=[auth_middleware])
        app["signer"] = Signer(pw)
        app.router.add_post("/sign", handle_sign)
        app.router.add_post("/login/start", handle_login_start)
        app.router.add_post("/login/poll", handle_login_poll)
        app.router.add_get("/health", handle_health)

        runner = web.AppRunner(app)
        await runner.setup()
        await web.TCPSite(runner, HOST, PORT).start()
        log.info("signer listening on http://%s:%d (token %s)", HOST, PORT, "on" if TOKEN else "off")
        await asyncio.Event().wait()


if __name__ == "__main__":
    asyncio.run(main())
