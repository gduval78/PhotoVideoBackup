# 2.8.0 — pCloud destination (planned)

Status: **spec only, nothing implemented** (2026-11-19). Sits with WebDAV and S3 in the 2.8.0 "remote destinations" wave. Same rule as ever: iOS and Android carry the same features under the same number.

Goal: a profile destination `.pcloud` so a user can back up to their pCloud account (US or EU data centre) from the iPhone — no desktop app, no mounted drive. **Pro**, like the NAS.

## What was learned (docs.pcloud.com, 2026-11-19 — to be re-checked against a real account)

| Topic | Finding |
|---|---|
| Regions | Two data centres: `api.pcloud.com` (US, `locationid` 1) and `eapi.pcloud.com` (EU, `locationid` 2). The account's region decides; every call must go to that host. OAuth returns `hostname` + `locationid`. |
| Auth | OAuth 2.0 at `https://my.pcloud.com/oauth2/authorize`, `response_type=token` (client-side apps, token returned in the URI fragment, no secret) or `code` (needs `oauth2_token` + client secret — never ship a secret in the app). Docs state tokens **do not expire** "with the current implementation". Only permission option: `manageshares`; **no app-folder scope documented** (full account access). |
| **Registration risk** | A `client_id` is required. A third-party page says **creating new apps is currently disabled**, and one rclone thread (Oct 2026) shows a client id briefly rejected. **Unconfirmed — first thing to check** in the pCloud account (My Apps). If we cannot register an app, the API route is blocked and WebDAV becomes the only way. |
| Addressing | By folder/file **id** (root = 0, 64-bit ids), paths discouraged. A folder tree needs `createfolder` per level and id lookups; a path → id cache per run is required. |
| Upload | `uploadfile`: HTTP `POST multipart` or `PUT` body, `filename`, `folderid`, `mtime` (sets modification time), `nopartial` (do not keep a broken upload), `renameifexists` (else **overwrites**). Streaming PUT works from a file. A resumable flow (`upload_create` / `upload_write` / `upload_save`) exists in pCloud's SDKs but **was not found in the pages read** — verify before relying on it. |
| Checksum | `checksumfile` returns **sha1 everywhere, md5 on US only, sha256 on EU only**. So server-side verification is SHA-256 on EU accounts, SHA-1 on US ones, without re-downloading the file. |
| Download | `getfilelink` → host list + path + expiry; then a plain HTTPS GET (Range support to confirm). |
| Listing | `listfolder` (`folderid`, `recursive`, `nofiles`) → name, size, modified, isfolder, fileid/folderid. |
| WebDAV | `webdav.pcloud.com` (US) / `ewebdav.pcloud.com` (EU), port 443, **account email + password**. pCloud's own help page says WebDAV is **not suited to large backups** and can break on big transfers; 2FA is documented as an email confirmation but users report it failing; some reports say free accounts lost WebDAV; Crypto Folder is not reachable. |

## API or WebDAV — recommendation

**Build the API target first (`PCloudTarget`), keep WebDAV as the generic server target** that already exists in the 2.8.0 plan (`WebDAVTarget`); a user can still point it at pCloud, documented as "works, slower, not for big files".

Why API first:
- **No password in the app**: OAuth token in the Keychain; WebDAV needs the account password (and 2FA gets awkward).
- **Verification without re-download**: `checksumfile` answers with the hash (SHA-256 on EU). WebDAV verification would re-download every file, which pCloud itself says is fragile on large transfers.
- **Reliability on large files**: designed API, not an interoperability layer.
- **Modification date** via `mtime`; **never overwrite** via the name chain + `renameifexists` unset check.

Why WebDAV stays: it costs nothing extra (shared with Nextcloud work), covers the case where app registration is closed, and is the only route if pCloud refuses new OAuth apps.

**Decision point (do this first, before any code):** try to register an app in the pCloud account. If registration is open → API target, WebDAV generic. If closed → WebDAV only for pCloud, and say so in the guide.

## Mapping to `BackupTarget`

| Need | pCloud API |
|---|---|
| `rootIdentifier` | `pcloud://<region>/<uid>/<base path>` |
| `existingSize(forRelative:)`, `size(atAbsolutePath:)` | resolve parent id (cached), `stat`/`listfolder` → size; absent ⇒ nil |
| `isReachable()` | cheap call (`userinfo`) with short timeout; 401/`2094` ⇒ token revoked → surface "reconnect", never "empty" |
| directories | `createfolderifnotexists` per level; cache `path → folderid` for the run |
| `upload(localFile:toRelative:onProgress:)` | streaming `PUT`/`POST` from the file with `filename`, `folderid`, `mtime`, `nopartial=1`; check the name is free just before (the chain `name`, `name-1`… stays) |
| `sha256(forRelative:)` | `checksumfile` → `sha256` (EU). US: SHA-1 returned — compare it with a SHA-1 computed while hashing the source (two digests in one pass) |
| `readSmallFile` / `writeSmallFile` (sidecar) | `getfilelink` + GET / `uploadfile` (the sidecar is the only file allowed to be replaced) |
| Browse | `listfolder`; thumbnails/viewer by on-demand download like the NAS |
| delete | `deletefile` |

Everything above `BackupTarget` — `resolveCoverage`, the ledger, `.pvb-index.json`, deterministic names, `isPath`, naming profile — is **unchanged**.

## Design points

1. **Sign-in**: `ASWebAuthenticationSession` with `response_type=token`; token + `hostname` + `uid` stored in the Keychain (`profile.<uuid>.pcloud`). Redirect URI is mandatory for the token flow — check whether pCloud accepts a custom scheme (`photovideobackup://`) or only https (then a small redirect page on the GitHub Pages site would catch the fragment and bounce to the app).
2. **Verification wording**: Report says "verified by SHA-256" (EU) or "verified by SHA-1" (US) — never claim SHA-256 when it was SHA-1. The *identity* of the source in the ledger stays SHA-256.
3. **Large files**: confirm whether one streamed `PUT` of a multi-GB video is reliable; if not, use the resumable flow (if it exists) with the same resume-by-id idea as the Nextcloud chunking. No whole-file in RAM.
4. **Rate limits** are not documented: stop on repeated errors like the other targets, `.partial` with `destinationError`.
5. **Quota**: pCloud free accounts are small (10 GB); a full account should stop the run like iCloud's `-1003` (find the error code, probably `2008`) — reuse `PartialReason`.
6. **Offline ≠ empty**: unreachable or revoked token never prunes the ledger.
7. **Cellular** warning banner as for the NAS.
8. **Privacy**: network to pCloud only; update the policy and the App Privacy answers (third-party API, no data collected by us).
9. **Pro gate** where the NAS is enforced (`ProfileDetailView.requirePro` and run time).
10. **Crypto Folder** (pCloud's client-side encrypted area) is not reachable by API or WebDAV — say so in the guide.

## Work list

iOS
- `Modules/Targets/PCloudTarget.swift` (+ `PCloudClient`: region host, token, `createfolderifnotexists`, `uploadfile`, `checksumfile`, `listfolder`, `getfilelink`, `deletefile`, error codes), register in `project.pbxproj`.
- `ProfileDestination.pcloud(PCloudConfig)` (region, uid, base folder; token in Keychain) — optional field, no migration.
- Sign-in sheet (`ASWebAuthenticationSession`), `ProfilePCloudEditor` (account, base folder picker via `listfolder`, *Test connection* = write/read/delete a small file), New backup templates, Browse section.
- Engines: remote like SMB (NAS-only run stages; local + pCloud uploads from the copy on the drive).
- Tests: `FakePCloudServer` (`URLProtocol`) for the JSON methods; path → id cache; name chain when the name is taken; SHA-1/SHA-256 verification by region; revoked token ⇒ offline, ledger untouched; error-code mapping. Live test `make test-pcloud` with a throwaway account (config gitignored like `nas-test-config.json`, simulator).
- Localization (13 languages), guide (setup page: sign-in, region, free-plan limits, Crypto Folder, WebDAV alternative), privacy policy, `support/knowledge.md`, changelog, screenshots + `manifest.json`.

Android: `PCloudTarget` with OkHttp, JSON parsing and region/id logic in `core` (pure Kotlin, JVM tests), Custom Tabs sign-in, `SecretStore` for the token, strings via `gen_android_strings.py`.

## Open questions

1. ~~Can a new pCloud app be registered today?~~ **Yes** (2026-11-19: the *New app* button exists in My Apps) → API target first, WebDAV generic.
2. Does the token flow accept a custom-scheme redirect?
3. Is a single streamed upload of 4 GB reliable, and is there a resumable API?
4. Exact error code for a full account, and for a revoked token.
5. Range support on download links (needed for video preview in Browse).
6. Is the user's account US or EU (decides SHA-1 vs SHA-256 verification in the field test)?

## Not in scope

Crypto Folder, sharing links, pCloud Photos/Backup features, public folder links, Business-team folders, scheduling.


## Update 2026-11-19 — what the API token really sees

The registered app is an **application-folder app**: its token is confined to `/Applications/PhotoVideoBackup` in the user's pCloud, and *that folder is the root* (`/` for the token; `/Applications` does not exist for it). Consequences: the API destination writes there, **not** next to the user's WebDAV backups at the account root; the first API run re-copies what WebDAV already holds (separate sidecar index). Safer (no access to the rest of the account), but a different place. The earlier note "no app-folder scope" was wrong for this app. Changing the access type of the app at pCloud (My Apps) would be needed to share the WebDAV location.
