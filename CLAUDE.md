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
- **Always increment the version before any App Store delivery**, without waiting to be asked.
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

## Known iOS API constraints
- `URLResourceValues.volumeURL` does not exist on iOS — use the NSURL bridge: `(url as NSURL).getResourceValue(&value, forKey: .volumeURLKey)`. Note: this method is `throws` in Swift, returns `Void`, not `Bool` — use `try?` and check the out-parameter separately.
- SourceKit errors about `UIKit`, `UIViewControllerRepresentable`, `UIDocumentPickerViewController` in `SettingsView.swift` are persistent false positives from the indexer — they do not reflect real compilation errors.

## DestinationManager — companion UserDefaults keys
Each bookmark key (e.g. `PhotoVideoBackup.bookmark.ssd1`) has two companion entries saved at `saveBookmark` time:
- `<key>.displayName` — volume localized name (used for offline display when disk is disconnected)
- `<key>.folderPath` — folder path relative to volume root, e.g. `X/Y` (computed via `volumeURLKey` NSURL bridge)
Both must be cleared in `clearBookmark`. This pattern allows destinations to remain visible (grayed) when the drive is unplugged.

## Device support — file types & folder structures
- **DJI Mini 3 Pro**: DCIM folders prefixed `DJI_` → `mp4`, `jpg`, `jpeg`, `dng` + `.srt` telemetry
- **DJI 360 / Action** (`DeviceType.dji360`): DCIM folders matching `^\d{3}` (e.g. `100DJIMED`, `100MEDIA`) → `mp4`, `mov`, `jpg`, `jpeg`, `dng`, `mp3`, `osv` + `.srt`
- **Insta360 X5**: DCIM, `.insv` / `.insp` / `.lrv`
- **Generic**: `mp4`, `mov`, `avi`, `jpg`, `jpeg`, `heic`, `png`, `dng`, `raw`, `cr2`, `cr3`, `arw`, `nef`, `rw2`, `insv`, `insp`, `braw`, `mp3`

## Background execution
- `UIApplication.shared.isIdleTimerDisabled = true` while backup runs — prevents auto screen lock.
- `UIApplication.shared.beginBackgroundTask` gives ~30 s of continued execution if user backgrounds the app.
- Both are managed in `DashboardViewModel.beginBackgroundExecution()` / `endBackgroundExecution()`, called at start/end of every backup (including all early-return error paths).

## UIDocumentPickerViewController
- Set `picker.directoryURL` to open the picker at a specific location (iOS 13+).
- The picker itself allows creating folders via the "…" menu — no need to implement folder creation in-app.
- `FolderPickerView` takes an `initialDirectory: URL?` parameter; pass `nil` for default behaviour.

## Backup progress — ETA
- `DashboardViewModel` tracks `backupStartDate: Date?` and exposes `estimatedSecondsRemaining: Double?`.
- ETA is computed from elapsed time and `overallProgress` (elapsed / progress × (1 − progress)), displayed after 5 s with >1 % progress.
- `resetSpeedTracking()` is called at backup start and `finishSession`. `updateSpeedEstimate(_:)` is called inside every `for await progress in stream` loop.

## Local notifications
- `UNUserNotificationCenter` permission is requested once at launch via `DashboardViewModel.requestNotificationPermission()`, called from `PhotoVideoBackupApp.onAppear`.
- `NotificationDisplayDelegate` (in `PhotoVideoBackupApp.swift`) implements `UNUserNotificationCenterDelegate` and returns `.banner + .sound` so notifications appear even when the app is in the foreground.
- A notification is sent at the end of every backup inside `finishSession()` via `sendCompletionNotification(_:)`.

## Browse tab — BackupBrowser module
- `BackupBrowserViewModel` (`Modules/BackupBrowser/`) manages security-scoped access to SSD destinations: call `startAccess()` on tab appear, `stopAccess()` on disappear. Thumbnails are cached in memory for the session.
- `BackupBrowserView` (`Views/`) provides 3-level navigation: device folder → date folder → media grid.
- Backup folder structure on SSD: `{destination}/{deviceName}/{yyyy-MM-dd}/{filename}`.
- Thumbnail generation: ImageIO (`CGImageSourceCreateThumbnailAtIndex`) for images, `AVAssetImageGenerator` for videos.
- Full-size image in `MediaDetailView` is loaded via ImageIO capped at 2048 px to avoid memory pressure on large RAW files.

## Browse tab — multi-select and share
- Selection mode is local state in `MediaGridView` (`@State selectionMode`, `selectedURLs: Set<URL>`).
- On share: selected files are copied to a unique temp directory (`FileManager.default.temporaryDirectory/pvb_share_{UUID}/`) in a detached task, then presented via `UIActivityViewController` (`ActivityShareSheet`).
- Temp directory is deleted in the `onDismiss` handler of the sheet (via `cleanupTempFiles()`).
- Security-scoped access opened in `BackupBrowserView.onAppear` remains valid throughout the entire navigation stack — no need to re-open per operation.

## Version Changelog
Keep this section up to date with every release. Use it to write App Store release notes.

| Version | Build | Date       | Type    | Description |
|---------|-------|------------|---------|-------------|
| 1.2.1   | 10    | 2026-04-20 | Bug fix | Fixed: adding a source via "Add Source" did not persist the bookmark — the source was lost after closing and reopening the app. |

## IAP price
- Pro upgrade price: **$1.99** (changed from $4.99).
- Price is referenced in `Configuration.storekit`, `Products.storekit`, and `docs-publish/index.md`.
- The real price on the App Store is set in **App Store Connect → Pricing and Availability** — the `.storekit` files only affect the simulator and TestFlight.
