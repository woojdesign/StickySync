# StickySync share landing page

Static HTML page that intercepts share URLs before they hit Apple's generic
iCloud fallback. Designed for hosting at e.g. `share.wooj.design` or
`stickysync.wooj.design`.

## URL shape

```
https://share.wooj.design/?ck=<urlencoded-iCloud-share-URL>&from=<senderName>
```

- `ck` — the underlying `https://www.icloud.com/share/…` URL the OS needs to
  route into the installed StickySync app. Required for the "Already have
  StickySync? Open the sticky →" link to do anything.
- `from` — optional sender name. Trimmed to 40 chars and HTML-escaped on
  render. Personalizes the preview sticky from "Someone left you a sticky"
  to e.g. "Sean left you a sticky".

## What it does

1. **Renders a calm Wooj-styled landing page** so a recipient hitting the link
   without StickySync installed sees a real surface instead of macOS's
   misleading "you need a newer version" error.
2. **Detects platform** (`Macintosh` → Mac install, `iPhone/iPad/iPod` → iOS
   install, anything else → both). No analytics, no tracking; just one
   `navigator.userAgent` check.
3. **Hands off to the installed app** via the embedded `ck` URL once the
   recipient has installed StickySync.

Degrades gracefully without JavaScript — both install paths show, and the
sticky shows a generic "someone left you a sticky" rather than personalized.

## Deploy targets

Drop-in static, no build step. Any of these will work:

- **Cloudflare Pages** — point at this directory, deploy on push.
- **Vercel / Netlify** — same, static-site preset.
- **GitHub Pages** — would publish from this subdirectory; if Wooj already
  uses a Pages site for `wooj.design`, this could be a subdomain.

Once deployed, update the send-side code in StickySync to wrap share URLs:

```swift
let openURL = "https://share.wooj.design/?ck=\(share.url.absoluteString.urlEncoded)&from=\(senderName)"
```

Then `provider.registerObject(openURL as NSURL, …)` instead of the raw
`share.url` — so Messages / Mail send the Wooj URL, and the recipient lands
on this page if they don't have the app.

## Placeholders to fill in before launch

- The TestFlight URL on the iOS install button is currently
  `https://testflight.apple.com/join/REPLACE-WITH-PUBLIC-CODE`. You'll
  need to create a TestFlight **External Tester** public link in App Store
  Connect → TestFlight → External Testers → Builds → "Create Public Link",
  then replace the placeholder with the URL App Store Connect issues.

## Visual aesthetic

Wooj brand applied: warm off-white (`#F3EFE4`) ground, Charter serif
headlines, clay accent (`#C2674F`), butter-yellow sticky illustration with
a slight rotation. ~zero ceremony — the page is supposed to feel like a
note, not a marketing landing.
