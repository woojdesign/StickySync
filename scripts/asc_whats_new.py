#!/usr/bin/env python3
"""Set "What to Test" on a TestFlight build via the App Store Connect API.

Polls until the build finishes processing (state VALID), then upserts the
en-US betaBuildLocalization with the contents of --notes-file.

One-time setup (in App Store Connect → Users and Access → Integrations →
App Store Connect API):
  • Create a Team Key. Save the Issuer ID, Key ID, and the .p8 file.
  • Export in your shell rc:
      export ASC_KEY_ID=ABCD123456
      export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
      export ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_ABCD123456.p8
  • pip install PyJWT cryptography requests
"""
from __future__ import annotations

import argparse
import os
import sys
import time
from pathlib import Path

try:
    import jwt  # PyJWT
    import requests
except ImportError as e:
    sys.exit(f"missing dependency: {e}. Run: pip install PyJWT cryptography requests")

API = "https://api.appstoreconnect.apple.com/v1"
WHATS_NEW_LIMIT = 4000
PROCESS_TIMEOUT_S = 30 * 60
POLL_S = 30

# App Store Connect's `whatsNew` field rejects a handful of Unicode characters
# with `ENTITY_ERROR.ATTRIBUTE.INVALID.INVALID_TEXT`. Apple doesn't publish the
# full list, so this map grows by trial and error. Each entry replaces a known-
# rejected character with a safe ASCII equivalent that reads naturally.
WHATS_NEW_REPLACEMENTS = {
    "☐": "[ ]",   # ☐  ballot box           (rejected 2026-06-23)
    "☑": "[x]",   # ☑  ballot box with check (rejected 2026-06-23)
    "☒": "[x]",   # ☒  ballot box with X
    "✓": "v",     # ✓  check mark
    "✔": "v",     # ✔  heavy check mark
    "✗": "x",     # ✗  ballot X
    "✘": "x",     # ✘  heavy ballot X
}


def sanitize_whats_new(text: str) -> str:
    """Replace characters known to be rejected by ASC's whatsNew validator."""
    out = text
    replaced: list[str] = []
    for src, dst in WHATS_NEW_REPLACEMENTS.items():
        if src in out:
            out = out.replace(src, dst)
            replaced.append(src)
    if replaced:
        print(f"   sanitized whatsNew: replaced {replaced}")
    return out


def _required_env(name: str) -> str:
    v = os.environ.get(name)
    if not v:
        sys.exit(f"env var {name} not set")
    return v


KEY_ID = _required_env("ASC_KEY_ID")
ISSUER_ID = _required_env("ASC_ISSUER_ID")
KEY_PATH = Path(os.path.expanduser(_required_env("ASC_KEY_PATH")))
if not KEY_PATH.is_file():
    sys.exit(f"ASC_KEY_PATH not found: {KEY_PATH}")
KEY_PEM = KEY_PATH.read_text()


def token() -> str:
    return jwt.encode(
        {"iss": ISSUER_ID, "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
        KEY_PEM,
        algorithm="ES256",
        headers={"kid": KEY_ID, "typ": "JWT"},
    )


def api(method: str, path: str, **kw) -> dict:
    headers = kw.pop("headers", {})
    headers["Authorization"] = f"Bearer {token()}"
    if "json" in kw:
        headers.setdefault("Content-Type", "application/json")
    r = requests.request(method, f"{API}/{path}", headers=headers, timeout=30, **kw)
    if not r.ok:
        sys.exit(f"ASC {method} {path}: {r.status_code} {r.text}")
    return r.json() if r.text else {}


def find_app(bundle_id: str) -> str:
    j = api("GET", "apps", params={"filter[bundleId]": bundle_id})
    if not j.get("data"):
        sys.exit(f"No app found with bundle id {bundle_id}")
    return j["data"][0]["id"]


def find_build(app_id: str, version: str, build_str: str) -> str:
    deadline = time.time() + PROCESS_TIMEOUT_S
    last_state = None
    while time.time() < deadline:
        j = api("GET", "builds", params={
            "filter[app]": app_id,
            "filter[preReleaseVersion.version]": version,
            "filter[version]": build_str,
            "limit": 1,
        })
        data = j.get("data") or []
        if data:
            b = data[0]
            state = b["attributes"]["processingState"]
            if state != last_state:
                print(f"   build state: {state}")
                last_state = state
            if state == "VALID":
                return b["id"]
            if state in ("FAILED", "INVALID"):
                sys.exit(f"Build processing ended in state {state}")
        else:
            if last_state != "MISSING":
                print("   build not visible yet — App Store Connect is still ingesting.")
                last_state = "MISSING"
        time.sleep(POLL_S)
    sys.exit(f"Timed out after {PROCESS_TIMEOUT_S // 60} min waiting for processing")


def set_whats_new(build_id: str, notes: str) -> None:
    j = api("GET", f"builds/{build_id}/betaBuildLocalizations")
    existing = next((d for d in j.get("data", []) if d["attributes"]["locale"] == "en-US"), None)
    if existing:
        api("PATCH", f"betaBuildLocalizations/{existing['id']}", json={"data": {
            "type": "betaBuildLocalizations",
            "id": existing["id"],
            "attributes": {"whatsNew": notes},
        }})
    else:
        api("POST", "betaBuildLocalizations", json={"data": {
            "type": "betaBuildLocalizations",
            "attributes": {"locale": "en-US", "whatsNew": notes},
            "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
        }})


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--bundle-id", required=True)
    ap.add_argument("--version", required=True, help="Marketing version, e.g. 0.3.2")
    ap.add_argument("--build", required=True, help="Build number, e.g. 52")
    ap.add_argument("--notes-file", required=True)
    args = ap.parse_args()

    notes = Path(args.notes_file).read_text().strip()
    notes = sanitize_whats_new(notes)
    if len(notes) > WHATS_NEW_LIMIT:
        print(f"warn: notes are {len(notes)} chars, truncating to {WHATS_NEW_LIMIT}")
        notes = notes[:WHATS_NEW_LIMIT]

    print(f"==> Locating app {args.bundle_id}")
    app_id = find_app(args.bundle_id)
    print(f"==> Waiting for build {args.version} ({args.build}) to finish processing")
    build_id = find_build(app_id, args.version, args.build)
    print(f"==> Setting What to Test ({len(notes)} chars)")
    set_whats_new(build_id, notes)
    print("Done.")


if __name__ == "__main__":
    main()
