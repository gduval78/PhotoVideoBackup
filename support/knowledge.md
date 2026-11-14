# PhotoVideoBackup — support knowledge

Curated notes for the support agent. **Keep this file up to date at every store delivery** (see the "Documentation maintenance" checklist in CLAUDE.md): add each new feature, limit or known issue, with the version it appeared in.

## Versions
- iPhone / iPad (and Apple-silicon Mac as "Designed for iPad"): 2.6.1.
- Android: 2.6.0 (same version number as iOS; same engine and same features as iOS except iCloud Drive, which does not exist on Android).
- A backup started on one platform is recognised by the other (the hidden `.pvb-index.json` at each destination root is shared).

## Pro
- One-time purchase, no subscription. Free: back up the photo library to one destination, browse and preview backups (LUT preview included). Pro: SD/USB camera sources, second destination (mirror), NAS, LUT grading to H.265.
- Restore: on the upgrade screen (Settings → Upgrade to Pro), tap **Restore Purchases**, signed in with the same Apple ID (iOS) or Google account (Android).
- Refunds and charges are handled by Apple / Google, not by us.

## Common situations
- **"Not connected" source or destination after ejecting and reinserting a card or drive**: tap **Reconnect** (the system gives the app a new access each time a volume is mounted). Name and type are kept.
- **Backup button disabled**: no device name set (Settings → Device → Folder name), or the destination is not connected.
- **A backup stopped as "Partial"**: the report says why — Stop tapped, file limit reached (Settings → Backup → Max files per session, empty = unlimited), or a destination disconnected. Reconnect and run again; files already copied are skipped.
- **Nothing is copied on the second run**: normal — every file already backed up is recognised (even if edited since) and skipped.
- **File naming**: only files copied after the profile is switched on are renamed; existing files keep their names. Nothing is ever overwritten (`-1`, `-2` suffix for a different file with the same name).
- **NAS timeout**: the NAS is not reachable — same Wi-Fi or VPN (Tailscale) on, SMB sharing enabled, NAS firewall. Use the NAS's IP as host.
- **Mac (Designed for iPad)**: the first time, tap **Choose…** again to create a properly scoped folder access.
- **Android: photos have no GPS data in the backup**: the "location of your photos" permission was refused; grant it in system settings, otherwise Android strips GPS from the files it hands over.
- **Android: a destination in the phone's own storage does not show in the gallery**: intended (`.nomedia`), so the backup is not backed up again.
- **Android: sources/destinations written by Android do not keep the original modification date** (the system file API cannot set it).
- **iPhone almost full**: backups stream straight to the destination; a NAS-only backup needs room for one file at a time.
- **iCloud Drive destination (iPhone only)**: local copies are released once iCloud confirms the upload.
- **iCloud Drive destination: iPhone fills up during a big backup (known limit)**: iOS uploads on its own schedule, so copies pile up locally; the app releases them as iCloud confirms, but free space can also fall because of Photos' iCloud download cache (Optimize iPhone Storage — hypothesis). Advise: charger + Wi-Fi, let iCloud finish uploading, run again; for large libraries prefer an external USB-C SSD. The log may then say "destination disconnected" although the real cause is full storage (wording not yet fixed). The run is partial, nothing is lost; `.pvb-index.json` failing to write on a full volume is harmless (rewritten next run).
- **Backup paused "waiting for storage to free up" (iPhone, 2.6.1)**: the Photos backup keeps at least 2 GB free on the iPhone (plus the file's size when writing to iCloud Drive / a NAS-only staging copy). It pauses and resumes by itself when space returns (iCloud uploads finishing, iOS purging caches); after ~10 min without gain (30 s if nothing is left to release) it stops as Partial with "iPhone storage is low" — nothing is lost, free space and run again. Not available on Android / for SD-card sources (they never use the phone's storage).
- **A file appears as `NAME-1.ext` next to a smaller `NAME.ext` (before 2.6.1)**: an earlier copy was interrupted (disk full) and left a truncated file. Fixed in 2.6.1; with 2.6.0, delete the truncated original in the destination, then run again.

## Not supported / limits
- LUT grading only handles `.mp4` and `.mov`; per-video selection (never "grade all").
- Deleting source files after a backup only offers files copied *and* verified in that session, behind a 4-digit code.
- Browse on a NAS shows no thumbnails (files are downloaded on demand).
