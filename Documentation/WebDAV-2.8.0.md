# 2.8.0 — WebDAV destination (planned)

Status: **spec only, nothing implemented** (2026-11-17). Prerequisite: 2.7.0 (profiles) is released on both platforms. Born from an Android tester's report (2026-11): a USB-drive backup worked, several SMB NAS setups worked, a **Nextcloud** setup failed. Not a bug: Nextcloud does not speak SMB. The tester suggested WebDAV.

Goal: a profile destination `.webdav` next to `.folder`, `.nas` (SMB) and the planned `.s3`, so the app reaches **Nextcloud, ownCloud, Synology/QNAP WebDAV, Hetzner Storage Box** and any WebDAV server over **HTTPS on port 443** — behind a reverse proxy, **without a VPN** (SMB on port 445 must never be exposed to the Internet, and most ISPs block it). **Pro**, like the NAS.

Ships with S3 as "remote destinations" in 2.8.0 (shared work: HTTP target plumbing, certificate trust, editor shell, cellular warning). WebDAV has more demand than S3 among self-hosters; if only one fits, build WebDAV first. **Version rule:** iOS and Android carry the same features under the same number — both platforms, or neither.

## Why it fits

- `BackupTarget` / `RemoteBackupTarget` already abstract the destination: add `WebDAVTarget` beside `SMBTarget`. Dedup (`resolveCoverage`, ledger, `.pvb-index.json`, deterministic names) is **unchanged**.
- No third-party dependency: `URLSession` (iOS), OkHttp (Android; already in the Play Billing/Media3 graph or a few hundred KB). AMSMB2 and smbj are heavier.
- **Upload really streams from a file** (`URLSession.upload(for:fromFile:)`, OkHttp `RequestBody` from a stream): no whole-file-in-RAM problem as with AMSMB2. The Photos path still stages a NAS-only run on disk (the engine decides, as for SMB); a local+WebDAV run uploads from the copy on the external volume.
- Verification by **full re-download SHA-256**, exactly as for SMB (no server-side SHA-256 in WebDAV; Nextcloud's `OC-Checksum` is SHA-1/MD5/Adler32 — optional extra, never the identity).

## Protocol mapping

| Need (BackupTarget) | WebDAV |
|---|---|
| `existingSize(forRelative:)`, `size(atAbsolutePath:)` | `PROPFIND` `Depth: 0`, read `getcontentlength`; 404 ⇒ nil |
| `isReachable()` | `PROPFIND` (or `OPTIONS`) on the root, short timeout; auth failure ≠ unreachable (surface it) |
| directories | `MKCOL` one level at a time, remembered per run (like `SMBTarget`'s created-folder cache); 405 = exists |
| `upload(localFile:toRelative:onProgress:)` | `PUT` with `If-None-Match: *` (never overwrite a different file; 412 ⇒ next name in the chain); progress from the session delegate |
| `sha256(forRelative:)` | `GET`, hash while streaming, never held in memory |
| `readSmallFile` / `writeSmallFile` (sidecar) | `GET` / `PUT` (replace allowed for this one file) |
| Browse listing | `PROPFIND` `Depth: 1`, parse `<d:response>` (`displayname`, `resourcetype`, `getcontentlength`, `getlastmodified`) |
| delete (LUT cleanup, tests) | `DELETE` |
| modification date | Nextcloud/ownCloud: `X-OC-Mtime` header on `PUT`; generic servers: ignored (the capture date is already in the name) |

`rootIdentifier` = `webdav://host[:port]/<base path>`; `absolutePath(forRelative:)` builds on it. URL path components are percent-encoded **per component** (names contain spaces, `{device}` text, non-ASCII); never double-encode.

## Large files — the hard part

A single `PUT` of a 4 GB video behind a typical Nextcloud fails: PHP `upload_max_filesize` / `post_max_size`, nginx `client_max_body_size`, **Cloudflare's 100 MB request limit** (free/pro plans), proxy read timeouts. Standard WebDAV has **no resumable or chunked upload**.

Plan in two steps:

1. **2.8.0 step 1 — plain `PUT`.** Works for photos and short clips and for servers without such limits (Synology WebDAV Server, Hetzner Storage Box, a Nextcloud on LAN/VPN). A failure caused by size (HTTP 413, a connection reset at the proxy limit) is reported as **"the server refused this file size — check its upload limit"** (own string, 12 languages), not as a generic error, and the file is recorded failed so a re-run retries it.
2. **2.8.0 step 2 — Nextcloud chunked upload** (`remote.php/dav/uploads/<user>/<uuid>/` with `MKCOL`, numbered chunk `PUT`s, then `MOVE` to the final path with `OC-Total-Length`). Detected at *Test connection* from the server's capabilities (`/ocs/v1.php/cloud/capabilities` → `dav.chunking`), a capability, never a `if nextcloud`. Gives resume of an interrupted file (list the chunks already present) and passes proxy body limits. Abort = `DELETE` the upload folder (otherwise orphan chunks use quota). Chunk size 10 MB by default.

Decide the step-1/step-2 split after the tester answers: **file sizes (drone video?) and whether his Nextcloud is behind Cloudflare**.

## Design points

1. **Never overwrite a different file**: `If-None-Match: *` where honoured; where not (some servers ignore it), `PROPFIND` first, as the SMB target does. Keep the `name`, `name-1`… chain untouched.
2. **Offline ≠ empty.** An unreachable server (timeout, DNS, TLS error) marks the destination offline and **never** triggers ledger pruning (`stalePaths` only when reachable) — identical to SMB.
3. **Credentials**: server URL (`https://cloud.example.com/remote.php/dav/files/USER/` or any WebDAV root), user, password, base folder. The password goes to the Keychain (iOS: `profile.<uuid>.webdav`) / `SecretStore` (Android), like the NAS. **Nextcloud with 2FA needs an app password** (Settings → Security → Devices & sessions): say so in the editor footer and the guide. A 401 on *Test connection* shows "wrong credentials — with two-factor authentication use an app password".
4. **Nextcloud URL helper**: if the user enters only `https://cloud.example.com`, offer to complete it to `…/remote.php/dav/files/<user>/` (probe it at *Test connection*); keep a manual field for other servers.
5. **TLS**: HTTPS required by default. Plain HTTP only for private addresses (ATS `NSAllowsLocalNetworking`; Android `networkSecurityConfig` scoped to private ranges) with a visible warning. **Self-signed certificates**: at *Test connection*, show the certificate fingerprint and let the user accept and **pin** it (store the SHA-256 of the certificate, compare in the `URLSessionDelegate` / `X509TrustManager`); never a blanket "trust all". Shared with the S3/MinIO plan.
6. **Rate limits / brute-force protection**: Nextcloud throttles repeated failed logins per IP; stop the run on the first 401/403 instead of retrying every file. 429/503 with `Retry-After`: back off once, then stop as `.partial` with a clear reason (reuse `PartialReason.destinationError` unless a dedicated one is warranted).
7. **Cellular**: reuse the mobile-data warning banner (the destination is remote).
8. **Timeouts**: connect 15 s, per-request idle 60 s; no total timeout on `PUT`/`GET` of a file (progress-based).
9. **Background (iOS)**: `beginBackgroundTask` as today; background `URLSession` is not attempted.
10. **Pro gate**: WebDAV destination is Pro, enforced where the NAS is (`ProfileDetailView.requirePro` and at run time). Free = one profile with a folder or iCloud, unchanged.
11. **Report**: verification text "verified by SHA-256" as for SMB. If step 2 ships, nothing changes in the Report.
12. **Browse**: WebDAV destinations listed like `nasEntries`; identity = `scheme|host|port|basePath|user`. Thumbnails / viewer by on-demand download, like the NAS. LUT Grade on WebDAV: same download → grade → upload scheme as the NAS, **after** the target works (mirror `NASBrowserView`; remember it is a separate Browse path, not shared code). LUT assignment key `webdav:<id>:<subPath>` to avoid the known NAS key collision.

## Work list

iOS
- `Modules/Targets/WebDAVTarget.swift` (+ small PROPFIND XML parser via `XMLParser`), conforming to `RemoteBackupTarget`; register in `project.pbxproj`.
- `ProfileDestination.webdav(WebDAVConfig)` + `webdavPasswordAccount` (optional field, no migration); `WebDAVConfig` = url, user, basePath, pinned cert fingerprint, capability flags found at test time (chunking, mtime header).
- Editor `ProfileWebDAVEditor` modelled on `ProfileNASEditor` (+ *Test connection*: PROPFIND, write + read back + delete a small object, report TLS/auth/size-limit hints), New backup templates ("Photo library → WebDAV", "Drive → WebDAV"), Browse section.
- Engines: treat as remote (staging rule identical to SMB); `DiskSpacePreflight` unchanged.
- Tests: `FakeWebDAVServer` (in-process `URLProtocol` stub serving PROPFIND/MKCOL/PUT/GET/DELETE over a temp dir, with switches for 412, 413, 401, 429, ignored `If-None-Match`, slow/timeout) → `WebDAVTargetTests`; PROPFIND parser tests with real Nextcloud / Synology / Apache `mod_dav` / nginx-dav response samples (namespaces, encoded hrefs, `Depth` listing including the collection itself); URL encoding tests (spaces, accents, `#`, `%`, `+`); name-chain test on 412; unreachable ⇒ ledger untouched.
- Live integration test `make test-webdav` against a Nextcloud in Docker (`nextcloud` image) and a bare `dav` server (nginx-dav or `bytemark/webdav`), config file gitignored like `nas-test-config.json`; run on the iOS Simulator (same sandbox reason as `test-nas`). **Test behind a reverse proxy with a body-size limit** to reproduce the 413 case, and with a self-signed certificate.
- Localization (12 languages), user guide (12/8 as the site stands) with a **Nextcloud setup page** (app password, URL, proxy limits, Cloudflare note), privacy policy (network to the user's own server only), `support/knowledge.md`, changelog row, screenshots + `images/manifest.json`.

Android
- `WebDAVTarget` in `app` (OkHttp), PROPFIND parsing shared in `core` as pure Kotlin so the parser and URL-encoding tests run on the JVM (`gradle :core:test`); `BrowsableTarget.list` implementation; Pro gate in `BackupController.buildTargets`; `SecretStore` for the password; network security config for private HTTP + pinned certificate; strings via `gen_android_strings.py`. Same behaviour, same tests, same sidecar.

## Risks and unknowns

- **Server variance** (Nextcloud, ownCloud, Synology, Apache, nginx, Hetzner differ on `If-None-Match`, `MKCOL` on existing folders, `Depth: infinity`, percent-encoding, case sensitivity). Mitigation: capability probing at *Test connection*, real-server tests above; only list in the guide the servers actually tested.
- **Large files** (see above): the main cause of "does not work for me" reports; the 413 message and the guide must make it self-service.
- **Speed**: HTTP per-file overhead (PROPFIND + MKCOL + PUT + GET verify) makes a thousand small photos slower than SMB. Cache created folders and check existence with one `PROPFIND` per file; do not promise SMB-like speed. Measure a 1 GB file and 1000 × 3 MB photos over LAN and Tailscale before writing any claim.
- **Verification doubles the traffic** over cellular/WAN (re-download), as with SMB. Option, later: skip the re-download when the server returns a matching checksum header and say so in the Report ("verified by server checksum").
- Browse over WebDAV downloads on demand (no thumbnails for NAS-like targets), same limit as today.

## Questions for the tester (before building)

1. Typical file sizes (photos only, or drone/360 video of several GB)?
2. Nextcloud reverse proxy / Cloudflare in front? Self-signed or Let's Encrypt certificate?
3. 2FA enabled (app password)? Would he test a TestFlight/Play closed-test build against his instance?
4. Would he prefer WebDAV to SMB over Tailscale for this server once available, or only when no VPN is possible?

## Not in scope

Nextcloud-specific features beyond upload (sharing, Photos app integration, end-to-end encryption), WebDAV locking (`LOCK`/`UNLOCK`), CalDAV/CardDAV, OAuth/Login Flow v2 sign-in (app passwords only), server-side checksum as the dedup identity, background `URLSession` uploads, scheduling.
