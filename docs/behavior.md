# Function behavior and Fastly VCL mapping

[Back to README](../README.md) · [Try the behavior](testing.md)

The supplied `f_logo` VCL is a fallback renderer. It does not contain the original-logo lookup, the condition that calls `f_logo`, or a logging statement. This Function adds the explicit Blob lookup and structured logging needed for a standalone demonstration. We cannot infer every customer call site from that VCL alone.

| VCL behavior | Function implementation |
|---|---|
| `querystring.get(req.url,"explicit") == "true"` | Exact, case-sensitive query value comparison; `True` is not `true` |
| Extract the filename before `.svg` | Bounded safe symbol allowlist; original blob uses the same case-sensitive key |
| `std.toupper(...)` | Uppercase the symbol for display |
| `regsub(..., "^[A-Z]+:", "")` | Remove a generic letters-plus-colon prefix; no special `PC:` code |
| `substr(..., 0, 2)` | Display the first two characters |
| `synthetic` SVG and 200 | Same circle/initials visual structure, `image/svg+xml`, 200 |
| Explicit fallback sets 404 | Missing+explicit gives 404/no-store; original+explicit still gives original 200 |
| Three `fastly.hash` calls | Seeded SHA-256 with the same requested HSL ranges; deterministic, **not exact Fastly color parity** |

The customer snippet percent-encodes percent signs as `%25`; the Function returns valid inline SVG color percentages (`%`). Exact Fastly colors require a verified compatible hash/range implementation or a supplied palette. This repository intentionally avoids claiming exact color matches or adding an unverified hash emulation.

The filename validation is intentionally stricter than the VCL's broad regex. Symbols containing slashes, markup, percent-decoded separators, `..`, or more than 96 allowed characters are rejected; arbitrary external origin URLs are not accepted.

## Missing versus broken

Only a Blob `404` with `x-ms-error-code: BlobNotFound` counts as a missing original. A nonexistent container, Storage authorization failure, timeout, wrong MIME type or oversized image returns `502` with `no-store`. A Storage outage must not silently become a set of successful placeholders.

The lookup has an eight-second request timeout and 128 KiB response limit. Managed-identity tokens are cached until shortly before expiry. There are no third-party runtime dependencies. Original SVGs are trusted administrator-uploaded assets; this is not a public arbitrary-SVG upload service or an SVG sanitizer.

## Cache behavior

- Original SVG: `Cache-Control: public, max-age=300`.
- Generated SVG: `Cache-Control: public, max-age=60` so newly added originals appear after a short TTL.
- Explicit 404, invalid requests, health, demo HTML and errors: `no-store`.
- The optional Front Door route uses `UseQueryString`. A cached normal placeholder must never answer an `explicit=true` request.
- Review existing Front Door rule sets: do not discard `explicit`, normalize its value, cache `no-store`, or override these TTLs accidentally.

`X-Logo-Result` identifies `original`, `fallback`, `explicit-not-found`, or `origin-error`. A Front Door hit returns the cached result without invoking the Function. `X-Cache`/`Age` can help observe caching, but a single request or POP does not guarantee a HIT. To publish a replacement immediately, purge the relevant Front Door path; otherwise wait for the TTL. A new generated result is computed per miss and is not written back to Storage.

Structured Function events include `logo_origin_hit`, `logo_missing`, `logo_fallback_generated`, `logo_fallback_suppressed` and `logo_origin_error`. They record origin executions, not every end-user edge hit. `explicit=true` is a caller-controlled “original only” option, not an authentication or privacy control.
