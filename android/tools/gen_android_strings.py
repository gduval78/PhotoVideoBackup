#!/usr/bin/env python3
"""Generates app/src/main/res/values*/strings.xml for the 8 languages of the app.

Source of truth for the shared strings is the iOS catalog (PhotoVideoBackup/Resources/Localizable.xcstrings, English
literal = key): an Android string name is mapped to the iOS key it reuses (REUSED), so a wording fixed on iOS is fixed
on Android on the next run. Strings that only exist on Android are written here once, in all 8 languages (EXTRA).

Run from the repo root:  python3 android/tools/gen_android_strings.py
Checks that every R.string.* referenced by the Kotlin code is defined, and that every language has every string.
"""
import json, re, sys
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[2]
XCSTRINGS = ROOT / "PhotoVideoBackup/Resources/Localizable.xcstrings"
RES = ROOT / "android/app/src/main/res"
KOTLIN = ROOT / "android/app/src/main/kotlin"

# iOS xcstrings language -> Android resource folder
LANGS = {"en": "values", "fr": "values-fr", "de": "values-de", "es": "values-es",
         "it": "values-it", "pt": "values-pt", "zh-Hans": "values-zh-rCN", "ru": "values-ru"}

# Android name -> iOS key (English literal)
REUSED = {
    "about": "About", "active": "Active", "add": "Add", "add_source": "Add Source (SD Card, USB Drive…)",
    "additional_file_types": "Additional file types", "all_files": "All files", "all_photos_videos": "all photos & videos",
    "already_present": "Already present", "analyzing_source": "Analyzing source…", "back": "Back", "backup": "Backup",
    "backup_complete": "Backup Complete", "backup_error": "Backup Error", "backup_failed": "Backup Failed",
    "backup_in_progress": "Backup in Progress", "backup_report": "Backup Report", "cancel": "Cancel",
    "choose_ellipsis": "Choose…", "clear": "Clear", "clear_history": "Clear History",
    "clear_history_message": "Session records are removed. Files on your SSD are not affected.",
    "clear_history_title": "Clear all backup history?", "close": "Close", "completed": "Completed", "connected": "Connected",
    "connecting": "Connecting to NAS…", "contact_support": "Contact Support", "copied": "Copied",
    "copied_count_fmt": "%lld copied", "copying_ellipsis": "Copying…", "date": "Date", "destination": "Destination",
    "destinations": "Destinations", "device": "Device", "diagnostic_log": "Diagnostic Log", "disconnected": "Disconnected",
    "documentation": "Documentation", "duration": "Duration",
    "err_device_name": "Please set a device name in Settings before starting a backup.",
    "err_external_pro": "External source backup requires the Pro upgrade.",
    "err_no_destination": "No backup destination is configured or connected.",
    "err_no_files_source": "No media files found in %@.",
    "err_source_not_connected": "\"%@\" is not connected. Reconnect the SD card and try again.",
    "eta_less_than_minute": "< 1 min remaining", "eta_minutes_fmt": "~%lld min remaining", "example": "Example",
    "extensions_explainer": "Files with these extensions will be included in every backup, for all device types. Enter without the dot.",
    "extensions_placeholder": "e.g. srt, gpx, csv", "failed": "Failed", "failed_count_fmt": "%lld failed",
    "feature_nas": "Back up over Wi-Fi to a NAS — even remotely",
    "feature_second_destination": "Redundant backup to a second SSD simultaneously",
    "feature_sources": "SD cards, USB drives, Insta360, DJI, and more", "file_naming": "File naming",
    "files_found_fmt": "%lld files found", "folder": "Folder", "folder_structure": "Folder structure",
    "folders_by_date": "By Date", "folders_by_month": "By Month", "folders_by_year_month": "By Year / Month",
    "folders_flat": "Flat (no subfolders)", "free": "Free", "free_fmt": "%@ free", "get_started": "Get Started",
    "history": "History", "history_empty_hint": "Completed backup sessions will appear here.", "host_ip": "Host / IP",
    "language": "Language", "max_files_per_session": "Max files per session", "name": "Name",
    "name_not_configured": "Name not configured",
    "name_source_message": "Give this source a name so you can recognise it easily.", "name_this_source": "Name this source",
    "naming_collision_note": "A file is never overwritten: if the name is already used by a different file, the new one is saved with a -1, -2… suffix. Include the seconds or {original} so that two shots taken together keep distinct names.",
    "naming_explainer": "Each file gets its final name as it is first copied, so it is never stored under its camera name and renamed afterwards. Duplicates are then recognised by that name. Turn off to keep the original file names.",
    "naming_tokens_hint": "Tap a token to insert it. Anything else is literal text. {device} is the device folder name without spaces; {original} is the original name without its extension.",
    "nas_connected_fmt": "Connected — %lld item(s) found.",
    "nas_data_warning": "You appear to be on mobile data. Backing up to the NAS may use your data plan — tap Stop to halt it.",
    "nas_fill_fields": "Please fill in host, share and username.", "nas_folder_placeholder": "optional, e.g. Backups",
    "nas_invalid_port": "Invalid host or port.", "nas_name_placeholder": "e.g. Synology NAS",
    "nas_share_placeholder": "e.g. photo", "nas_smb": "NAS (SMB)",
    "nas_unreachable": "The NAS is unreachable — check Wi-Fi/VPN and settings.",
    "no_backup_history": "No Backup History", "no_destination_hint": "No destination configured — go to Settings.",
    "none": "None", "not_configured": "Not configured", "not_connected": "Not connected",
    "notif_complete": "Backup complete", "notif_failed": "Backup failed", "notif_partial": "Backup partial",
    "notif_summary_disconnected": "%lld copied — destination disconnected. Reconnect and run again · %@",
    "notif_summary_failed": "%lld copied · %lld failed — %@",
    "notif_summary_limit": "%lld copied — file limit reached · %@",
    "notif_summary_skipped": "%lld copied · %lld skipped — %@",
    "notif_summary_stopped": "%lld copied — stopped. Run again to continue · %@",
    "off": "Off", "ok": "OK", "one_time_purchase": "One-time purchase — no subscription",
    "onboarding_naming": "Files are named automatically as they are backed up",
    "onboarding_sources": "SD cards, DJI, Insta360, GoPro and more",
    "onboarding_tagline": "Back up your media to an external SSD\nin just a few taps.",
    "partial": "Partial", "partial_backup": "Partial Backup",
    "partial_disconnected": "Partial backup — destination disconnected. Reconnect and run again to continue.",
    "partial_limit": "Partial backup — file limit reached. Run again to continue.",
    "partial_stopped": "Partial backup — stopped. Run again to continue.", "password": "Password", "pattern": "Pattern",
    "port": "Port", "preparing_ellipsis": "Preparing…", "pro": "Pro", "pro_feature": "Pro feature",
    "pro_title": "PhotoVideoBackup Pro", "product_load_failed": "Could not load product info.",
    "progress_files_fmt": "%lld / %lld files", "reconnect": "Reconnect", "remove": "Remove", "remove_nas": "Remove NAS",
    "rename_during_backup": "Rename files during backup", "restore_purchases": "Restore Purchases", "retry": "Retry",
    "running": "Running", "save": "Save", "set_device_name_hint": "Set a device name in Settings.",
    "settings": "Settings", "share": "Share", "share_report": "Share Report", "show_welcome": "Show welcome screen", "skipped": "Skipped",
    "skipped_count_fmt": "%lld skipped", "source": "Source", "source_name_placeholder": "e.g. Blackmagic, GoPro…",
    "source_subtitle_fmt": "%@ · %@", "sources": "Sources", "starting_copy": "Starting copy…", "stop": "Stop",
    "stopping": "Stopping…", "support": "Support", "system_default": "System Default", "test_connection": "Test connection",
    "total_fmt": "%@ total", "unlimited": "Unlimited", "upgrade_for_fmt": "Upgrade for %@",
    "upgrade_to_pro": "Upgrade to Pro", "use_this_nas": "Use this NAS for backups", "username": "Username",
    "verified_of_fmt": "%lld / %lld verified", "verified_sha_fmt": "%lld verified by SHA-256", "verifying": "Verifying…",
    "version": "Version", "version_fmt": "Version %@ (%@)",
    # Browse tab
    "tab_browse": "Browse", "browse_title": "Browse Backup", "no_ssd_connected": "No SSD Connected",
    "connect_ssd_hint": "Connect your SSD and configure a destination in Settings.",
    "no_backups_yet": "No backups yet on this SSD.", "empty_folder": "Empty folder",
    "one_file_in_folder": "1 file in this folder", "files_in_folder_fmt": "%lld files in this folder",
    "no_media_files": "No media files", "select": "Select", "select_all": "Select All", "deselect_all": "Deselect All",
    "share_n_fmt": "Share (%lld)", "preparing_n_fmt": "Preparing %lld file(s)…", "nas": "NAS",
    "could_not_connect_nas": "Could not connect to the NAS.",
    # Delete source files
    "delete_source_files_ellipsis": "Delete Source Files…", "delete_source_files": "Delete Source Files",
    "delete_one_file_msg": "1 file will be permanently deleted from **%@**.",
    "delete_n_files_msg": "%lld files will be permanently deleted from **%@**.",
    "delete_irreversible": "This action cannot be undone. Make sure your backup is complete before proceeding.",
    "enter_code": "Enter this code to confirm deletion:", "code": "Code", "delete_one_file": "Delete 1 file",
    "delete_n_files_fmt": "Delete %lld files", "deletion_complete": "Deletion Complete",
    "already_deleted": "These files have already been deleted.", "one_deleted_ok": "%lld file deleted successfully.",
    "n_deleted_ok": "%lld files deleted successfully.", "deleted_failed_fmt": "%lld deleted, %lld failed.",
    "delete_footer_fmt": "Permanently deletes the %lld files that were copied during this session from the original source. Your backup is not affected.",
    "deleting": "Deleting…",
    # LUT Grade
    "lut_grade": "LUT Grade", "assign_lut": "Assign LUT…", "grade": "Grade", "grading_n_fmt": "Grading %lld / %lld",
    "grading_complete": "Grading complete", "grading_ellipsis": "Grading…", "import_lut_cube": "Import LUT (.cube)…",
    "import_failed": "Import Failed", "no_luts_yet": "No LUTs imported yet.", "select_lut": "Select LUT",
    "available_luts": "Available LUTs", "select_videos_hint": "Select videos in the grid, then tap Grade.",
    "select_log_hint": "Select only your LOG videos to grade.", "lut_on": "LUT ON",
    "nas_grading_note": "Downloading, grading, and uploading to a “(Graded)” copy on the NAS.", "delete": "Delete",
}

# Android-only strings: name -> {lang: text}. Format args use %s / %d (positional when several).
EXTRA = {
    "app_name": {l: "PhotoVideoBackup" for l in LANGS},
    "gallery": {"en": "Gallery", "fr": "Galerie", "de": "Galerie", "es": "Galería", "it": "Galleria", "pt": "Galeria", "zh-Hans": "相册", "ru": "Галерея"},
    "device_name_placeholder": {"en": "e.g. Gerard's Pixel", "fr": "p. ex. Pixel de Gérard", "de": "z. B. Gerards Pixel", "es": "p. ej. Pixel de Gerard", "it": "es. Pixel di Gerard", "pt": "ex.: Pixel do Gerard", "zh-Hans": "例如:Gerard 的 Pixel", "ru": "напр. Pixel Жерара"},
    "device_name_footer": {"en": "This name is the top-level folder of your backups for the phone's gallery.", "fr": "Ce nom est le dossier de premier niveau de vos sauvegardes de la galerie du téléphone.", "de": "Dieser Name ist der oberste Ordner Ihrer Sicherungen der Telefongalerie.", "es": "Este nombre es la carpeta de primer nivel de las copias de la galería del teléfono.", "it": "Questo nome è la cartella principale dei backup della galleria del telefono.", "pt": "Este nome é a pasta de nível superior das cópias da galeria do telemóvel.", "zh-Hans": "此名称是手机相册备份的顶层文件夹。", "ru": "Это имя — папка верхнего уровня для резервных копий галереи телефона."},
    "destination_1": {"en": "Destination 1 (primary)", "fr": "Destination 1 (principale)", "de": "Ziel 1 (primär)", "es": "Destino 1 (principal)", "it": "Destinazione 1 (principale)", "pt": "Destino 1 (principal)", "zh-Hans": "目标 1(主要)", "ru": "Назначение 1 (основное)"},
    "destination_2": {"en": "Destination 2 (secondary)", "fr": "Destination 2 (secondaire)", "de": "Ziel 2 (sekundär)", "es": "Destino 2 (secundario)", "it": "Destinazione 2 (secondaria)", "pt": "Destino 2 (secundário)", "zh-Hans": "目标 2(次要)", "ru": "Назначение 2 (дополнительное)"},
    "feature_gallery": {"en": "Back up your phone's photos and videos to a folder", "fr": "Sauvegardez les photos et vidéos du téléphone dans un dossier", "de": "Fotos und Videos des Telefons in einem Ordner sichern", "es": "Copia las fotos y vídeos del teléfono en una carpeta", "it": "Esegui il backup di foto e video del telefono in una cartella", "pt": "Copie as fotos e vídeos do telemóvel para uma pasta", "zh-Hans": "将手机的照片和视频备份到文件夹", "ru": "Резервное копирование фото и видео телефона в папку"},
    "onboarding_gallery": {"en": "Back up your phone's photos and videos to an SSD or SD card", "fr": "Sauvegardez les photos et vidéos du téléphone sur un SSD ou une carte SD", "de": "Fotos und Videos des Telefons auf SSD oder SD-Karte sichern", "es": "Copia las fotos y vídeos del teléfono en un SSD o una tarjeta SD", "it": "Esegui il backup di foto e video del telefono su SSD o scheda SD", "pt": "Copie as fotos e vídeos do telemóvel para um SSD ou cartão SD", "zh-Hans": "将手机的照片和视频备份到 SSD 或 SD 卡", "ru": "Резервное копирование фото и видео телефона на SSD или SD-карту"},
    "err_gallery_permission": {"en": "Allow access to your photos and videos in Android settings to back up the gallery.", "fr": "Autorisez l'accès aux photos et vidéos dans les réglages Android pour sauvegarder la galerie.", "de": "Erlauben Sie den Zugriff auf Fotos und Videos in den Android-Einstellungen, um die Galerie zu sichern.", "es": "Permite el acceso a fotos y vídeos en los ajustes de Android para copiar la galería.", "it": "Consenti l'accesso a foto e video nelle impostazioni di Android per eseguire il backup della galleria.", "pt": "Permita o acesso a fotos e vídeos nas definições do Android para copiar a galeria.", "zh-Hans": "请在 Android 设置中允许访问照片和视频,以备份相册。", "ru": "Разрешите доступ к фото и видео в настройках Android, чтобы создать копию галереи."},
    "err_no_files_gallery": {"en": "No photos or videos found on this phone.", "fr": "Aucune photo ou vidéo trouvée sur ce téléphone.", "de": "Keine Fotos oder Videos auf diesem Telefon gefunden.", "es": "No se encontraron fotos ni vídeos en este teléfono.", "it": "Nessuna foto o video trovato su questo telefono.", "pt": "Não foram encontradas fotos nem vídeos neste telemóvel.", "zh-Hans": "此手机上未找到照片或视频。", "ru": "На этом телефоне не найдено фото или видео."},
    "err_scan_failed": {"en": "Could not read the source: %1$s", "fr": "Impossible de lire la source : %1$s", "de": "Die Quelle konnte nicht gelesen werden: %1$s", "es": "No se pudo leer el origen: %1$s", "it": "Impossibile leggere la sorgente: %1$s", "pt": "Não foi possível ler a origem: %1$s", "zh-Hans": "无法读取来源:%1$s", "ru": "Не удалось прочитать источник: %1$s"},
    "err_source_unavailable": {"en": "This source is no longer available.", "fr": "Cette source n'est plus disponible.", "de": "Diese Quelle ist nicht mehr verfügbar.", "es": "Este origen ya no está disponible.", "it": "Questa sorgente non è più disponibile.", "pt": "Esta origem já não está disponível.", "zh-Hans": "此来源已不可用。", "ru": "Этот источник больше недоступен."},
    "err_unexpected": {"en": "Unexpected error: %1$s", "fr": "Erreur inattendue : %1$s", "de": "Unerwarteter Fehler: %1$s", "es": "Error inesperado: %1$s", "it": "Errore imprevisto: %1$s", "pt": "Erro inesperado: %1$s", "zh-Hans": "意外错误:%1$s", "ru": "Непредвиденная ошибка: %1$s"},
    "notif_backing_up": {"en": "Backing up your media…", "fr": "Sauvegarde de vos médias…", "de": "Medien werden gesichert …", "es": "Copiando tus archivos…", "it": "Backup dei tuoi file in corso…", "pt": "A copiar os seus ficheiros…", "zh-Hans": "正在备份您的媒体…", "ru": "Резервное копирование медиа…"},
    "notif_channel_progress": {"en": "Backup in progress", "fr": "Sauvegarde en cours", "de": "Sicherung läuft", "es": "Copia en curso", "it": "Backup in corso", "pt": "Cópia em curso", "zh-Hans": "备份进行中", "ru": "Выполняется резервное копирование"},
    "notif_channel_done": {"en": "Backup results", "fr": "Résultats des sauvegardes", "de": "Sicherungsergebnisse", "es": "Resultados de la copia", "it": "Risultati del backup", "pt": "Resultados da cópia", "zh-Hans": "备份结果", "ru": "Результаты копирования"},
    "pro_active": {"en": "PhotoVideoBackup Pro is active", "fr": "PhotoVideoBackup Pro est activé", "de": "PhotoVideoBackup Pro ist aktiv", "es": "PhotoVideoBackup Pro está activo", "it": "PhotoVideoBackup Pro è attivo", "pt": "O PhotoVideoBackup Pro está ativo", "zh-Hans": "PhotoVideoBackup Pro 已启用", "ru": "PhotoVideoBackup Pro активен"},
    "pro_active_detail": {"en": "Thank you for your support!", "fr": "Merci pour votre soutien !", "de": "Danke für Ihre Unterstützung!", "es": "¡Gracias por tu apoyo!", "it": "Grazie per il tuo supporto!", "pt": "Obrigado pelo seu apoio!", "zh-Hans": "感谢您的支持!", "ru": "Спасибо за поддержку!"},
    "send": {"en": "Send", "fr": "Envoyer", "de": "Senden", "es": "Enviar", "it": "Invia", "pt": "Enviar", "zh-Hans": "发送", "ru": "Отправить"},
    "nas_explainer": {"en": "The NAS is used as an additional backup destination over Wi-Fi. Files are written directly to the share and verified by SHA-256. The password is stored encrypted in the Android Keystore.", "fr": "Le NAS sert de destination de sauvegarde supplémentaire via le Wi-Fi. Les fichiers sont écrits directement sur le partage et vérifiés par SHA-256. Le mot de passe est stocké chiffré dans le Keystore Android.", "de": "Das NAS dient als zusätzliches Sicherungsziel über WLAN. Dateien werden direkt auf die Freigabe geschrieben und per SHA-256 geprüft. Das Passwort wird verschlüsselt im Android Keystore gespeichert.", "es": "El NAS se usa como destino de copia adicional por Wi-Fi. Los archivos se escriben directamente en el recurso compartido y se verifican con SHA-256. La contraseña se guarda cifrada en el Keystore de Android.", "it": "Il NAS è usato come destinazione di backup aggiuntiva via Wi-Fi. I file vengono scritti direttamente sulla condivisione e verificati con SHA-256. La password è memorizzata cifrata nel Keystore di Android.", "pt": "O NAS é usado como destino de cópia adicional por Wi-Fi. Os ficheiros são escritos diretamente na partilha e verificados com SHA-256. A palavra-passe é guardada cifrada no Keystore do Android.", "zh-Hans": "NAS 通过 Wi-Fi 用作额外的备份目标。文件直接写入共享并通过 SHA-256 校验。密码加密存储在 Android Keystore 中。", "ru": "NAS используется как дополнительное место резервного копирования по Wi-Fi. Файлы записываются прямо в общую папку и проверяются по SHA-256. Пароль хранится в зашифрованном виде в Android Keystore."},
    "browse_preview_unavailable": {"en": "This file can't be previewed here.", "fr": "Ce fichier ne peut pas être prévisualisé ici.", "de": "Diese Datei kann hier nicht angezeigt werden.", "es": "Este archivo no se puede previsualizar aquí.", "it": "Questo file non può essere visualizzato qui.", "pt": "Este ficheiro não pode ser pré-visualizado aqui.", "zh-Hans": "无法在此预览该文件。", "ru": "Этот файл нельзя просмотреть здесь."},
    "browse_open_with": {"en": "Open with…", "fr": "Ouvrir avec…", "de": "Öffnen mit …", "es": "Abrir con…", "it": "Apri con…", "pt": "Abrir com…", "zh-Hans": "用其他应用打开…", "ru": "Открыть в…"},
    "browse_downloading": {"en": "Downloading…", "fr": "Téléchargement…", "de": "Wird geladen …", "es": "Descargando…", "it": "Download in corso…", "pt": "A transferir…", "zh-Hans": "正在下载…", "ru": "Загрузка…"},
    "browse_share_failed": {"en": "Could not prepare the files to share.", "fr": "Impossible de préparer les fichiers à partager.", "de": "Die Dateien konnten nicht zum Teilen vorbereitet werden.", "es": "No se pudieron preparar los archivos para compartir.", "it": "Impossibile preparare i file da condividere.", "pt": "Não foi possível preparar os ficheiros para partilhar.", "zh-Hans": "无法准备要分享的文件。", "ru": "Не удалось подготовить файлы для отправки."},
    "delete_grant_hint": {"en": "To delete files on this source, Android needs write access. Choose the same folder again and allow it.", "fr": "Pour supprimer les fichiers de cette source, Android demande un accès en écriture. Choisissez à nouveau le même dossier et autorisez-le.", "de": "Zum Löschen von Dateien dieser Quelle braucht Android Schreibzugriff. Wählen Sie denselben Ordner erneut und erlauben Sie den Zugriff.", "es": "Para eliminar los archivos de este origen, Android necesita acceso de escritura. Elige de nuevo la misma carpeta y permítelo.", "it": "Per eliminare i file di questa sorgente, Android richiede l'accesso in scrittura. Scegli di nuovo la stessa cartella e consenti l'accesso.", "pt": "Para eliminar os ficheiros desta origem, o Android precisa de acesso de escrita. Escolha novamente a mesma pasta e permita o acesso.", "zh-Hans": "要删除此来源的文件,Android 需要写入权限。请再次选择同一文件夹并允许访问。", "ru": "Чтобы удалить файлы этого источника, Android требуется доступ на запись. Выберите ту же папку ещё раз и разрешите доступ."},
    "delete_old_android": {"en": "Deleting photos from the gallery needs Android 11 or later.", "fr": "La suppression de photos de la galerie nécessite Android 11 ou plus récent.", "de": "Zum Löschen von Fotos aus der Galerie ist Android 11 oder neuer nötig.", "es": "Eliminar fotos de la galería requiere Android 11 o posterior.", "it": "Per eliminare le foto dalla galleria serve Android 11 o successivo.", "pt": "Eliminar fotos da galeria requer Android 11 ou posterior.", "zh-Hans": "从相册删除照片需要 Android 11 或更高版本。", "ru": "Для удаления фото из галереи требуется Android 11 или новее."},
    "lut_invalid": {"en": "This file is not a valid .cube LUT.", "fr": "Ce fichier n'est pas une LUT .cube valide.", "de": "Diese Datei ist keine gültige .cube-LUT.", "es": "Este archivo no es una LUT .cube válida.", "it": "Questo file non è una LUT .cube valida.", "pt": "Este ficheiro não é uma LUT .cube válida.", "zh-Hans": "此文件不是有效的 .cube LUT。", "ru": "Этот файл не является корректной LUT .cube."},
    "grade_failed_fmt": {"en": "%1$d video(s) could not be graded.", "fr": "%1$d vidéo(s) n'ont pas pu être étalonnée(s).", "de": "%1$d Video(s) konnten nicht bearbeitet werden.", "es": "No se pudieron procesar %1$d vídeo(s).", "it": "Impossibile elaborare %1$d video.", "pt": "Não foi possível processar %1$d vídeo(s).", "zh-Hans": "有 %1$d 个视频无法调色。", "ru": "Не удалось обработать видео: %1$d."},
    "browse_not_connected": {"en": "This destination is not connected.", "fr": "Cette destination n'est pas connectée.", "de": "Dieses Ziel ist nicht verbunden.", "es": "Este destino no está conectado.", "it": "Questa destinazione non è connessa.", "pt": "Este destino não está ligado.", "zh-Hans": "此目标未连接。", "ru": "Это место назначения не подключено."},
}

PLACEHOLDER = re.compile(r"%(\d+\$)?(@|lld|ld|d)")

def to_android(text: str) -> str:
    """iOS format specifiers -> Android (positional), then XML/Android escaping."""
    n = 0
    def sub(m):
        nonlocal n
        n += 1
        idx = (m.group(1) or f"{n}$")
        return f"%{idx}{'s' if m.group(2) == '@' else 'd'}"
    out = PLACEHOLDER.sub(sub, text)
    out = escape(out.replace("**", ""))   # iOS uses Markdown bold in a few strings; plain text here
    out = out.replace("\\", "\\\\").replace("'", "\\'").replace('"', '\\"').replace("\n", "\\n")
    if out.startswith(("@", "?")):
        out = "\\" + out
    return out

def main():
    cat = json.loads(XCSTRINGS.read_text())["strings"]
    values = {lang: {} for lang in LANGS}
    problems = []

    for name, key in REUSED.items():
        entry = cat.get(key)
        if entry is None:
            problems.append(f"iOS key missing for {name}: {key!r}"); continue
        for lang in LANGS:
            if lang == "en":
                text = key
            else:
                loc = entry.get("localizations", {}).get(lang)
                unit = (loc or {}).get("stringUnit")
                if unit is None and loc and "variations" in loc:
                    plural = loc["variations"].get("plural", {})
                    unit = (plural.get("other") or next(iter(plural.values()), {})).get("stringUnit")
                if unit is None:
                    problems.append(f"{name} [{lang}] has no translation in the iOS catalog"); continue
                text = unit["value"]
            values[lang][name] = to_android(text)

    for name, tr in EXTRA.items():
        for lang in LANGS:
            if lang not in tr:
                problems.append(f"EXTRA {name} missing {lang}"); continue
            values[lang][name] = to_android(tr[lang]) if name != "app_name" else tr[lang]

    # Every R.string.* used by the code must exist; every string should be used.
    used = set()
    for f in KOTLIN.rglob("*.kt"):
        used |= set(re.findall(r"R\.string\.([a-z0-9_]+)", f.read_text()))
    defined = set(values["en"])
    for n in sorted(used - defined): problems.append(f"used but undefined: {n}")
    unused = sorted(defined - used)

    for lang, folder in LANGS.items():
        d = RES / folder
        d.mkdir(parents=True, exist_ok=True)
        lines = ['<?xml version="1.0" encoding="utf-8"?>', "<resources>"]
        for name in sorted(values[lang]):
            attr = ' translatable="false"' if name == "app_name" else ""
            lines.append(f'    <string name="{name}"{attr}>{values[lang][name]}</string>')
        lines.append("</resources>")
        (d / "strings.xml").write_text("\n".join(lines) + "\n")

    print(f"{len(defined)} strings x {len(LANGS)} languages; {len(used)} used")
    if unused: print("unused (harmless):", ", ".join(unused))
    if problems:
        print("PROBLEMS:"); [print(" -", p) for p in problems]; sys.exit(1)

main()
