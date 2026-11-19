# Destinations: one "Server" kind with a typed connection (study, 2026-11-19)

Status: **study only, nothing implemented.** Born from the 2.8.0 WebDAV work: after folders and cloud folders were merged (iCloud Drive / Google Drive are detected from the folder), the app now has three destination words (folder, NAS, WebDAV server), eight "New backup" templates, and more to come (pCloud API, S3). Users will get lost, and every new protocol multiplies screens, templates, guide text and translations.

## Today (iOS, measured)

- `ProfileDestination` = `.folder`, `.nas`, `.webdav`; the profile carries one optional config per kind (`nas`, `webdav`) and one Keychain account per kind (`nasPasswordAccount`, `webdavPasswordAccount`). A profile can hold at most one NAS and one WebDAV server.
- 8 selectable templates (`photosToDrive`, `photosToNAS`, `photosToWebDAV`, `photosToDriveAndNAS`, `cameraToDrive`, `cameraToNAS`, `cameraToWebDAV`, `cameraToDriveAndNAS`); S3 and pCloud would add 4 more each. The template is source × destination written out by hand.
- The kind leaks everywhere: `usesNAS` / `usesWebDAV` (25 hits, 6 files), `NASConfig` (39 hits, 10 files), `includesNAS` / `includesWebDAV`, `SMBTarget` (25 hits, 7 files), two editors (`ProfileNASEditor`, `ProfileWebDAVEditor`), two Browse views (`NASBrowserView` with LUT Grade, `WebDAVBrowserView` without), two Browse entry lists, two branches in `runProfile`, `resolvedTargets`, `connection(of:)`, the run summary, the card badge.
- What is **already common**: the engines only see `BackupTarget` / `RemoteBackupTarget`; dedup, ledger, sidecar, naming and verification do not know the protocol. Android has the same shape (`ProfileTemplate` with `*_TO_NAS`, `BackupProfile.nas: NasConfig?`, `usesNas`).

## Scope clarified (user, 2026-11-19)

What changes for the user is **editing and creating a profile**. Once a destination is a typed connection, the app already has everything it needs to open the link: the type says which target to build, the fields give the address and options, the Keychain account gives the secret. So **nothing downstream asks the user anything kind-specific**: run, reachability, run summary, card, Browse and Pro gate all work from the typed connection (the engines already see only `BackupTarget`). The visible work is therefore one thing — **one profile editor** that adds a destination as *Folder* or *Server*, shows the fields of the chosen type, and tests the link — plus the plumbing that lets everything else read the typed connection instead of branching on `.nas` / `.webdav`.

## Proposal

### What the user sees: two kinds, one word each

| Kind | What it is | Examples |
|---|---|---|
| **Folder** | anything the system file picker gives | external SSD, USB drive, phone storage, iCloud Drive, Google Drive / OneDrive / Dropbox (detected from the folder — already done) |
| **Server** | reached by an address and an account | NAS (SMB), Nextcloud / ownCloud / WebDAV, pCloud, S3-compatible storage — *the protocol is a choice inside "Server", not a new concept* |

- **A backup = a source + a list of destinations.** "New backup": step 1, *what to back up* (Photo library / Camera or SD card); step 2, *where to* — add one or several destinations, each a **Folder** or a **Server**. The eight templates disappear as a concept (the stored `template` stays only to read old profiles); there is nothing to add for S3 or pCloud.
- **Adding a Server** opens one list, with a plain-language line for each type:
  - *NAS (Synology, QNAP…)* — "on your home network or through a VPN" (SMB)
  - *Nextcloud, ownCloud or WebDAV server* — "over the Internet, from anywhere" (WebDAV)
  - *pCloud* — preset of WebDAV today (address pre-filled by region), a dedicated API connection later; the user keeps picking "pCloud"
  - *S3-compatible storage* — later
  The user picks by what they own, not by protocol name. A **preset** (pCloud, Hetzner Storage Box…) is only a pre-filled connection, never a new type.
- Where the protocol still matters, it is a hint and a guide paragraph, not a concept: SMB works on the local network or a VPN only; WebDAV/pCloud/S3 work anywhere but have upload size limits.
- The run summary, the card, the badge (Wi-Fi / mobile data), Browse and the Pro gate treat every Server alike (Pro, like the NAS today).

### What the code stores: a typed connection

```json
{ "kind": "folder", "bookmarkKey": "PhotoVideoBackup.profile.<uuid>.0" }

{ "kind": "server", "id": "<uuid>", "passwordAccount": "profile.<uuid>.server.<id>",
  "connection": { "type": "smb",    "host": "192.168.1.20", "port": 445, "share": "photo",
                  "basePath": "Backups", "username": "me", "displayName": "Synology" } }

{ "kind": "server", "id": "<uuid>", "passwordAccount": "…",
  "connection": { "type": "webdav", "serverURL": "https://cloud.example.com/remote.php/dav/files/me/",
                  "basePath": "Backups", "username": "me", "pinnedCertificate": "…", "chunking": true } }

{ "connection": { "type": "pcloud", "region": "eu", "userId": 123, "basePath": "Backups" } }     // later
{ "connection": { "type": "s3", "endpoint": "…", "region": "…", "bucket": "…", "prefix": "…", "accessKeyId": "…" } }  // later
```

- Swift: `enum ServerConnection: Codable { case smb(NASConfig), webdav(WebDAVConfig), unknown(Data) }` with a custom coder on the `type` discriminator. **An unknown type is kept byte for byte** (`unknown`) and written back untouched — the same tolerance as the profile list (`loadTolerant`): a profile written by a newer build never disappears. Kotlin: a sealed class with `kotlinx.serialization` polymorphism on `"type"`, same JSON, so the profile and the sidecar logic stay interchangeable.
- **Secrets never live in the JSON**: the destination carries the Keychain / Keystore *account* name. Existing accounts (`profile.<uuid>.nas`, `.webdav`) are simply stored in `passwordAccount`: no password migration.
- A destination has its **own id**, so a profile can hold several servers (today: at most one NAS and one WebDAV). Browse identifies a server by its connection (`identity`: type + address + folder + user), as `nasEntries` / `webdavEntries` do now.

### One protocol in the code, one editor, one Browse

- **A registry per server type** — everything the app needs to know about a type, in one place: title, symbol, one-line description, `isComplete`, `label`, `identity`, `makeTarget(password:) -> ServerTarget`, `testConnection()`, the editor section. Adding S3 = a config struct + a target + an editor section + a registry entry; no template, no `if kind ==` in the run path, the cards, Browse or the summary.
- **`BrowsableTarget`** (list, download, delete, existingSize, upload) and **one `RemoteEntry`** replace `SMBTarget.Entry` / `WebDAVTarget.Entry`; `SMBTarget` and `WebDAVTarget` conform. A single `RemoteBrowserView` replaces `NASBrowserView` and `WebDAVBrowserView`, and **LUT Grade works on every server for free** (it only needs download, upload, existingSize, list — all in the protocol).
- `ProfileRun` carries `servers: [(ServerConnection, password)]`; `resolvedTargets`, `connection(of:)`, the summary and the card iterate the destinations.
- **One `ServerEditor`**: a type picker, then the section of the chosen type (today's NAS and WebDAV forms become two sections of it, with *Test connection* shared).

### Compatibility and migration

- On load, `.nas` + `nas` and `.webdav` + `webdav` are read as `.server(…)`; the new shape is written. Test fixtures: real 2.7.0 / 2.7.1 profile JSON (NAS, folder, mixed) must load and run unchanged.
- **Downgrade**: a build older than this one will not read the new shape; the tolerant read sets such profiles aside and writes them back untouched, so reinstalling the newer build restores them. Acceptable for a version upgrade (state it in the changelog).
- LUT assignments keyed `nas:<subPath>` keep working for SMB servers (legacy prefix); new keys include the server id (this also removes the known "two NAS with the same sub-path share an assignment" limit).
- The global NAS of the former Advanced tab stays as migration data only, as today.

### Android

Same model (the Kotlin profile is already template-driven with a `nas` field): do the unification **before** adding WebDAV, pCloud and S3 there, so each is born as a `ServerConnection` type instead of another special case. The guide's iPhone/Android parity rule (same features under the same number) argues for one common JSON.

## Plan

1. **Model and plumbing, no visible change (iOS).** `ServerConnection` + `ProfileDestination.server` + legacy decode, `BrowsableTarget` / `RemoteEntry`, `ProfileRun.servers`, registry, Browse entries by connection, `connection(of:)`, summary. Tests: fixtures of old profiles, round trip, unknown type preserved, NAS and WebDAV behaviour unchanged (existing suites + `make test-webdav` + a NAS run on the device).
2. **UI.** New wizard (source, then destinations), *Add a destination → Folder / Server*, `ServerEditor` with the type list and presets, one `RemoteBrowserView` (with LUT Grade), templates removed from the list; strings (new, and the 8 template strings retired) in 13 languages.
3. **Guide and docs (13 languages).** One section "Back up to a server" with a short block per type (NAS / Nextcloud & WebDAV / pCloud), the "which one do I pick?" hint, FAQ; privacy policy and support notes already name servers generically.
4. **Android**: same model in `core` (pure Kotlin, JVM tests), then WebDAV there.
5. Then, each new protocol (pCloud API, S3) is small: config + target + editor section + tests.

Effort: phases 1 and 2 are each about the size of the WebDAV integration (one long session each); phase 3 is a re-write of the sections already added; Android is separate.

## Decisions needed

1. **Wording**: "Server" (recommended) vs "Network" vs "Network drive". A NAS is a server; so is Nextcloud; "network" suggests Wi-Fi only.
2. **Templates**: remove them (recommended: the wizard asks source, then destinations) or keep two or three shortcuts ("Photos → folder", "Photos → server").
3. **Several servers per backup** (new, Pro) — allowed by the model; recommended.
4. **Do it before releasing 2.8.0** (recommended: WebDAV has not shipped, so only the 2.7.x NAS profiles need migrating; later it is a breaking change for more users) or ship WebDAV as is and unify in 2.9.
5. **Downgrade compatibility** (new shape unreadable by 2.7.x, kept aside): acceptable?

## Risks

- Regression of the SMB NAS path validated in the field: the target classes are untouched; the change is in how profiles reach them. Mitigation: fixtures, the existing suites, a real NAS run before release.
- Wizard wording and the "which type do I pick" list are UX decisions best checked on the phone.
- Guide and 13 translations to redo for the new screens (not for the engine).
