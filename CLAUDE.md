# PhotoVideoBackup — Project Rules for Claude

## Language
**All app UI strings must be in English.** This includes error messages, labels, subtitles, placeholders, alerts, and button titles. The user communicates in French but the app itself is entirely in English.

## Documentation
- User-facing documentation is in `docs-publish/` — this is a separate git repository published on GitHub Pages
- GitHub repo: `git@github.com:gduval78/PhotoVideoBackup.git`
- To publish: `cd docs-publish && git add -A && git commit -m "..." && git push origin main`
- Internal documentation (not published) is in `Documentation/UserGuide.md` — keep it in sync with `docs-publish/index.md`
- Screenshots are in `docs-publish/images/`

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

## Backup engine architecture — memory & batching

Both `PHBackupEngine` and `FileCopyEngine` use the same pattern to avoid memory pressure on large libraries:

- **No `session.files.append`** — IndexedFile objects are inserted directly into the SwiftData context (`IndexStore.shared.context.insert(indexed)`). SwiftData manages the relationship via its inverse; never fault in the full `session.files` collection during a backup run.
- **Batch save every 500 files**: `if index > 0 && index % Self.batchFlushInterval == 0 { await MainActor.run { IndexStore.shared.save() }; try? await Task.sleep(nanoseconds: 10_000_000) }` — the 10ms sleep gives iOS room to reclaim memory between batches.
- **Stats via actor-isolated counters**: `_copiedCount`, `_skippedCount`, `_failedCount`, `_totalBytesCopied`, `_wasLimited` are actor-isolated vars on the engine. They are read after the stream completes via `engineResult: EngineResult`. `finishSession` uses these counters directly — it never scans `session.files`.

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

## Browse tab — multi-select and share
- Selection mode is local state in `MediaGridView` (`@State selectionMode`, `selectedURLs: Set<URL>`).
- On share: selected files are copied to a unique temp directory (`FileManager.default.temporaryDirectory/pvb_share_{UUID}/`) in a detached task, then presented via `UIActivityViewController` (`ActivityShareSheet`).
- Temp directory is deleted in the `onDismiss` handler of the sheet (via `cleanupTempFiles()`).
- Security-scoped access opened in `BackupBrowserView.onAppear` remains valid throughout the entire navigation stack — no need to re-open per operation.

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

## Documentation maintenance — checklist for every feature session

**After any feature or UI change, always do the following before closing the session:**

1. **Update `docs-publish/index.md`** — version header, affected sections (Settings, History, Browse, Completion, FAQ). The user cannot do this without reading the code; you can.
2. **Update `Documentation/UserGuide.md`** — keep it in sync with `docs-publish/index.md`.
3. **Update the Version Changelog** below (already in CLAUDE.md).
4. **Identify screenshots that need retaking** — you cannot take device screenshots yourself. At the end of the session, list explicitly which screenshots in `docs-publish/images/` are now stale and what the new screen should show, so the user knows exactly what to capture. Common candidates:
   - Settings screen: any time a new setting is added or a section changes
   - Dashboard/History/Report: any time a new status, badge, or row format changes
   - Browse tab: any time navigation depth or grid layout changes
5. **Commit `docs-publish/` separately** with `cd docs-publish && git add -A && git commit -m "..." && git push origin main`.

**What you cannot do alone (flag to the user):**
- Take screenshots on a real device or simulator
- Verify App Store Connect metadata or pricing
- Submit to the App Store

## Version Changelog
Keep this section up to date with every release. Use it to write App Store release notes.

| Version | Build | Date       | Type    | Description |
|---------|-------|------------|---------|-------------|
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

### What the tests do NOT cover (and why)

- **PHBackupEngine** — requires `PHPhotoLibrary` / `PHAsset`, which cannot be seeded in a unit test without the real Photos framework. Test this manually on device.
- **DestinationManager bookmarks** — security-scoped bookmarks are sandbox-tied; no meaningful test possible outside the real app sandbox.
- **UI interactions** — DashboardView, SettingsView, etc. are excluded by design; they have no logic to test independently.
- **BackupBrowserViewModel / Browse tab** — assertions stop at the filesystem level (`FileManager.fileExists`); no Browse-layer code is invoked. This is intentional: (1) `BackupBrowserViewModel.startAccess()` requires a real security-scoped bookmark, which cannot be created in a unit test sandbox; (2) thumbnail generation (ImageIO / AVAssetImageGenerator) requires real media files, not the dummy `0xAB` byte fixtures used in tests. The filesystem check is sufficient: if `expect(.fileExists(...))` passes, `BackupBrowserViewModel` will find the file when it enumerates the same directory — it performs no additional validation beyond `FileManager.contentsOfDirectory`.

## IAP price
- Pro upgrade price: **$1.99** (changed from $4.99).
- Price is referenced in `Configuration.storekit`, `Products.storekit`, and `docs-publish/index.md`.
- The real price on the App Store is set in **App Store Connect → Pricing and Availability** — the `.storekit` files only affect the simulator and TestFlight.
