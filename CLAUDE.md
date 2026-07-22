# PhotoVideoBackup — Project Rules for Claude

## Language
**Write all UI string literals in English** — this is the source language and the xcstrings key. Translations for French (`fr`), German (`de`), Spanish (`es`), Italian (`it`), Portuguese (`pt`), Chinese Simplified (`zh-Hans`), and Russian (`ru`) live in `PhotoVideoBackup/Resources/Localizable.xcstrings`. The user communicates in French, but English is always the code-level string.

When adding a new user-facing string:
1. Write the English literal directly in the Swift code (SwiftUI `Text`, `Label`, `Button`, etc. auto-localize string literals).
2. For `String`-returning contexts (computed properties, ViewModels), use `String(localized: "…")`.
3. Add FR / DE / ES / IT / PT / ZH-HANS / RU translations to `Localizable.xcstrings`.
4. Also add translations to `InfoPlist.xcstrings` for any plist-level strings (`NSPhotoLibraryUsageDescription`, etc.).

**Every feature extension must include full localization.** Never ship a new view or string without its 7 translations. This applies to every new `Text(…)`, `Label(…)`, `Button(…)`, `.navigationTitle(…)`, section header/footer, picker label, alert message, and error string — without exception.

### LanguageManager — critical localization rules

The app uses a custom `LanguageManager` that swizzles `Bundle.main` with `LanguageBundle` to intercept `localizedString(forKey:value:table:)`. This works for most cases but has **known limitations**:

**`String(localized: key, locale: someLocale)` does NOT reliably bypass `LanguageBundle`** — the `locale:` parameter is often ignored; the result depends on `LanguageManager.selectedCode`, not the locale passed. Do not rely on `locale:` to force a specific language in `String(localized:)`.

**The only reliable way to respect the selected language in a View** is `Text(LocalizedStringKey)` — SwiftUI's `Text` uses `.environment(\.locale, languageManager.currentLocale)` (set at the root in `PhotoVideoBackupApp`) and bypasses the `LanguageBundle` issue entirely.

**Rules for localized strings in Views:**
- Prefer `Text("key")` (LocalizedStringKey literal) over `String(localized: "key")` wherever possible.
- When a view component takes a `String` parameter (e.g. a custom struct with `name: String`), change the parameter to `LocalizedStringKey` or use a `@ViewBuilder` content closure so the `Text` stays as `LocalizedStringKey`.
- For verbatim (user-provided) strings, use `Text(verbatim: value)` to prevent SwiftUI from treating them as localization keys.
- `String(localized:)` without `locale:` is fine in ViewModels and non-View contexts where `LanguageBundle` intercepts correctly.

**Date formatting:** `Date.formatted()` uses `Locale.current` (device language), not the app language. Always pass `.locale(languageManager.currentLocale)` explicitly: `date.formatted(Date.FormatStyle(...).locale(languageManager.currentLocale))`.

**Byte count formatting:** `ByteCountFormatter.string(fromByteCount:countStyle:)` uses `Locale.current`. Use `Int64.formatted(.byteCount(style: .file).locale(languageManager.currentLocale))` instead.

**`FolderOrganization.labelKey`** returns a `LocalizedStringKey` for use in SwiftUI `Text`. Use this in Pickers and views instead of `displayName` (which uses `String(localized:)`).

The app language follows the iPhone system language by default. Users can override it in Settings → Language (in-app picker powered by `LanguageManager`).

## Documentation
- **User-facing documentation is `index.md` at the repo root** — GitHub Pages serves the site from `main` at path `/` (`https://gduval78.github.io/PhotoVideoBackup/`). Editing `index.md` on `main` and pushing publishes the site; no separate repo or submodule.
- GitHub repo: `git@github.com:gduval78/PhotoVideoBackup.git`
- To publish: edit `index.md` (and `images/`), commit and `git push origin main`.
- Screenshots are in `images/` at the repo root.
- Internal documentation (not published) is in `Documentation/UserGuide.md` — keep it in sync with `index.md`.
- **History note:** docs used to live in a `docs-publish/` submodule pointing at this same repo. That self-referential submodule caused `main` (app) and the docs line to diverge; it was removed in 2.2.1. The pre-removal docs history is preserved on the `origin/docs-backup` branch. Do **not** re-introduce a docs submodule.

## Versioning
- **Do NOT increment the version automatically** during a development or testing session.
- Increment version and build number only when the user explicitly signals readiness for App Store delivery (e.g., "on passe en production", "incrémente la version", "prépare la release").
- Version numbers are in `PhotoVideoBackup.xcodeproj/project.pbxproj` (both Debug and Release configurations).
- Rules:
  - Bug fix or minor change → increment patch: `1.0.0` → `1.0.1`
  - New feature → increment minor: `1.0.1` → `1.1.0`
  - Major redesign → increment major: `1.1.0` → `2.0.0`
- Always increment `CURRENT_PROJECT_VERSION` (build number) by 1 at the same time.

## Codebase
- iOS app written in Swift / SwiftUI
- Minimum target: iOS 16 (USB-C iPhones, iPhone 15+)
- Architecture: `@Observable` view models, no Combine
- IAP via StoreKit 2 (`StoreManager`)
- Destination bookmarks persisted via `DestinationManager`

## Mac "Designed for iPad" support

The app runs on Apple Silicon Macs via the "Designed for iPad" mode (no Mac Catalyst). Key constraints and workarounds implemented:

**Folder picker**
- `UIDocumentPickerViewController` fails silently on Mac — it uses an XPC remote view service (`ViewBridge`) that is non-functional in this mode.
- `fileImporter` SwiftUI modifier also uses `UIDocumentPickerViewController` internally on iOS/Mac and exhibits the same failure.
- **Fix**: `MacOpenPanel` (`Modules/MacOpenPanel.swift`) accesses `NSOpenPanel` via the Objective-C runtime. `runModal` returns `NSInteger` (not an object) — `perform(_:)` returns nil for non-object returns, so the IMP is called via `class_getMethodImplementation` + `unsafeBitCast`.
- All folder picker entry points check `ProcessInfo.processInfo.isiOSAppOnMac` and branch to `MacOpenPanel.pickFolder()` on Mac.

**Security-scoped bookmarks on Mac**
- Bookmarks must be created with `URL.BookmarkCreationOptions(rawValue: 2048)` (`.withSecurityScope`) and resolved with `URL.BookmarkResolutionOptions(rawValue: 1024)` (`.withSecurityScope`) — these are macOS-only raw values used at runtime since the iOS SDK doesn't expose them as named constants.
- `DestinationManager.saveBookmark` and `resolveBookmark` apply these conditionally via `isiOSAppOnMac`.
- `bookmarkData(options: .minimalBookmark)` fails with "kCFURLBookmarkCreationMinimalBookmarkMask cannot be used with scoped bookmarks" when `startAccessingSecurityScopedResource()` returns true. Use `options: []` (or the `.withSecurityScope` raw value on Mac).
- After reconfiguring a destination (first launch on Mac), the user must tap Choose… once to create a properly scoped bookmark — existing iOS bookmarks do not carry Mac security scope data.

**Entitlements**
- `com.apple.security.files.user-selected.read-write` added to `PhotoVideoBackup.entitlements`.
- `CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION = YES` in both Debug and Release build configurations.

**User use case**
- iPhone for lightweight travel (flights), Mac for road trips where multiple sources (DJI Neo 2, SD cards) are backed up to a portable SSD with full reporting.

## Known iOS API constraints
- `URLResourceValues.volumeURL` does not exist on iOS — use the NSURL bridge: `(url as NSURL).getResourceValue(&value, forKey: .volumeURLKey)`. Note: this method is `throws` in Swift, returns `Void`, not `Bool` — use `try?` and check the out-parameter separately.
- SourceKit false positives are common throughout this project (e.g. "Cannot find type 'PHMediaItem'", "'UIViewControllerRepresentable'", "'UIDocumentPickerViewController'"). They appear on nearly every file edit and do not reflect real compilation errors. Ignore them — the project builds correctly in Xcode.

## DestinationManager — companion UserDefaults keys
Each bookmark key (e.g. `PhotoVideoBackup.bookmark.ssd1`) has two companion entries saved at `saveBookmark` time:
- `<key>.displayName` — volume localized name (used for offline display when disk is disconnected)
- `<key>.folderPath` — folder path relative to volume root, e.g. `X/Y` (computed via `volumeURLKey` NSURL bridge)
Both must be cleared in `clearBookmark`. This pattern allows destinations to remain visible (grayed) when the drive is unplugged.

## Device support — file types & folder structures
- **DJI Mini 3 Pro**: DCIM folders prefixed `DJI_` → `mp4`, `jpg`, `jpeg`, `dng` + `.srt` telemetry
- **DJI 360 / Action** (`DeviceType.dji360`): DCIM folders matching `^\d{3}` (e.g. `100DJIMED`, `100MEDIA`) → `mp4`, `mov`, `jpg`, `jpeg`, `dng`, `mp3`, `osv` + `.srt`
- **Insta360 X5**: DCIM, `.insv` / `.insp` / `.lrv`
- **GoPro HERO**: DCIM folders matching `100GOPRO` → `mp4`, `jpg`; skips `.lrv` (proxy) and `.thm` (thumbnail)
- **Generic**: `mp4`, `mov`, `avi`, `jpg`, `jpeg`, `heic`, `png`, `dng`, `raw`, `cr2`, `cr3`, `arw`, `nef`, `rw2`, `insv`, `insp`, `braw`, `mp3`

## Background execution
- `UIApplication.shared.isIdleTimerDisabled = true` while backup runs — prevents auto screen lock.
- `UIApplication.shared.beginBackgroundTask` gives ~30 s of continued execution if user backgrounds the app.
- Both are managed in `DashboardViewModel.beginBackgroundExecution()` / `endBackgroundExecution()`, called at start/end of every backup (including all early-return error paths).

## UIDocumentPickerViewController
- Set `picker.directoryURL` to open the picker at a specific location (iOS 13+).
- The picker itself allows creating folders via the "…" menu — no need to implement folder creation in-app.
- `FolderPickerView` takes an `initialDirectory: URL?` parameter; pass `nil` for default behaviour.

## External source bookmarks — iOS security-scoped bookmark constraints

This area is tricky. Key facts learned from debugging:

**Create the bookmark immediately in the picker callback.**
The security-scoped URL provided by `UIDocumentPickerViewController` must have its bookmark data created synchronously inside the `onPick` closure (while `startAccessingSecurityScopedResource()` is still valid). If the URL is stored in `@State` and the bookmark is created later (e.g. after an alert interaction), the security scope may have expired and `bookmarkData()` will produce a bookmark that cannot be resolved on the next app launch. This is why `DashboardView`'s picker callback creates the bookmark immediately and stores `Data`, not `URL`, in `pendingSourceData`.

**Use `options: []`, not `.minimalBookmark`.**
`.minimalBookmark` stores only a path string. For external volumes (SD cards via USB-C reader) whose mount point can change between connections, this is insufficient — the bookmark resolves only while the card remains at the exact same path. `options: []` stores volume UUID, inode, and sandbox extension data, making it resolvable even if the card remounts at a different path.

**Bookmark resolution can fail transiently at app launch (timing).**
iOS may not have fully mounted the external volume by the time `onAppear` fires. `loadPersistedSources()` loads the source as offline (rootURL = nil), then a delayed `retryOfflineSources()` (800 ms later) re-attempts resolution. The same retry runs on every `refreshDestinationStatuses()` call (toolbar Refresh button) and on `UIApplication.willEnterForegroundNotification`.

**Eject + reinsert invalidates the bookmark (iOS security model).**
iOS security-scoped bookmarks for external volumes embed a sandbox extension tied to the specific mount instance. When a card is ejected and reinserted, iOS creates a new mount instance; the old extension is invalid and `URL(resolvingBookmarkData:)` throws. The automatic retry cannot fix this — it requires the user to tap **Reconnect**, which re-opens the folder picker and creates a fresh bookmark for the new mount instance. `DashboardViewModel.reconnectSource(id:url:bookmarkData:)` updates the existing source entry in-place (preserving name and device type) and replaces only the bookmark data in UserDefaults.

**`ExternalSource.rootURL` is `URL?` (nil = offline).**
Sources with a failed bookmark are kept in `externalSources` with `rootURL = nil` and `isAvailable = false`. They display as grayed ("Not connected") so the user knows the source exists but is unreachable. `startBackup(from:)` guards against nil rootURL with an explicit error message.

## Backup progress — ETA
- `DashboardViewModel` tracks `backupStartDate: Date?` and exposes `estimatedSecondsRemaining: Double?`.
- ETA is computed from elapsed time and `overallProgress` (elapsed / progress × (1 − progress)), displayed after 5 s with >1 % progress.
- `resetSpeedTracking()` is called at backup start and `finishSession`. `updateSpeedEstimate(_:)` is called inside every `for await progress in stream` loop.

## Local notifications
- `UNUserNotificationCenter` permission is requested once at launch via `DashboardViewModel.requestNotificationPermission()`, called from `PhotoVideoBackupApp.onAppear`.
- `NotificationDisplayDelegate` (in `PhotoVideoBackupApp.swift`) implements `UNUserNotificationCenterDelegate` and returns `.banner + .sound` so notifications appear even when the app is in the foreground.
- A notification is sent at the end of every backup inside `finishSession()` via `sendCompletionNotification(_:)`.

## FolderOrganization — backup folder structure

`Modules/FolderOrganization.swift` centralises all folder-structure logic.

```swift
enum FolderOrganization: String, CaseIterable {
    case flat        // {destination}/{deviceName}/{filename}
    case byMonth     // {destination}/{deviceName}/{yyyy-MM}/{filename}
    case byDate      // {destination}/{deviceName}/{yyyy-MM-dd}/{filename}  ← default
    case byYearMonth // {destination}/{deviceName}/{yyyy}/{MM}/{filename}
}
```

- UserDefaults key: `"folderOrganization"` (String, rawValue of the enum)
- Default: `byDate`
- `FolderOrganization.current` reads UserDefaults synchronously; safe to call from actor context (both engines call it).
- Both `PHBackupEngine` and `FileCopyEngine` delegate destination URL construction to `FolderOrganization.current.destinationURL(root:deviceName:date:fileName:)`.
- `BackupSession` stores the value at backup time in `folderOrganizationRaw: String` (default `"byDate"`) so History / Report can display which mode was used.

## MediaScanner — capture date priority

`mediaFile(at:)` resolves the capture date with this priority:
1. **EXIF `DateTimeOriginal`** via ImageIO (`exifCaptureDate`) — images only (JPG, DNG, etc.)
2. **Video container `creationDate`** via AVFoundation (`videoCreationDate`) — MP4, MOV, AVI, M4V, INSV, BRAW. Reads `AVMetadataCommonKeyCreationDate` from `AVURLAsset.commonMetadata`. This date is embedded by the camera/drone in the QuickTime/MP4 container and **survives any file copy**, regardless of filesystem timestamps.
3. **`contentModificationDate`** (filesystem) — fallback of last resort.

The video container date (step 2) is critical for the two-step iOS relay workflow (see below): without it, `modificationDate` is used for videos, which changes at each copy and produces duplicate destination folders.

## FileCopyEngine — modification date preservation

`streamCopy` propagates the source file's `modificationDate` to all destination files after the copy via `FileManager.setAttributes([.modificationDate: srcDate], ...)`. This ensures the filesystem date survives the relay chain (Neo 2 → SD → SSD) even if the container metadata is not available for a given format.

## iOS two-step relay backup (DJI Neo 2)

iOS has one USB-C port — source and destination cannot both be connected simultaneously. Workaround:

- **Step 1**: Connect Neo 2 → backup to SD card (SD card is the destination).
- **Step 2**: Connect SD card as *source* → backup to SSD (SSD is the destination).

For step 2 to deduplicate correctly against files already on the SSD (e.g. from a prior Mac direct backup), the source `displayName` used as the device folder **must match** step 1's source name. The simplest way: when adding the SD card source in step 2, navigate inside it and select the device subfolder directly (e.g. `DJI Neo 2/`) — its `lastPathComponent` becomes the `displayName` automatically.

The date fixes above (container date + modification date preservation) ensure that `SSD/DJI Neo 2/2024-01-14/file.mp4` from a direct Mac backup and from the two-step relay produce the **same path**, so deduplication via physical file existence check works correctly.

## Deduplication — cascade logic (v2.1.0+)

Both engines apply a 3-level cascade per file to decide whether to copy:

1. **Physical existence check** — all destination URLs checked for size match. If all present → skip immediately (no file read, no IndexStore query).
2. **SHA-256 content check** — source SHA-256 computed, then `IndexStore.knownDestinationPaths(forSHA256:)` returns stored destination paths. At least one must still exist on disk (`FileManager.fileExists`) before skipping — this ensures deleted files are re-copied even if their hash is in the IndexStore.
3. **Copy** — `streamCopy` writes to missing destinations using the precomputed SHA-256 (no double-read of source). SHA-256 is persisted in `IndexedFile` for future dedup.

**Estimate-vs-actual on the streamed path (fixed in build 43).** `PHBackupEngine`'s physical existence check compares a target's stored size against `item.fileSize`, which for Photos is an **estimate** and often differs from the real exported bytes (video/HEIC). A NAS that already holds the file was therefore marked "missing", and because the whole-file SHA skip only fires when *every* target is covered, a local target legitimately needing the file (e.g. an SSD that was disconnected on an earlier run) let the NAS be re-uploaded. `uploadToRemotes` now takes `expectedSize` and, once streaming has revealed the true size, re-checks each remote's `existingSize` and skips the upload for any already at that size, recording it as present. When that leaves nothing written but something present, the file is recorded skipped, not failed. `FileCopyEngine` is unaffected — its `file.size` is the real filesystem size, so its existence check was always accurate.

**Critical invariant**: The SHA-256 skip is only valid when EVERY destination root has at least one known path for that hash still present on disk. Checking "any known path on any disk" is wrong when using 2 SSDs — if SSD2's folder is deleted, SSD1 still has the file, so the hash is "known" but SSD2 would never receive it. Both engines use `destinations.allSatisfy { destRoot in knownPaths.contains { $0.hasPrefix(destRoot.path) && fileExists($0) } }`.

`IndexStore` methods for deduplication:
- `knownDestinationPaths(forSHA256:) -> [String]` — returns stored paths; caller checks `FileManager.fileExists`.
- `captureDate(forDestinationPath:) -> Date?` — lookup by filename for use in `RenameSheet` preview.
- `updateDestinationPath(from:to:)` — called after rename to keep `destinationPaths` and `fileName` in sync.

## Backup engine architecture — memory & batching

Both `PHBackupEngine` and `FileCopyEngine` use the same pattern to avoid memory pressure on large libraries:

- **No `session.files.append`** — IndexedFile objects are inserted directly into the SwiftData context (`IndexStore.shared.context.insert(indexed)`). SwiftData manages the relationship via its inverse; never fault in the full `session.files` collection during a backup run.
- **Batch save every 500 files**: `if index > 0 && index % Self.batchFlushInterval == 0 { await MainActor.run { IndexStore.shared.save() }; try? await Task.sleep(nanoseconds: 10_000_000) }` — the 10ms sleep gives iOS room to reclaim memory between batches.
- **Stats via actor-isolated counters**: `_copiedCount`, `_skippedCount`, `_failedCount`, `_totalBytesCopied`, `_wasLimited`, `_disconnectedCount` are actor-isolated vars on the engine. They are read after the stream completes via `engineResult: EngineResult`. `finishSession` uses these counters directly — it never scans `session.files`.

## Streamed export — backing up with little free space

`PHBackupEngine` used to export every asset to `temporaryDirectory` before copying it out, so the **device volume had to hold the whole file** even when the destination was an external SSD. A 4 GB video needed 4 GB free on the iPhone.

**Local-only sessions now stream.** `streamAssetToDestinations` writes chunks from `PHAssetResourceManager.requestData(for:options:dataReceivedHandler:completionHandler:)` straight to every destination `FileHandle`, folding each chunk into a running SHA-256.

- **Backpressure is free.** Photos calls `dataReceivedHandler` on a serial queue; returning from the handler is what paces delivery. Writing inside the handler means nothing buffers — footprint is one chunk regardless of file size. No semaphore, no `AsyncStream`, no deadlock risk.
- **The chunk must be copied.** The header states the buffer's lifetime is not guaranteed beyond the handler — always `Data(data)`.
- **No cancellation on total disconnection.** When every destination dies the sink stops writing but the request runs to completion; cancelling risks never receiving the completion handler, which would hang the copy.
- **Local destinations are fully independent (fixed after the 3-destination report).** Losing or filling one local destination must never stop another. Two places enforce this:
  - **Setup:** `openDestinationHandles` opens one handle per destination and drops any whose volume is gone (SSD unplugged) into a `disconnected` list instead of aborting the rest. Previously all-or-nothing, so after the SSD disconnected every subsequent file threw at setup and iCloud silently stopped. A creation failure on a *still-reachable* volume is a real error and rethrows. Unit-tested by `DestinationIndependenceTests` (including SSD-in-slot-1, the field ordering).
  - **Mid-write:** `ChunkSink.write` drops **only** the offending destination on a write failure and keeps writing to the rest. An earlier version set a single global failure, so a full iCloud Drive folder (a "real error" on a still-reachable volume) would have taken a healthy SSD down with it. A vanished volume and a real error now differ only in log tag (`[DISC_ERROR]` vs `[COPY_ERROR]`); both drop just that destination. Both are surfaced as `disconnected` in the `StreamResult`, so the file is partial there and a re-run picks it up. Not unit-tested — `ChunkSink` is private and needs a failing `FileHandle` write; it mirrors the tested setup-path logic.
- **Only NAS-*only* sessions stage.** `canStream = !localTargets.isEmpty`. When both a local and a remote destination are present, the asset is streamed to the local one and the SMB upload then reads *that* file — it lives on the external volume, so no staging copy touches the device. If every local destination dies mid-copy there is nothing to upload from, and the code falls back to `exportToTemp` rather than letting a disconnected SSD take the NAS down with it.
- **Running the upload after the dedup check saves bandwidth too**: a renamed duplicate is deleted locally and never uploaded.

**AMSMB2 has no incremental upload — do not try again.** All three public write APIs need the whole file at once: `uploadItem(at:)` takes a URL, `write(data:)` takes a full `Data`, and `write(stream:)` looks like streaming but is not — `AsyncInputStream.prefetchData()` drains the sequence as fast as it can into one `Data` and `read()` only advances an offset without ever purging consumed bytes, so the entire file ends up in RAM. That is strictly worse than a staging file on disk (jetsam kills the app on a 4 GB video). `SMB2FileHandle`, which does support incremental writes, is internal to the package. Streaming to a NAS-only destination would require patching `prefetchData` upstream.
- **`FileCopyEngine` never staged anything** — it reads straight from the source file. SD card / drone workflows are unaffected by all of this.

**Dedup ordering inverts on the streamed path.** The hash is only known once the bytes have flowed, so the SHA-256 check the staging path runs *before* copying runs *after*: if the content already sits at every destination under a different name, the just-written files are deleted and the file is recorded as skipped. Paths written during this file are excluded from the coverage check or they would count as covering themselves. Without this, dedup of renamed files (v2.1.0) would silently regress.

**Not covered by tests.** The regression suite exercises `FileCopyEngine`; `PHBackupEngine` needs `PHPhotoLibrary` and cannot be seeded in a unit test. The streamed path requires device validation.

## iCloud eviction — freeing device space during a backup

`Modules/ICloudEviction/ICloudEvictionManager.swift`. A destination in an **iCloud Drive folder** sits on the device volume, so the streamed copy stays there until iCloud uploads it. Without eviction, a backup to iCloud accumulates copies of what is already in the cloud and fills the phone.

**Verified on device** (`ICloudEvictionProbe`, verdict `EVICT_OK`): `evictUbiquitousItem` works on a *user-picked* iCloud Drive folder — a security-scoped URL outside the app's own ubiquity container — with **no iCloud entitlement**. This is what makes CloudKit unnecessary for freeing space; do not revisit that.

- **The upload gate is not optional.** Every eviction is gated on `isUploaded && !isUploading`. `isUploaded` alone only means "some data is present in the cloud". A file that cannot be positively confirmed is left alone — absence of evidence never authorises an eviction.
- **A throw-free `evictUbiquitousItem` is not proof.** `evictIfUploaded` re-checks that `downloadingStatus == .notDownloaded` before counting the bytes as reclaimed.
- **`URL` caches resource values** — every poll rebuilds the URL, or the upload appears never to finish.
- **Eviction runs after SHA-256 verification**, never before: verifying re-reads the destination, and reading an evicted file pulls it straight back down from iCloud.
- **Files are queued only after surviving the dedup rollback**, so a duplicate deleted post-hoc never lands on the pending list.
- **Blocking only under pressure.** After each file a cheap non-blocking pass evicts whatever is ready. Only when free space drops below `PHBackupEngine.lowSpaceWatermark` (2 GB) does the run block on uploads. A phone with room to spare runs at full speed.
- **One stall per run, not one per file.** If a blocking pass hits its 120 s deadline, `ReclaimResult.stalled` is set and the engine stops blocking for the rest of the session (`evictionStalled`). Uploads that are not progressing (no network, iCloud quota exhausted) would otherwise crawl the backup to 2 min/file for no gain.

## Disk-space preflight

`DiskSpacePreflight.check(largestFileBytes:destinations:usesStagingCopy:)` refuses a backup that cannot fit before it starts, rather than letting it die mid-file with a partial session.

- Sized on the **smallest single file**, not the total and **not the largest**. A file too big to fit fails on its own and the run continues with the rest, so one oversized video must not block the two hundred small ones behind it. This check catches only the case where *nothing* can proceed. Sizing it on the largest file was the original mistake.
- The NAS-only staging branch additionally checks **per file** before `exportToTemp`, so an oversized file is reported as "Not enough free space on this device to copy this file." and skipped, rather than costing a full read and returning an opaque POSIX error.
- `exportToTemp` deletes its partial file when the export throws. The caller's `defer` is only registered once the function has returned a URL, so without this a failed 4 GB export leaked its partial file — making a disk-full run progressively worse with every retry.
- Counted copies: the staging copy (only when **every** target is remote — a NAS-only session, the one case that still stages) plus any destination on the **device volume** — i.e. an iCloud Drive folder. External SSDs are a different volume; SMB targets stream from staging. Volume identity is compared via `.volumeIdentifierKey` against `temporaryDirectory`.
- Uses `volumeAvailableCapacityForImportantUsage` (includes purgeable space iOS reclaims), not raw free bytes.
- **Fails open.** `availableBytes` is `Int64?`; nil means the volume could not be read and the backup proceeds. Returning 0 instead would have refused *every* backup.
- A file size of 0 (iCloud assets before download) enforces only the safety margin.
- Refusals are logged as `[DISKSPACE] refused required=… available=… largest=… deviceCopies=…`.

## Mid-backup disconnection detection (v2.1.4+)

`streamCopy` in both engines handles per-destination disconnection:

- Destinations are tracked as `(handle: FileHandle, dest: URL)` pairs.
- On `handle.write()` failure: `isVolumeReachable(dest)` checks `volumeTotalCapacityKey` on the destination folder. If 0 or throws → volume gone → drop this destination, continue with others.
- If all destinations disconnect → throw `CopyError.allDestinationsDisconnected` → main loop catches it, breaks, marks session `.partial` or `.failed`.
- `StreamResult` carries `disconnected: [URL]` and `written: [URL]` — verify and modificationDate propagation only apply to `written` destinations.
- `_disconnectedCount` accumulates across files; `finishSession` sets `.partial` if `disconnectedCount > 0`.
- `[DISC_ERROR]` tag written to DiagnosticLog on every disconnection event.

**Security scope for multiple SSDs**: `startAccessingSecurityScopedResource()` can return `false` on iOS for a valid external volume (sandbox extension already embedded in the bookmark). **Never filter destinations on this return value** — call it on all destinations for side effects, keep all in `accessed`. Actual inaccessibility is caught by the copy engine at write time.

## Report — multi-destination display (v2.1.4+)

When `session.destinations.count > 1`, `ReportView` switches to a multi-target layout:

- **Summary**: one `TargetSummary` block per SSD showing Copied / Skipped / Failed counts for that SSD specifically. Computed by `targetSummaries()` — iterates `session.files`, checks `file.destinationPaths.contains { $0.hasPrefix(root) }` per destination root.
- **Files detail**: single `ReportMultiTargetFilesView` (replaces 3 separate Copied/Skipped/Failed lists). Each file row shows filename + per-SSD status indicator (● green = copied, ● orange = skipped, ● red = failed/disconnected) + size + date.
- Per-target status derived from `file.destinationPaths` vs `session.destinations` — no new SwiftData fields needed.
- Single-destination sessions keep the existing Copied / Skipped / Failed split navigation.

## Backup session — file limit and partial status

- UserDefaults key: `"backupFileLimit"` (Int, 0 = unlimited)
- Setting exposed in Settings → Backup as "Max files per session".
- The limit applies only to files that actually need copying (files already at the destination are skipped and do not count against the limit).
- When the limit is reached, the engine sets `_wasLimited = true` and breaks. `finishSession` sets `session.status = .partial`.
- `SessionStatus.partial` is displayed as orange in History (`exclamationmark.arrow.circlepath`), Report (header badge + warning label), DashboardView completion banner, and push notification.

## BackupSession — fields added across versions

All fields use SwiftData default values (lightweight migration — no migration plan needed):
- `sourceDisplayName: String = ""` *(v1.4.0)* — human-readable source name saved at backup time. Used in History/Report so the source is readable even after removal.
- `folderOrganizationRaw: String = "byDate"` *(v1.4.0)* — rawValue of `FolderOrganization` at backup time. Used in History/Report to display which folder structure was used.
- `destinationDisplayNames: [String] = []` *(v1.7.0)* — display names of destination drives at backup time (e.g. `["SanDisk / Backup"]`). Shown in History rows and Report summary. Old sessions fall back to path last component.

## Browse tab — BackupBrowser module
- `BackupBrowserViewModel` (`Modules/BackupBrowser/`) manages security-scoped access to SSD destinations: call `startAccess()` on tab appear, `stopAccess()` on disappear. Thumbnails are cached in memory for the session.
- Navigation hierarchy: `BackupBrowserView` → `DeviceFolderView` (LUT Grade section + subfolders) → `FolderContentView` (recursive) → `MediaGridView`.
- `DeviceFolderView` is the first level after tapping a device folder. It shows the LUT Grade section at the top, then subfolders and/or a root files link.
- `FolderContentView` is recursive — it handles any depth of subfolder (date folders, year/month folders, etc.) and falls through to `MediaGridView` when no subfolders exist.
- Videos play via `VideoFullScreenView` (full-screen `AVPlayerViewControllerRepresentable` + dismiss button). If an `activeLUT` is set, a `AVMutableVideoComposition(asset:applyingCIFiltersWithHandler:)` is attached to the `AVPlayerItem` for real-time LUT preview.
- Thumbnail generation: ImageIO (`CGImageSourceCreateThumbnailAtIndex`) for images, `AVAssetImageGenerator` for videos.
- Full-size image in `MediaDetailView` is loaded via ImageIO capped at 2048 px to avoid memory pressure on large RAW files.

## Browse tab — multi-select, share and rename
- Selection mode is local state in `MediaGridView` (`@State selectionMode`, `selectedURLs: Set<URL>`).
- Toolbar in selection mode: **Cancel**, **Select All / Deselect All**, **Rename (N)**, **Share (N)**.
- On share: selected files are copied to a unique temp directory (`FileManager.default.temporaryDirectory/pvb_share_{UUID}/`) in a detached task, then presented via `UIActivityViewController` (`ActivityShareSheet`).
- Temp directory is deleted in the `onDismiss` handler of the sheet (via `cleanupTempFiles()`).
- Security-scoped access opened in `BackupBrowserView.onAppear` remains valid throughout the entire navigation stack — no need to re-open per operation.
- `BackupBrowserViewModel.refreshFolder(_:)` increments `folderListVersion` to force re-enumeration after rename.

## Browse tab — batch rename (v2.1.0)
- `RenameSheet` (`Views/RenameSheet.swift`) — sheet with pattern editor, token chips, index width picker (2/3/4 digits), live preview of first 3 filenames, progress counter.
- `RenamePattern` (`Modules/RenameEngine/RenamePattern.swift`) — pattern engine. Tokens: `{YYYY}` `{MM}` `{DD}` `{hh}` `{mm}` `{ss}` `{index}` `{original}`. Anything else is literal text. Date is **capture date** (EXIF `DateTimeOriginal` or video container `creationDate`), not modification date.
- Rename uses `FileManager.moveItem` — file content unchanged, SHA-256 invariant.
- After rename: `IndexStore.updateDestinationPath(from:to:)` is called per file to keep `destinationPaths` and `fileName` in sync for future deduplication.
- Conflict resolution: if target name already exists, `_2`, `_3`… suffix is appended automatically.
- Files sorted alphabetically before applying `{index}` so numbering is deterministic.

## Browse tab — LUT Grade feature
- `LUTStore` (`Modules/LUT/LUTManager.swift`) — `@Observable @MainActor` singleton. Imports `.cube` files to `Documents/LUTs/`. Parsed via `LUTStore.parseCube(at:)` (nonisolated static, can run on any thread). Applies via `CIColorCubeWithColorSpace` filter.
- `LUT assignments` persisted in UserDefaults `"PhotoVideoBackup.lut.assignments"` as `[String: String]` — key = device folder `lastPathComponent`, value = LUT filename.
- `VideoGradingEngine` (`Modules/LUT/VideoGradingEngine.swift`) — `final class` (was actor, changed to class since `run`/`grade` are stateless). Grades `.mp4` and `.mov` files only. Creates `AVMutableVideoComposition` + `AVAssetExportSession` (HEVC preset). Output goes to `DeviceFolder (Graded)/` mirroring the original path. Already-graded files are skipped.
- **Grading requires Pro** (`StoreManager.shared.isPremium`). Free users tapping Grade see the paywall sheet. Real-time LUT preview in `VideoFullScreenView` is free.
- Grading state is exposed on `BackupBrowserViewModel` as `gradingState: GradingState?` and `gradingDeviceFolder: URL?` — `DeviceFolderView` checks `gradingDeviceFolder == folder` to show progress for the right folder only.
- Grade button is disabled while `gradingState?.isFinished == false` (active grading only — re-enables after completion).
- `folderListVersion: Int` on `BackupBrowserViewModel` increments when grading completes, causing `BackupBrowserView` and `DeviceFolderView` to re-enumerate the filesystem so the new `(Graded)` sibling folder appears immediately without manual refresh.
- Folders whose `lastPathComponent.hasSuffix(" (Graded)")` do not show the LUT Grade section in `DeviceFolderView`.
- `activeLUT: ParsedLUT?` is passed down from `DeviceFolderView` → `FolderContentView` → `MediaGridView` → `VideoFullScreenView` as a normal parameter (prop drilling). This is intentional: avoids coupling navigation state to the ViewModel.
- LUT parsing is done in `Task { await Task.detached { LUTStore.parseCube(at:) }.value }` to keep heavy work off the main thread while safely updating `@State` on the main actor.

### LUT Grade on NAS destinations (v2.2.0)

The NAS Browse path (`NASBrowserView`) has full LUT Grade parity with the local `DeviceFolderView`. Key facts:

- **Two separate Browse paths.** Local SSD folders route through `DeviceFolderView`; NAS folders route through `NASBrowserRootView` → `NASBrowserView` (a generic SMB file lister). The LUT Grade section had to be added to `NASBrowserView` explicitly — it is not shared code. Anything added to the local LUT flow must be mirrored there.
- **LUT assignment is keyed by a plain `String`, not a `URL`.** `BackupBrowserViewModel` exposes key-based `assignedLUTName(forKey:)` / `assignLUT(named:forKey:)` / `removeLUT(forKey:)`; the old URL-based methods are thin wrappers using `deviceFolder.lastPathComponent`. NAS folders use `BackupBrowserViewModel.nasLUTKey(subPath:)` = `"nas:" + subPath` so a NAS folder never collides with a local device-folder name in the shared `lutAssignments` UserDefaults dict.
- **`LUTPickerSheet` and `VideoFullScreenView` are now `internal` (not `private`)** and reused by `NASBrowserView`. `LUTPickerSheet` takes a `folderKey: String` (not a `URL`).
- **NAS LUT Grade section shows only when `!subPath.isEmpty` and the folder name doesn't end in `" (Graded)"`** — i.e. at device-folder level, matching local. Not at the NAS root.
- **Grading is per-video, never "grade all".** A camera folder mixes LOG and non-LOG footage; grading non-LOG with a LOG LUT ruins it. `NASBrowserView` has a multi-select mode (Select / Select All / Grade), mirroring `MediaGridView`. `startNASGrading(target:subPath:relFiles:lut:)` takes the explicit list of chosen files.
- **Download → grade → upload.** `VideoGradingEngine.grade(source:destination:lut:)` is now `internal` and reused: each NAS clip is downloaded (`SMBTarget.download`) to a temp file, graded locally, then uploaded (`SMBTarget.upload`) to the `(Graded)` sibling (`nasGradedBase(forSubPath:)`). Skip check uses `SMBTarget.existingSize(forRelative:)`. NAS grading state is separate: `nasGradingState` / `nasGradingSubPath`; cancelled in `stopAccess()`.
- **Bandwidth caveat:** unlike local grading (direct filesystem), NAS grading transfers each clip twice over the network (down + up). Slow for 4K, heavy on cellular. Not yet gated behind a mobile-data warning.
- **Fix (both paths):** `VideoGradingEngine.run`'s catch now deletes a failed export's partial file, so it isn't later mistaken for "already graded" via `fileExists`.

## File reading — InputStream, not FileHandle.readData

**Never use `FileHandle.readData(ofLength:)` for reading source or destination files.** This old ObjC API raises an `NSException` (not a Swift `Error`) on I/O errors — exceptions are uncatchable in Swift and crash the app silently.

**Always use `InputStream`:**

```swift
guard let stream = InputStream(url: url) else { throw ... }
stream.open()
defer { stream.close() }
var buffer = [UInt8](repeating: 0, count: chunkSize)
while stream.hasBytesAvailable {
    let n = stream.read(&buffer, maxLength: chunkSize)
    if n < 0 { throw stream.streamError ?? ... }
    guard n > 0 else { break }
    // use Data(buffer[0..<n])
}
```

`stream.read(_:maxLength:)` returns `Int`: `-1` = error (check `stream.streamError`), `0` = EOF, `>0` = bytes read. Always catchable, no ObjC exceptions.

`FileHandle` is still used for **writing** (`handle.write(contentsOf:)` throws Swift errors correctly).

## IndexStore — SwiftData corruption recovery

`IndexStore.init()` no longer calls `fatalError`. Recovery sequence:
1. Normal `ModelContainer` init → success → proceed.
2. Failure → delete `.store`, `.store-shm`, `.store-wal` from Application Support → retry → `didResetHistory = true`.
3. Still failing → in-memory container → app works, history not persisted → `didResetHistory = true`.

`DashboardViewModel.onAppear()` checks `IndexStore.shared.didResetHistory` and surfaces a user-visible message. **Never add `fatalError` back** — a corrupted database should not prevent the app from launching.

## DiagnosticLog — crash tracing

`Modules/IndexStore/DiagnosticLog.swift` — append-only log, serialized on a background queue, safe to call from any thread or actor.

**File location:** `Documents/pvb_diagnostic.log` — survives app updates, visible in Files app, max 1000 lines (pruned at launch).

**API:**
```swift
DiagnosticLog.write("[TAG] message")                         // any context
DiagnosticLog.pruneAndMarkLaunch(appVersion: "2.0.1")       // call once in App.init()
DiagnosticLog.installObservers()                            // call once in App.init() — lifecycle/memory/thermal breadcrumbs
DiagnosticLog.markUIReady()                                 // call in ContentView.onAppear (logs once)
```

**System-metric helpers (cheap, side-effect-free, safe from any context):**
- `DiagnosticLog.envSnapshot()` → `"mem=95/3072MB disk=4200MB thermal=nominal lowpower=off lang=fr-FR applang=auto"` — used/total RAM (`phys_footprint`, what iOS jetsam watches), free disk, thermal state, low-power mode, **phone language** (`lang=`) and **in-app language override** (`applang=`, `auto` = follows system). Use these to reply to a user in their language.
- `DiagnosticLog.memoryTag` → compact `"mem=95/3072MB"` for high-frequency lines.
- `memoryFootprintMB()` (via `task_vm_info` / `phys_footprint`), `freeDiskMB()`, both return `-1` on failure.

**Tags in use:**
| Tag | Where written |
|---|---|
| `[LAUNCH]` | App.init — device model (e.g. `iPhone16,2`), iOS version, **+ `envSnapshot()`** (RAM/disk/thermal/lowpower/lang) |
| `[STORE_OK]` | IndexStore.init — SwiftData store opened successfully: `persistent`, `reopened after reset`, or `in-memory`. Its **absence** after `[LAUNCH]` = crash/hang during store init |
| `[UI_READY]` | ContentView.onAppear (once) — proves the UI rendered; its **absence** after `[LAUNCH]`/`[STORE_OK]` = early crash before first frame |
| `[STARTUP_OK]` | DashboardViewModel.onAppear — cold-start finished, UI interactive; summary `store=/destinations=/sources=/premium=`. **This line = the app started without problem** |
| `[LIFECYCLE]` | installObservers — `background` / `foreground` (+ memoryTag) / `terminate` |
| `[THERMAL]` | installObservers — thermal state changed (+ envSnapshot) |
| `[POWER]` | installObservers — low-power mode toggled |
| `[DATA_PROTECTION]` | installObservers — device locked/unlocked (protected data un/available) |
| `[STORE_RESET]` | IndexStore when SwiftData container is recreated |
| `[SCAN_START]` | DashboardViewModel before PHLibraryScanner / MediaScanner |
| `[SCAN_ERROR]` | DashboardViewModel if scan throws |
| `[BACKUP_START]` | DashboardViewModel — source, file count, destination count, **+ memoryTag** |
| `[PROGRESS]` | Both engines every 50 files — index, totals, **memoryTag**, current filename |
| `[BACKUP_END]` | DashboardViewModel — copied/skipped/failed/limited, **+ memoryTag** |
| `[COPY_ERROR]` | Both engines on per-file export or write failure |
| `[MEMORY_WARNING]` | installObservers on `UIApplication.didReceiveMemoryWarningNotification` (+ envSnapshot) |
| `[BACKGROUND_EXPIRED]` | DashboardViewModel background task expiry handler |
| `[NAS]` / `[NAS_ERROR]` | NAS config save / SMB connect / test-connection failures |

**UI:** History tab → "Diagnostic" section → tap row to view → envelope button sends via `mailto:` with log content in body to `photovideobackup@icloud.com`. Swipe left on the row to delete.

**Was the startup clean?** A healthy cold start writes this exact chain, in order:
`[LAUNCH]` → `[STORE_OK]` → `[UI_READY]` → `[STARTUP_OK]`.
If all four are present, the app started without problem. Where the chain **stops** pinpoints the failure stage:
- stops at `[LAUNCH]` → crash/hang during App.init or SwiftData store open (no `[STORE_OK]`);
- `[STORE_OK]` but no `[UI_READY]` → crash between store open and first frame render;
- `[UI_READY]` but no `[STARTUP_OK]` → crash during the initial `onAppear` (destination/source loading, network monitor).
A `[STORE_OK]` reading `reset`/`in-memory` (or a `[STORE_RESET]`) means the app launched but the history DB was recovered — functional, history lost.

**Reading a crash report:**
- Log ends at `[LAUNCH]` with **no `[UI_READY]`** → crash before the first frame (framework load, SwiftData init, or App.init).
- Log ends on `[BACKUP_START]` or `[PROGRESS]` without a following `[BACKUP_END]` → crash during the copy; the last `[PROGRESS]` line narrows it to a 50-file window and names the file.
- **Memory-kill (jetsam) signature:** rising `mem=` on `[PROGRESS]` lines, often a `[MEMORY_WARNING]` just before the cut, and no crash log — the higher `mem=` approaches total RAM (tight on 3 GB devices like the iPhone XR / `iPhone11,8`), the more likely iOS terminated the app.

## AppConstants

`App/AppConstants.swift` centralises app-wide constants:
```swift
enum AppConstants {
    static let supportEmail = "photovideobackup@icloud.com"
}
```

Use `AppConstants.supportEmail` everywhere an email address is needed (Settings Support section, DiagnosticLogView). Never hardcode the address inline.

## Documentation maintenance — checklist for every feature session

**After any feature or UI change, always do the following before closing the session:**

1. **Update `index.md`** (repo root) — version header, affected sections (Settings, History, Browse, Completion, FAQ). The user cannot do this without reading the code; you can.
2. **Update `Documentation/UserGuide.md`** — keep it in sync with `index.md`.
3. **Update the Version Changelog** below (already in CLAUDE.md).
4. **Identify screenshots that need retaking** — you cannot take device screenshots yourself. At the end of the session, list explicitly which screenshots in `images/` (repo root) are now stale and what the new screen should show, so the user knows exactly what to capture. Common candidates:
   - Settings screen: any time a new setting is added or a section changes
   - Dashboard/History/Report: any time a new status, badge, or row format changes
   - Browse tab: any time navigation depth or grid layout changes
5. **Commit the docs with the rest** — `index.md` and `images/` live on `main`; a normal `git push origin main` publishes the site (Pages builds from `main` root). No separate repo/submodule.

**What you cannot do alone (flag to the user):**
- Take screenshots on a real device or simulator
- Verify App Store Connect metadata or pricing
- Submit to the App Store

## Version Changelog
Keep this section up to date with every release. Use it to write App Store release notes.

| Version | Build | Date       | Type    | Description |
|---------|-------|------------|---------|-------------|
| 2.3.0   | 44    | 2026-07-22 | Feature | **Back up when the iPhone is nearly full.** The Photos engine no longer copies each asset to a temporary file before writing it out — it streams the asset from the Photos daemon straight to the destination, hashing as it goes, so the device holds **one 4 MB chunk at a time instead of the whole file**. A 4 GB video used to need 4 GB free on the iPhone just to be backed up to an external SSD; it now needs almost nothing. Applies to every local destination (SSD, iCloud Drive) and to SSD + NAS together, where the SMB upload reads from the copy just written to the external volume rather than staging on the device. A NAS-*only* backup still stages, because AMSMB2 offers no incremental upload. **iCloud Drive destinations now free their local space as they go**: once iCloud confirms a file is uploaded, its local copy is released and only a placeholder remains — the file stays in iCloud and visible in the Files app. Waiting on uploads only happens when the device drops below 2 GB free, so a phone with room to spare backs up at full speed, and stalled uploads (no network, iCloud storage full) never slow the run down more than once. **New disk-space check** before a backup starts: it refuses only when nothing at all could be copied, so one oversized video no longer blocks the two hundred small files behind it — that file is reported individually and the rest are copied. Also fixed: a failed export left its partial file behind, so a run that was already short on space made itself worse with every retry. Drone and SD card backups are unchanged. Also fixed a deduplication edge case on the Photos path: after an SSD was disconnected mid-backup and reconnected on a later run, files already uploaded to a NAS were re-uploaded, because the existence check compared the NAS copy against Photos' *estimated* size rather than the real one — the NAS is now re-checked against the true size and skipped if already present. **Destination independence when one drive fails mid-backup:** unplugging an SSD (or a full iCloud Drive folder) no longer stops the other local destinations — each is dropped on its own, at both handle-setup and mid-write, and the rest keep going. **Correct multi-destination report:** a file copied only to a reconnected drive is no longer wrongly shown as "Copied" on the iCloud/NAS destinations that already held it — the summary now separates "copied this session" from "already present" per destination, and a destination that never received a file reads as Failed rather than silently appearing complete. |
| 2.2.1   | 41    | 2026-07-11 | Improvement | **Richer diagnostic logging (crash/jetsam tracing).** `DiagnosticLog` now records device environment on every key event to make one-shot crash reports self-sufficient. `[LAUNCH]` and `[MEMORY_WARNING]`/`[THERMAL]` carry an `envSnapshot()`: used/total RAM (`phys_footprint` — what iOS jetsam watches), free disk, thermal state, low-power mode, **phone language** (`lang=`) and **in-app language override** (`applang=`, `auto` = follows system) so support can reply in the user's language. A positive cold-start chain now proves a healthy launch: `[LAUNCH]` → `[STORE_OK]` (SwiftData store opened) → `[UI_READY]` (first frame, written once from `ContentView.onAppear`) → `[STARTUP_OK]` (onAppear finished, UI interactive, with store/destinations/sources/premium summary). Where the chain stops pinpoints the failure stage. New lifecycle breadcrumbs via `DiagnosticLog.installObservers()`: `[LIFECYCLE]` (background/foreground/terminate), `[THERMAL]`, `[POWER]` (low-power toggled), `[DATA_PROTECTION]` (device locked/unlocked). `[PROGRESS]`, `[BACKUP_START]` and `[BACKUP_END]` now include a compact `mem=used/total` tag, so a rising memory footprint approaching total RAM on constrained devices (e.g. iPhone XR / `iPhone11,8`, 3 GB) reveals a jetsam memory-kill. Logging only — no behavioural change. |
| 2.2.0   | 40    | 2026-07-06 | Feature | **NAS (SMB) backup destination.** Back up directly to a NAS over Wi-Fi via a native SMB2/3 client (AMSMB2/libsmb2) — on the LAN or **remotely** (e.g. via Tailscale/VPN, incl. cellular). Configure host/share/folder/credentials in Settings → Destinations → **NAS (SMB)** (Pro; password in Keychain) with a **Test connection** button; the NAS appears as a destination in the Dashboard with live capacity. Works alongside or instead of local SSDs (**NAS-only** supported). Files are uploaded **directly** (no local staging) and verified by full **SHA-256 re-download**. **Browse** tab: navigate the NAS folder-by-folder with on-demand download + QuickLook preview. **Mobile-data awareness**: a warning banner appears when backing up to the NAS over cellular, plus a **Stop** button to cancel any running backup (session marked Partial). Onboarding gains a NAS network diagram + feature bullet. Architecture: engines refactored onto a `BackupTarget` abstraction (`LocalFileTarget` / `SMBTarget`). Removed the DEBUG SMB Probe and the 3rd "SD Card (transit)" destination slot. Also fixed a dedup edge case — a corrupted/wrong-size file at a known path is now re-copied (coverage check verifies size, not just existence). **LUT Grade on NAS destinations (parity with local SSD):** the NAS Browse view now offers the full LUT Grade feature — assign a `.cube` LUT per NAS device folder, preview videos with the LUT applied in real time (full-screen player instead of QuickLook), and **multi-select** which videos to grade (a folder often mixes LOG and non-LOG footage, so grading is per-video, never "grade all"). Grading downloads each selected clip from the NAS → grades locally → uploads the HEVC result to a `Device (Graded)` folder on the NAS; already-graded files are skipped. Also fixed a LUT bug affecting both local and NAS: a failed export no longer leaves a partial file that was wrongly treated as "already graded". |
| 2.1.6   | 38    | 2026-06-23 | Improvement | Support email address changed to `photovideobackup@icloud.com` (was `supportphotovideobackup@gmail.com`); updated in app (Settings/Diagnostic mailto) and documentation. |
| 2.1.5   | 37    | 2026-06-02 | Improvement | Onboarding redesigned: setup diagram replaced by a swipeable carousel of 4 scenarios (Simple, Hub, iCloud + SSD, Advanced multi-SSD); new feature bullets for batch rename and iCloud Drive destination. |
| 2.1.4   | 36    | 2026-06-02 | Bug fix | Multi-SSD fixes: (1) copy was going to only one SSD even with both connected — `startAccessingSecurityScopedResource()` returning false on iOS for the second SSD was silently filtering it out; now all resolved destinations are kept regardless of return value, actual write errors are caught by the engine. (2) SHA-256 deduplication was skipping files on SSD2 when they existed on SSD1 — dedup now requires every destination root to have the file. (3) Mid-backup disconnection detection: `streamCopy` now handles per-destination write failures — on disconnection the destination is dropped and copying continues on remaining SSDs; if all SSDs disconnect the backup stops cleanly with `[DISC_ERROR]` in the diagnostic log. (4) Report redesigned for multi-destination sessions: summary shows Copied/Skipped/Failed per SSD; file detail is a single unified list with a coloured per-SSD status indicator (green = copied, orange = skipped, red = failed/disconnected). |
| 2.1.3   | 35    | 2026-06-02 | Bug fix | Fixed: second SSD connected via powered USB hub could appear as "Not connected" even when physically plugged in. Two root causes fixed: (1) destinations are now re-checked 800 ms after launch, matching the existing retry logic for external sources — handles the case where iOS hasn't fully mounted both volumes yet; (2) eliminated double bookmark resolution in `refreshDestinationStatuses()` (was resolving each bookmark twice in quick succession, which could cause the second volume to be missed). |
| 2.1.2   | 34    | 2026-06-02 | Improvement | Documentation link added in Settings → Support: opens the GitHub Pages documentation site in Safari. URL centralised in `AppConstants.documentationURL`. |
| 2.1.1   | 33    | 2026-06-02 | Bug fix | Localization fix: "Pattern" and "Tap a token to insert it. Anything else is literal text." in the batch rename sheet were missing translations — added FR, DE, ES, IT, PT, ZH-Hans, RU. |
| 2.1.0   | 32    | 2026-05-31 | Feature | SHA-256 content-based deduplication: files already backed up are detected by hash even if renamed at destination (cascade: hash check → physical check → copy). Batch rename in Browse tab: select files (with Select All / Deselect All), tap Rename, compose a pattern with date tokens ({YYYY}, {MM}, {DD}, {hh}, {mm}, {ss}), index ({index}), or original name ({original}); live preview of first 3 filenames; conflict auto-resolution; IndexStore updated after rename so deduplication remains accurate. |
| 2.0.1   | 31    | 2026-05-30 | Bug fix | Localization fixes: 718 missing translations added (FR/DE/ES/IT/PT/ZH/RU); byte-count units now follow app language; dates in History/Report now follow app language; folder structure names and Photos Library source name correctly localized; "Additional file types" delete gesture via Edit button; destination labels localized. Silent crash fix: `FileHandle.readData(ofLength:)` replaced by `InputStream` in both copy engines — I/O errors (SSD disconnected mid-backup) now surface as proper error messages. SwiftData corruption recovery: `IndexStore` no longer crashes at launch — deletes the corrupted store and restarts fresh, notifying the user. Diagnostic log (`pvb_diagnostic.log` in Documents/): records launch, device model, iOS version, scan start, backup progress every 50 files, errors, memory warnings, background task expiry — viewable and shareable from History tab. Support section in Settings with `photovideobackup@icloud.com`. |
| 2.0.0   | 30    | 2026-05-29 | Feature | Multi-language support (French, German, Spanish, Italian, Portuguese, Chinese Simplified, Russian) with in-app language picker in Settings → Language. Strings auto-follow iPhone language by default; users can force any supported language. Instant switch — no restart required. |
| 1.10.0  | 28    | 2026-05-09 | Feature | Delete source files from a completed backup session: "Delete Source Files…" button in the Report view (visible when source is connected); protected by a random 4-digit confirmation code. Works for Photos Library and external sources (SD card / USB). |
| 1.9.3   | 27    | 2026-05-08 | Improvement | Onboarding screen updated: added LUT Grade and GoPro mentions. |
| 1.9.2   | 26    | 2026-05-08 | Feature | LUT video grading (H.265/HEVC export) now requires Pro. Real-time LUT preview in the video player remains free. |
| 1.9.1   | 25    | 2026-05-08 | Bug fix | LUT Grade bug fixes: Grade button re-enables after a completed session; (Graded) sibling folder appears immediately in Browse without requiring a manual refresh; (Graded) folders no longer show the LUT Grade section. |
| 1.9.0   | 24    | 2026-05-08 | Feature | GoPro HERO support: auto-detection via DCIM/100GOPRO pattern; scans .mp4 and .jpg; skips .lrv proxy and .thm thumbnail files. SHA-256 verification now shown in completion banner ("N verified by SHA-256"), in Report summary, and in per-file report rows. Videos in Browse tab now play full-screen in a native AVPlayerViewController overlay. LUT Grade feature in Browse tab: assign a .cube LUT per device folder, preview videos with LUT applied in real time, and grade all footage to a sibling "Device (Graded)" folder in H.265/HEVC (skips already-graded files). |
| 1.8.0   | 23    | 2026-05-03 | Feature | Mac "Designed for iPad" support: folder picker via NSOpenPanel (UIDocumentPickerViewController fails via XPC on Mac), security-scoped bookmarks created/resolved with withSecurityScope. Added "Additional file types" setting (Settings → Backup) to copy arbitrary extensions (e.g. GPS logs) alongside media, for all device types. Report Skipped section now shows source folder and explains why files were not re-copied. |
| 1.7.0   | 22    | 2026-05-02 | Feature | History rows and Report summary now show the destination drive(s): "VolumeName / FolderName". Stored as `destinationDisplayNames` on BackupSession (lightweight SwiftData migration). Old sessions fall back to path last component. |
| 1.6.0   | 21    | 2026-05-01 | Feature | App Store review prompt after the 3rd successful backup with ≥ 10 files copied, then every 15 substantial backups, with a 60-day minimum between requests. Uses SKStoreReviewController via SwiftUI @Environment(\.requestReview). |
| 1.5.3   | 20    | 2026-05-01 | Bug fix | Browse tab now shows all files at every folder level, including files at the root of a device folder when subfolder also exist (mixed Flat + date-organized content). Replaced fixed-depth DateListView with a recursive FolderContentView. |
| 1.5.2   | 19    | 2026-05-01 | Bug fix | Browse tab now detects folder structure from disk instead of relying on the current folderOrganization setting. Switching backup modes no longer causes the browser to show nothing. |
| 1.5.1   | 18    | 2026-04-30 | Bug fix | Error reasons now persisted and visible in the Report: `IndexedFile` gained an `errorNote` field (lightweight SwiftData migration); both engines store the error message per failed file. Report shows the reason once at top when all failures share the same error, or per-file when mixed. Session status now correctly uses `.failed` (red) instead of `.completed` when no files were copied. Push notification updated accordingly. `ExportError` messages made user-friendly. |
| 1.5.0   | 17    | 2026-04-27 | Feature + Fix | Memory fix for large libraries: engines no longer hold all IndexedFile objects in memory (session.files.append removed — SwiftData manages via inverse relationship); batch save every 500 files + 10ms yield to let iOS breathe; stats computed via counters instead of scanning session.files. Added "Max files per session" setting (0 = unlimited, default): backup stops at the limit and is marked Partial. Partial status shown in History, Report, and notification.  |
| 1.4.0   | 16    | 2026-04-27 | Feature | Added backup folder structure setting: Flat (no subfolders), By Month, By Date (default), By Year / Month. Setting is in Settings → Backup. The Browse tab adapts its navigation depth accordingly. |
| 1.3.4   | 15    | 2026-04-21 | Improvement | Offline external sources now reconnect automatically: bookmark resolution is retried on app foreground, on Refresh button, and after an 800ms delay at launch (to let iOS finish mounting the volume). "Reconnect" button remains as fallback when the bookmark is genuinely invalidated. |
| 1.3.3   | 14    | 2026-04-21 | Bug fix | Added "Reconnect" button on offline external sources: iOS security-scoped bookmarks are mount-instance scoped; ejecting and reinserting an SD card invalidates the old bookmark. The Reconnect button re-opens the folder picker and refreshes the bookmark without asking for a new name. |
| 1.3.2   | 13    | 2026-04-21 | Bug fix | Fixed: Backup buttons not disabled when SSD destination is configured but disconnected (was only checking if list was empty, not if connected). Fixed: external source bookmark not resolving across app launches — security-scoped bookmark is now created immediately in the UIDocumentPicker callback, before security scope can expire. |
| 1.3.1   | 12    | 2026-04-21 | Bug fix | Fixed: SD card / external source disappeared from the list after closing and reopening the app when the bookmark could not be resolved. Offline sources now remain visible (grayed, "Not connected") instead of silently vanishing. |
| 1.3.0   | 11    | 2026-04-21 | Feature | Added onboarding screen (shown once at first launch) with a setup diagram; added About section in Settings showing app version. |
| 1.2.1   | 10    | 2026-04-20 | Bug fix | Fixed: adding a source via "Add Source" did not persist the bookmark — the source was lost after closing and reopening the app. |

## Regression test system

Target XCTest `PhotoVideoBackupTests` added to the project. **No production code was modified.**

### Architecture

Tests run on **"My Mac (Designed for iPad)"** — no iOS simulator needed. Execution takes < 1 s for a full scenario run.

The system has two layers:
- **Support/** — DSL infrastructure (simulators, assertions, base class)
- **ScenarioTests/** — one file per feature area, one `func test_…` per scenario

### Simulated peripherals

A `SimulatedSDCard` creates a real temp directory in `/tmp/` that mirrors the exact DCIM structure the production scanners expect. A `SimulatedSSD` creates an empty temp directory used as the backup destination. Both are cleaned up in `tearDown()`.

| Peripheral | DCIM structure created |
|---|---|
| `.djiMini3Pro` | `DCIM/DJI_0001/` — files inside |
| `.dji360` | `DCIM/100MEDIA/` — files inside |
| `.insta360X5` | `DCIM/` — files directly inside |
| `.generic` | files at root, no DCIM |

`TestFile(name:sizeInBytes:date:)` creates a real file filled with `0xAB` bytes. **Set `date:` explicitly** so that `FolderOrganization.destinationURL` produces a deterministic path (tests use `Date.scenarioDefault` = 2024-01-14 UTC).

### DSL vocabulary (ScenarioTestCase methods)

```swift
// Peripherals
let sd  = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [...])
let ssd = ssd(named: "TravelSSD")

// Settings (maps directly to the same UserDefaults keys as production)
use(.folderOrganization(.byDate))
use(.maxFiles(2))
use(.additionalExtensions(["gpx"]))

// Run the real scanner + engine (no mocks)
await backup(from: sd, to: ssd)

// Assertions
expect(.copied(2))
expect(.skipped(0))
expect(.failed(0))
expect(.partial)                                          // wasLimited=true
expect(.fileExists("DJI Mini 3 Pro/2024-01-14/file.MP4", on: ssd))
expect(.fileAbsent("file.DNG", from: ssd))
```

### Scenario comment convention (mandatory)

Every `func test_…` must open with a structured comment:

```swift
// SCENARIO: Short title (one line)
// What specific behavior this verifies — written for a human reader,
// not for the implementation. Mention edge cases if any.
func test_something() async throws {
```

### How to add a new scenario

1. Open the appropriate file in `ScenarioTests/` (or create a new `XxxTests.swift` that subclasses `ScenarioTestCase`).
2. Add the new file to the `PhotoVideoBackupTests` target in Xcode (or add its UUIDs to `project.pbxproj`).
3. Write the function with the mandatory comment, then DSL commands.
4. Run `make test-scenario` to verify.

### Running tests

```bash
make test-scenario   # BackupFromSDCardTests only
make test-all        # entire PhotoVideoBackupTests target (Mac "Designed for iPad")
make testiphone      # entire target on iPhone 17 Pro simulator
make build-test      # compile only, no execution
```

### project.pbxproj UUID block reserved for test target

All test-related UUIDs start with `CC000000000000000000` to avoid collisions. Do not reuse these prefixes for app-side objects. When adding new test files, use UUIDs of the form `CC00000000000000001XXX00` (fileRef) and `CC00000000000000002XXX00` (buildFile), incrementing XXX beyond `008`.

### Testing NAS / remote logic without a live share

The engines that touch SMB cannot run in a unit test (no live NAS, and `PHBackupEngine` also needs Photos). The strategy is to **keep the risky decisions as pure, target-agnostic functions** and test those against a fake remote:

- `partitionRemotesByPresence(_:relativePath:expectedSize:)` (`BackupTarget.swift`) — the remote-upload dedup decision, extracted from `PHBackupEngine.uploadToRemotes` precisely so it is testable. This is where the "re-uploaded a file the NAS already had" bug lived; `RemoteDedupTests` locks it.
- `coveredDestinationPaths(...)` — the SHA cascade, already pure.
- `FakeRemoteTarget` (`Support/`) — an in-memory `RemoteBackupTarget` backed by a temp directory. `upload` copies into the tree and increments `uploadCount`; `seed(...)` places a file as if a prior run had uploaded it. A test asserts `uploadCount == 0` to prove no bandwidth was spent.

**When adding remote behaviour, push the decision into a pure function and test it there** — do not try to drive the engine.

**Live NAS integration test (`make test-nas`).** `LiveNASIntegrationTests` does a real SMB round-trip (connect → upload → SHA-256 verify → dedup re-check → delete) against a NAS described by `nas-test-config.json` at the repo root. That file holds credentials, is gitignored (bare filename, so it is ignored at any path), and is read at runtime — never committed, never printed. Two constraints learned the hard way:
- **It must run on the iOS Simulator, not "Designed for iPad".** A Mac-sandboxed Designed-for-iPad test process cannot read a file outside its container (`readable=false`), so it can never load the credentials; the simulator can. `make test-nas` pins the simulator destination.
- **`make test-all` excludes it via `-skip-testing`** — that flag, not an env var, is the hermetic boundary (a Designed-for-iPad bundle does not inherit the shell environment, so env-var gating is unreliable). The test also self-skips when the config file is absent, so it is safe on any machine.
- Connection reuses `DestinationManager.makeSMBTarget(from:password:)`, split out of `makeSMBTarget()` specifically so the test connects from its own credentials without touching the user's saved NAS config. Cleanup uses `SMBTarget.delete(forRelative:)`.

### What the tests do NOT cover (and why)

- **PHBackupEngine** — requires `PHPhotoLibrary` / `PHAsset`, which cannot be seeded in a unit test without the real Photos framework. Test this manually on device.
- **DestinationManager bookmarks** — security-scoped bookmarks are sandbox-tied; no meaningful test possible outside the real app sandbox.
- **UI interactions** — DashboardView, SettingsView, etc. are excluded by design; they have no logic to test independently.
- **BackupBrowserViewModel / Browse tab** — assertions stop at the filesystem level (`FileManager.fileExists`); no Browse-layer code is invoked. This is intentional: (1) `BackupBrowserViewModel.startAccess()` requires a real security-scoped bookmark, which cannot be created in a unit test sandbox; (2) thumbnail generation (ImageIO / AVAssetImageGenerator) requires real media files, not the dummy `0xAB` byte fixtures used in tests. The filesystem check is sufficient: if `expect(.fileExists(...))` passes, `BackupBrowserViewModel` will find the file when it enumerates the same directory — it performs no additional validation beyond `FileManager.contentsOfDirectory`.

## IAP price
- Pro upgrade price: **$1.99** (changed from $4.99).
- Price is referenced in `Configuration.storekit`, `Products.storekit`, and `index.md` (repo root).
- The real price on the App Store is set in **App Store Connect → Pricing and Availability** — the `.storekit` files only affect the simulator and TestFlight.
