# 2.7.0 — Backup profiles

Goal (Andreas's wish, support 2026-11): *the user decides what to back up and where; the app takes care of how.* Pick a profile from a short list, run it with one tap. Same engines, same safety rules as today.

## Decisions (taken 2026-11-14)

- **Profiles are the only way to run a backup** ("Backups" tab, first). The old dashboard ("Advanced") is removed: several destinations per profile, Reconnect and free space moved into the profiles (decided 2026-11-14).
- **Existing setups are migrated** at first launch of 2.7.0: one profile for the Photos library with the current destinations, one per external source — no reconfiguration.
- **Six starting templates** (below). A profile = template + the user's own drive/folder choices **and its own configuration**: its NAS (host, share, folder, credentials), folder structure, file naming, file limit and extra file types. A profile is self-contained — with n profiles there are potentially n destinations, n NAS and n sets of options (decided 2026-11-14). New profiles start from a copy of the global settings; migrated ones get a snapshot.
- iOS first; Android follows with the same model once validated.

## Templates

| # | Template | Source | Destination | Pro |
|---|---|---|---|---|
| 1 | Photo library → external drive *(recommended)* | Photos | one folder (SSD / USB-C) | no |
| 2 | Photo library → NAS | Photos | NAS | yes |
| 3 | Photo library → iCloud Drive | Photos | iCloud Drive folder (slow — warning stays) | no |
| 4 | Camera / SD card → external drive | external source | one folder | yes |
| 5 | External drive → iCloud Drive | external source | iCloud Drive folder | yes |
| 6 | Photo library → external drive + NAS (double copy) | Photos | one folder + NAS | yes |

Template 5 is the second step of "free the iPhone": run 1, check the report, delete the originals (existing *Delete Source Files…*), then run 5. It runs on `FileCopyEngine`, which got the iCloud protection of the Photos engine (`ICloudRunGuard`: release of uploaded copies, pause under a reserve, quota detection) before being offered.

## Model (`Modules/Profiles/BackupProfile.swift`)

- `BackupProfile { id, name, template, source, destinations, settings?, nas?, nasPasswordAccount? }` — `settings` (`ProfileSettings`: folder structure, naming, file limit, extra extensions) and `nas` (`NASConfig`) are optional so a profile saved before they existed still loads and follows the global settings / the Advanced NAS.
- `ProfileSource`: `.photos` | `.external(UUID)` (the existing `ExternalSource` id)
- `ProfileDestination`: `.folder(bookmarkKey)` (resolved by `DestinationManager.resolveBookmark(forKey:)`, so SSD, USB and iCloud folders all work) | `.nas`
- `ProfileTemplate`: the six above (+ `.custom` for migrated setups) with title, symbol, source kind, required destinations, Pro flag.
- Stored by `ProfileStore` as JSON in UserDefaults (`PhotoVideoBackup.profiles`); a profile's own folders use keys `PhotoVideoBackup.profile.<uuid>.<n>`; migrated profiles keep the legacy keys (`…bookmark.ssd1/2`) so nothing moves.

## Running a profile

`DashboardViewModel.startBackup(profile:)` resolves the profile's destinations to `BackupTarget`s and calls the existing `startBackup` paths with that list instead of the global slots. Engines, dedup, naming, eviction/pause, reports: unchanged. Pro gates are enforced at run time exactly as today.

## Screens

- **Backups tab**: one card per profile — name, "source → destination(s)", connection state, **Run**; the pinned progress card and completion banner are the existing ones. Menu: Rename, Delete. **New backup** button.
- **New backup flow**: choose a template → (external source: pick one) → choose the folder(s) / confirm the NAS → name (pre-filled) → done.
- Plain wording: no SHA-256, no bookmarks, no "slot" in this flow.

## Out of scope (later)

Per-profile organisation/naming, scheduling, a guided two-step "free the iPhone" assistant, iCloud-aware engine for external sources (needed before template 5 is safe on a nearly full iPhone), Android.
