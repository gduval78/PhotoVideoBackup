UI = {
    "guide_title": "PhotoVideoBackup — User guide",
    "tagline": "Back up your photos and videos to an external SSD, an SD card or a NAS — from your iPhone or your Android phone.",
    "version_line": "Guide for PhotoVideoBackup 2.6 (iPhone, iOS 16 or later) and 1.0 (Android 9 or later)",
    "toc": "Contents",
    "privacy_link": "Privacy policy",
    "contact": "Support",
    "back": "Back to the user guide",
    "footer": "PhotoVideoBackup · Photos and videos, safely copied",
    "chooser_tagline": "Back up your photos and videos safely",
    "chooser_privacy": "Privacy policy",
}

GUIDE = [
    ("what", "What is PhotoVideoBackup?", [
        ("p", "PhotoVideoBackup copies your photos and videos from your phone — or from a camera memory card — to a portable SSD, a USB drive or a <b>NAS</b>. Your media never goes through an online service: the app has no server and no account."),
        ("ul", ["Your phone storage is full and you want to free space safely.", "You are back from a trip with an SD card full of footage (DJI, GoPro, Insta360, Blackmagic…) and want to secure it at once.", "You want a personal copy that does not depend on iCloud or Google Photos."]),
        ("p", "<b>What makes it safe?</b> Every copied file is read back and checked with a mathematical fingerprint (SHA-256). If a single byte is wrong, the app tells you — you never end up with a silently corrupted backup."),
        ("p", "The app only <b>copies</b>. It never moves or deletes anything from the source, unless you explicitly ask for it after a backup (see “History and reports”)."),
    ]),
    ("pro", "Free and Pro", [
        ("p", "PhotoVideoBackup is free to download. One <b>Pro</b> purchase — paid once, <b>no subscription</b> — unlocks the advanced features:"),
        ("table", ["Feature", "Free", "Pro"], [
            ["Back up the photo library to one drive or folder", "✓", "✓"],
            ["Browse and preview backups (LUT preview included)", "✓", "✓"],
            ["Back up camera cards and USB drives (SD, DJI, GoPro, Insta360…)", "—", "✓"],
            ["Mirror to a second drive", "—", "✓"],
            ["Back up to a NAS over Wi-Fi", "—", "✓"],
            ["Grade LOG videos with a LUT (H.265 export)", "—", "✓"],
        ]),
        ("fig", "paywall", "The upgrade screen. Open it from the Settings tab whenever you like."),
    ]),
    ("need", "What you need", [
        ("table", ["", "iPhone / iPad", "Android"], [
            ["The device", "An iPhone with a USB-C port (iPhone 15 or later), iOS 16 or later", "An Android phone or tablet, Android 9 or later"],
            ["A drive", "Any USB-C SSD (Samsung T7, SanDisk Extreme, WD My Passport…)", "Any USB-C SSD or USB drive, or a folder on the phone"],
            ["A hub or reader (optional)", "A small USB-C hub to plug an SSD and a card reader together", "A USB-C card reader, or an OTG hub"],
        ]),
        ("note", "Copying a lot of video uses battery. Plug your phone in, or start with a good charge."),
    ]),
    ("start", "First launch and permissions", [
        ("p", "A welcome screen presents the app and five typical set-ups — from a simple phone → SSD to a NAS reached over a VPN. Tap <b>Get Started</b>."),
        ("fig", "onboarding_simple", "The simplest set-up: phone → SSD."),
        ("ul", ["<b>iPhone / iPad</b>: allow <b>Full Access</b> to your photo library. Without it the app cannot read your photos.", "<b>Android</b>: allow access to your photos and videos. Also allow access to the <b>location of your photos</b> — without it Android removes the GPS data from the files it hands over, and the backup would not be the original. Allow notifications so you are told when a backup ends."]),
        ("note", "The app only reads your photos in order to copy them. It never modifies, shares or uploads them anywhere."),
    ]),
    ("setup", "Set up your device name and destination", [
        ("ol", ["Open the <b>Settings</b> tab. In the <b>Device</b> section, type a <b>folder name</b> — for example <i>Anna’s iPhone</i> or <i>Pixel 8</i>. It becomes the folder name on the drive, so two phones saving to the same drive stay separate. A backup does not start until a name is set.", "Plug in your drive.", "Under <b>Destinations</b>, tap <b>Choose…</b> and pick the drive, or a folder on it, in the system file browser. On Android you can also pick a folder in the phone’s own storage.", "The drive name appears in Settings and on the Backup tab, with its free space. You only do this once: the app recognises the drive the next time."]),
        ("fig", "settings_configured", "Settings: device name and the first destination."),
        ("note", "A destination can also be a folder in <b>iCloud Drive</b> (iPhone) — the app releases the local copy once iCloud confirms the upload, so the phone does not fill up."),
    ]),
    ("photos", "Back up your photos and videos", [
        ("p", "Open the <b>Backup</b> tab. At the top you see your destinations, with their free space. In <b>Sources</b>, the <b>Photos Library</b> row shows your device name. Tap its <b>Backup</b> button."),
        ("fig", "dashboard_ready", "The Backup tab: destination connected, Photos Library ready."),
        ("p", "The app scans the library, then copies. The <b>first backup is the longest</b>; the next ones only copy what is new, and are much faster."),
        ("ul", ["Photos stored only in iCloud / Google Photos are downloaded first — that takes a connection and some time.", "The app copies each file straight to the destination, so it works even when the phone is almost full.", "You can leave the app: a notification tells you when the backup ends."]),
    ]),
    ("sd", "Back up a camera card (Pro)", [
        ("ol", ["Plug the card reader into the phone and insert the card (use a hub if the SSD must stay plugged in too).", "On the Backup tab, tap <b>Add Source (SD Card, USB Drive…)</b>, find the card in the file browser and confirm.", "Give the source a name — <i>Blackmagic</i>, <i>Trip to Japan</i>… The device type is recognised by itself.", "Tap <b>Backup</b> on the source row."]),
        ("table", ["Recognised device", "What is backed up"], [
            ["DJI Mini 3 Pro", "Photos, videos, DNG and the telemetry (.srt)"],
            ["DJI 360 / Action (Neo 2…)", "Videos, photos, DNG, audio and the telemetry (.srt)"],
            ["Insta360 (X5…)", ".insv, .insp and .lrv files"],
            ["GoPro HERO", "Videos and photos; the proxy (.lrv) and thumbnail (.thm) files are skipped"],
            ["Anything else", "Common photo, video and RAW formats"],
        ]),
        ("note", "A card ejected and put back needs one tap on <b>Reconnect</b>: the system gives the app a new access each time the card is mounted. The name and type of the source are kept."),
        ("p", "To remove a source from the list, use the red <b>–</b> (iPhone) or the remove button of the row (Android). This deletes no file."),
    ]),
    ("progress", "While the backup runs", [
        ("p", "A <b>Backup in Progress</b> panel appears the moment you tap Backup. First <b>Preparing…</b> (connecting to your destinations), then <b>Analyzing source…</b> with a live count of files found — on a large library this can take a moment, it is not stuck."),
        ("fig", "progress_backup", "Backup in progress: percentage, files done, time remaining, current file."),
        ("table", ["Phase", "What the app is doing"], [
            ["Scanning", "Counting the files and checking which ones need to be copied."],
            ["Copying", "Writing the file to the destination."],
            ["Verifying", "Reading the copy back and comparing it with the original."],
            ["Skipped", "The file is already backed up — nothing to do."],
        ]),
        ("note", "Do not unplug the drive or the card while a backup runs. If a drive disappears anyway, the other destinations carry on, and the session is marked <b>Partial</b>."),
        ("p", "A <b>Stop</b> button ends the backup cleanly at any time. Settings → Backup also has a <b>Max files per session</b> limit: leave it empty for unlimited."),
    ]),
    ("done", "When the backup is done", [
        ("fig", "completion_banner", "The completion banner: copied, skipped, failed, size and duration."),
        ("table", ["Number", "Meaning"], [
            ["Copied", "Files saved to the destination for the first time."],
            ["Skipped", "Files that were already there — normal and safe."],
            ["Failed", "Files that could not be copied (rare)."],
        ]),
        ("p", "A failure comes from a damaged card, a full drive, a connection that dropped, or one single file too large for the free space — only that file is reported and the rest continues. Free some space or reconnect, and run the backup again: the missing files are picked up."),
    ]),
    ("history", "History and reports", [
        ("p", "The <b>History</b> tab lists every backup: source, destinations, folder structure, number of files, and a colour — green for success, orange for <b>Partial</b>, red for failures."),
        ("fig", "history_list", "History: one completed session."),
        ("p", "<b>Partial</b> means the backup stopped early, for one of three reasons that the report states: you tapped <b>Stop</b>, the <b>file limit</b> was reached, or a <b>destination disconnected</b>. Reconnect the drive and run again — it resumes where it stopped."),
        ("p", "Tap a session for its report: summary, SHA-256 status, and the lists of copied, skipped and failed files — with the reason of each failure. With two destinations the report shows each drive separately."),
        ("fig", "report_summary", "A session report."),
        ("p", "<b>Delete Source Files…</b> frees space on the card or in the library once you are satisfied with the backup. It only offers files that were copied <i>and</i> verified, and you must type a four-digit code to confirm. Your backup is not touched. On iPhone and Android the system asks for one more confirmation for photos."),
        ("fig", "report_delete_confirm", "Typing the code confirms the deletion."),
        ("note", "<b>Clear History</b> only removes the records inside the app. Your files stay where they are."),
    ]),
    ("browse", "Browse, view and share your backups", [
        ("p", "The <b>Browse</b> tab shows what is on your drives, inside the app: one folder per device, then your date folders, then a grid of thumbnails. Tap a photo to open it full screen — swipe to move between files, pinch to zoom — or tap a video to play it. The drive must be plugged in."),
        ("fig", "browse_device_folders", "Browse: the device folders of a drive."),
        ("fig", "browse_media_grid", "The media grid of a day."),
        ("p", "To send files elsewhere: tap <b>Select</b>, tick the files, then <b>Share</b> — AirDrop, messages, e-mail, another app."),
        ("fig", "android_viewer", "Android: the full-screen viewer."),
        ("p", "On a NAS, Browse lists the files and downloads each one only when you open it."),
    ]),
    ("naming", "Folders and file names", [
        ("p", "In <b>Settings → Backup</b>, <b>Folder structure</b> sets how a device folder is organised: <i>Flat</i>, <i>By month</i>, <i>By date</i> (default) or <i>By year / month</i>. The Browse tab adapts to whatever is on the drive."),
        ("p", "<b>File naming</b> gives every file its final name <b>as it is first copied</b> — it is never stored under its camera name and renamed afterwards. Turn on <b>Rename files during backup</b> and edit the pattern: tap a token to insert it, anything else is literal text. An <b>Example</b> line shows the result."),
        ("fig", "settings_file_naming", "File naming: pattern, tokens and live example."),
        ("table", ["Token", "Replaced by"], [
            ["{YYYY} {MM} {DD}", "Year, month, day of the capture"],
            ["{hh} {mm} {ss}", "Hour, minute, second of the capture (local time)"],
            ["{device}", "The device folder name, without spaces"],
            ["{original}", "The original file name, without its extension"],
        ]),
        ("ul", ["<b>Nothing is ever overwritten.</b> If the name is taken by a different file, the new one gets a <code>-1</code>, <code>-2</code>… suffix. Include the seconds in your pattern so two shots taken together keep different names.", "<b>Duplicates are recognised by that name.</b> A file already backed up is skipped — even if you have edited it since — and a different file with the same name is kept apart.", "<b>Existing files are not renamed.</b> The profile applies to files copied from now on. With the profile off (default) files keep their camera names."]),
        ("p", "You can also add <b>extra file extensions</b> to copy next to the media — for example <code>gpx</code> GPS logs."),
    ]),
    ("lut", "LUT Grade: give LOG footage its look (Pro)", [
        ("p", "Footage shot in <b>LOG</b> (DJI D-Log M, GoPro Protune…) looks flat and grey until a <b>LUT</b> is applied. In Browse, assign a LUT to a device folder to preview and grade without leaving the app."),
        ("ol", ["Open a device folder and, in <b>LUT Grade</b>, tap <b>Assign LUT…</b> then <b>Import LUT (.cube)</b>. Any standard <code>.cube</code> file works (DaVinci Resolve, Final Cut Pro, your camera maker).", "Tap any video of that folder: it plays with the LUT applied in real time. This preview is <b>free</b>.", "To create permanent copies (Pro), tap <b>Select</b>, choose the videos, then <b>Grade</b>. Each one is re-encoded in <b>H.265</b> with the LUT baked in, into a sibling folder named <b>Device (Graded)</b>."]),
        ("fig", "browse_lut_picker", "Choosing a LUT for a folder."),
        ("fig", "android_lut", "Android: the LUT Grade section of a device folder."),
        ("ul", ["Grading is per video, never “everything” — a folder often mixes LOG and ordinary clips, and a LOG LUT would ruin the ordinary ones.", "Already-graded files are skipped, so it is safe to run again. Cancel at any time: finished files are kept.", "Grading is demanding: keep the app open and the drive connected. The phone may get warm.", "On a NAS the clips are downloaded, graded on the phone and uploaded to a <b>Device (Graded)</b> folder on the NAS — slower, and it uses data."]),
    ]),
    ("mirror", "Two destinations at once (Pro)", [
        ("p", "In Settings, add a second destination: every file is copied to both at the same time — two drives, or a drive and a NAS. The backup is not twice as long. If one destination fails or disappears, <b>the other carries on</b>, and the report says which one is missing what."),
        ("note", "If only one of the two drives is plugged in when you start, the app still copies to it and marks the session as incomplete for the other."),
    ]),
    ("nas", "Back up to a NAS over Wi-Fi (Pro)", [
        ("p", "Instead of — or in addition to — a drive, you can back up straight to a <b>NAS</b> (Synology, QNAP, TrueNAS, any device that speaks SMB) over the network. No cable, no cloud, and each file is verified by SHA-256."),
        ("ol", ["On the NAS, enable <b>SMB file sharing</b> and give a user read and write access to a shared folder.", "In the app: <b>Settings → Destinations → NAS (SMB)</b>.", "Fill in the <b>host</b> (e.g. <code>192.168.1.20</code>), the <b>share</b> (e.g. <code>photo</code>), an optional <b>folder</b>, and your <b>user name</b> and <b>password</b>. The password is stored in the iOS Keychain or the Android Keystore.", "Tap <b>Test connection</b>: <i>“Connected — N item(s) found.”</i> Then <b>Save</b>."]),
        ("p", "The NAS now appears on the Backup tab with its free space. You can back up <b>away from home</b> if the NAS is reachable — the simplest secure way is a VPN such as <b>Tailscale</b>: install it on the NAS and on the phone, then use the NAS’s <code>100.x.x.x</code> address as host."),
        ("note", "Over mobile data, an orange banner warns you that large videos can use a lot of data; <b>Stop</b> halts the backup (it is marked Partial)."),
    ]),
    ("android", "Android and iPhone: what differs", [
        ("p", "The two apps share the same engine: same duplicate detection, same naming, same SHA-256 verification, same index — a backup started on one is recognised by the other."),
        ("table", ["", "iPhone / iPad", "Android"], [
            ["Library source", "Photos Library", "Gallery (photos and videos)"],
            ["Destination", "Folder chosen in Files (SSD, iCloud Drive, SMB)", "Folder chosen with the system picker (SSD, USB, phone storage), NAS"],
            ["Background", "About 30 seconds, then the screen stays on during the backup", "A foreground notification keeps it running, with a Stop button"],
            ["Pro", "In-app purchase (App Store)", "One-time purchase (Google Play)"],
            ["Mac", "Runs on Apple-silicon Macs (“Designed for iPad”)", "—"],
        ]),
        ("note", "On Android, a destination inside the phone’s own storage is hidden from the gallery (a <code>.nomedia</code> file) so the backup is not backed up again."),
        ("fig", "android_backup", "Android: the Backup tab."),
        ("fig", "android_settings", "Android: Settings."),
    ]),
    ("faq", "Frequently asked questions", [
        ("p", "<b>Will it copy the same file twice if I run it again?</b> No. Each file is given a name at the destination and the next backup looks for it under that name. If the app’s records show it came from the same original, it is skipped — even if you edited it since. Only genuinely different files that share a name get a <code>-1</code>, <code>-2</code>… suffix, and nothing is ever overwritten."),
        ("p", "<b>Where does the app remember what it has backed up?</b> In its own database, and in a small <b>hidden file, <code>.pvb-index.json</code>, at the root of each destination</b>. That copy travels with the backup: after a reinstall, or from another phone, the app reads it and does not copy again. You can leave it alone; if you delete it the app rebuilds it."),
        ("p", "<b>Can I back up to a NAS and a drive together?</b> Yes — every connected destination receives the backup at the same time."),
        ("p", "<b>My NAS connection times out.</b> The NAS is usually not reachable: check that you are on the same Wi-Fi (or that the VPN is on), that SMB sharing is enabled, and that the NAS firewall allows the connection."),
        ("p", "<b>Can I use two phones with the same drive?</b> Yes. Give each a different folder name in Settings; each creates its own folder on the drive."),
        ("p", "<b>The bar says 3% and seems stuck.</b> The first files are often large videos. Wait a few minutes."),
        ("p", "<b>My card appears as “Documents”.</b> Some cameras use a generic folder. Type a meaningful name when you add the source."),
        ("p", "<b>Can I back up when my phone is almost full?</b> Yes. Files are streamed to the destination, so only a few megabytes are held at a time. Only a backup to a NAS <i>alone</i> needs room for one file at a time. A file that really cannot fit is reported as failed and the rest continues."),
        ("p", "<b>Is my data sent anywhere?</b> No. Everything happens between your phone and your drive or NAS. The app has no server and no account. The only network traffic is to the NAS you set up yourself, and the download of your own iCloud / Google photos by the system."),
        ("p", "<b>Which languages?</b> English, French, German, Spanish, Italian, Portuguese, Simplified Chinese and Russian. The app follows the phone language; you can force one in <b>Settings → Language</b>, with no restart."),
    ]),
]

PRIVACY = {
    "title": "Privacy policy — PhotoVideoBackup",
    "updated": "Last updated: {date}",
    "summary": "PhotoVideoBackup does not collect, store, transmit or share any personal data. It has no account, no analytics, no advertising and no server of its own.",
    "sections": [
        ("What the app accesses", [
            ("ul", ["Your photos and videos — <b>read-only</b>, to copy them to the drive, folder or NAS that you choose. On Android this includes the location stored in your photos, so that the copy is identical to the original.", "The folders and cards that you pick with the system file browser.", "Notifications, to tell you when a backup ends."]),
        ]),
        ("What leaves your device", [
            ("ul", ["<b>Nothing goes to us.</b> Your files are written only to the destinations you choose.", "If you configure a NAS, the app connects to <b>that server</b>, at the address you typed, and nowhere else. The password is kept in the iOS Keychain or the Android Keystore.", "iOS or Android may download your own iCloud or Google photos so the app can read them; this is done by the system, for your account.", "Purchases are handled by Apple or Google. We receive no payment information."]),
        ]),
        ("Diagnostic log", [
            ("p", "The app keeps a small diagnostic log on your device, with no personal content. It is sent only if you choose to e-mail it to support from the app."),
        ]),
        ("Contact with support", [
            ("p", "If you write to support, we receive what you send — your address and your message — and use it only to answer you."),
        ]),
    ],
}
