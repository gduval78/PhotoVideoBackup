# App Store listing — zh-Hant (Traditional Chinese, Taiwan) — iOS 2.7.0 (build 54)

App Store Connect locale: **Chinese, Traditional** (`zh-Hant`). Machine-derived from the Simplified Chinese texts and the Play listing, with Taiwan vocabulary (`Documentation/site/hant_convert.py`): **have a Taiwanese speaker proof-read it before submitting.** The App Store descriptions of the other locales are not in this repository, so compare this one with them for consistency (features, Pro wording, claims). Character limits are Apple's; counts are checked.

## Name (16/30)
PhotoVideoBackup

## Subtitle (18/30)
備份照片與影片到 SSD 或 NAS

## Promotional text (80/170)
一鍵將 iPhone 的照片和影片備份到外接硬碟、NAS 或 iCloud Drive，並以 SHA-256 逐檔驗證。不重複、不覆蓋，也不會經過我們的伺服器。

## Keywords (66/100)
備份,照片,影片,SSD,NAS,SD卡,外接硬碟,空拍機,DJI,GoPro,Insta360,SMB,iCloud,LUT,相簿

## Description (961/4000)
PhotoVideoBackup 可將 iPhone 或 iPad 上的照片和影片，或相機記憶卡和 USB 隨身碟中的檔案，複製到外接 SSD、NAS 或 iCloud Drive。每個檔案都會逐位元組驗證，絕不會在不知情的情況下留下損壞的備份。

• 備份方案：自行選擇要備份的內容和位置，一鍵執行。每個備份都有自己的來源、目的地（多個資料夾和一台 NAS）和選項。
• 將照片圖庫備份到外接硬碟、NAS 或 iCloud Drive。備份到外接硬碟或 iCloud Drive 時，檔案以串流方式寫入，不需要先暫存在 iPhone 上，儲存空間快滿時也能備份。
• 相機記憶卡與空拍機（Pro）：自動識別 DJI、DJI 360 / Action、GoPro、Insta360 及通用記憶卡和外接硬碟。
• 透過 Wi-Fi 備份到 NAS（Pro）：直接複製到群暉或任何 SMB 共用，區域網路內或透過 VPN 遠端均可。
• 同時備份到第二個目的地（Pro）：鏡像到兩個硬碟，或一個硬碟加一台 NAS。其中一個中途斷開時，另一個會繼續。
• SHA-256 驗證：每份副本都會被重新讀取並與原件比對。
• 不產生重複檔案：已備份的檔案會被識別並略過，即使之後被修改過也一樣；不同的檔案絕不會被覆蓋。
• 自訂資料夾與命名：依日期、月份或年/月整理，並按 2025-06-14 15H30M12 iPhone 這樣的範本命名檔案。
• 瀏覽備份：資料夾、縮圖、全螢幕檢視器、影片播放、多選和分享。
• LUT 調色（Pro）：為 LOG 素材套用 .cube LUT，匯出調色後的 H.265 副本。App 內即時 LUT 預覽免費。
• 安全釋放空間：備份後可刪除已複製並驗證的來源檔案，並有確認碼保護。
• 報告與歷史記錄：依目的地顯示已複製、已略過和失敗的檔案。
• 也可在配備 Apple 晶片的 Mac 上執行（以 iPad App 方式）。
• 支援 13 種語言，包括繁體中文。

免費：將照片圖庫備份到一個目的地，瀏覽和預覽備份。Pro 為一次性購買，無需訂閱：多個備份、第二個目的地、NAS、相機和 USB 來源，以及 LUT 調色。

無需帳號，無廣告，無追蹤：您的檔案絕不會經過我們的伺服器。

## What's New (151/4000)
新功能：備份方案。自行選擇要備份的內容和位置，一鍵執行。每個備份都有自己的來源、目的地（多個資料夾和一台 NAS）和選項。現有設定將自動遷移。免費版：一個備份；Pro：多個備份、第二個目的地、NAS、SD/USB 來源、LUT 調色。現已支援 13 種語言：新增日語、韓語、印地語、阿拉伯語和繁體中文。

## To do in App Store Connect
- Add the localization **Chinese, Traditional**; paste the fields above.
- Screenshots: the localization needs its own set; the English set (iPhone 6.9", 5 scenes, commit `a8eab3d`) can be reused until localized ones exist.
- Support URL / marketing URL / privacy policy URL: the existing ones (the privacy policy opens in the visitor's language; `zh-Hant/privacy-policy.html` exists).
- The build must be 54 or later (it is the first with `zh-Hant` in the app).
