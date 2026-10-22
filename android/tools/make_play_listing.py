#!/usr/bin/env python3
"""Google Play listing (8 languages) -> android/store/play_listing.json.
Play limits: title 30, short description 80, full description 4000. Source of truth for the texts: this file."""
import json, pathlib

POLICY = "https://gduval78.github.io/PhotoVideoBackup/privacy-policy.html"
TITLE = "PhotoVideoBackup"

L = {}

L["en-US"] = dict(
short="Back up photos and videos to an SSD, SD card or NAS, verified by SHA-256.",
body="""PhotoVideoBackup copies your photos and videos from your phone, or from a camera memory card, to an external SSD, a USB drive or a NAS. Every file is verified byte for byte, so you never end up with a silent, corrupted backup.

• Back up your gallery to any folder: an SSD or USB drive plugged into your phone, or the phone's own storage.
• Camera cards and drones (Pro): DJI, DJI 360 / Action, GoPro, Insta360 and generic cards are recognised automatically.
• NAS over Wi-Fi (Pro): copy straight to a Synology or any SMB share, on your network or remotely through a VPN.
• Two destinations at once (Pro): mirror to two drives, or a drive and a NAS. If one disappears mid-backup, the other carries on.
• SHA-256 verification: each copy is read back and compared with the original.
• No duplicates: a file already backed up is recognised and skipped, even if you edited it since, and a different file is never overwritten.
• Your folders, your names: organise by date, month or year/month, and name files with a pattern such as 2025-06-14 15H30M12 Pixel.
• Browse your backup: folders, thumbnails, full-screen viewer with swipe and zoom, video playback, multi-select and share.
• LUT Grade (Pro): apply a .cube LUT to LOG footage and export a graded H.265 copy. Real-time LUT preview is free.
• Free up space safely: after a backup, delete the source files that were copied and verified, protected by a confirmation code.
• Reports and history: what was copied, skipped or failed, per destination.
• Runs in the background with a notification and a Stop button; resumes where it left off.
• Available in English, French, German, Spanish, Italian, Portuguese, Simplified Chinese and Russian.

Free: back up your gallery to one folder, browse and preview your backups. Pro is a one-time purchase, no subscription: camera and SD sources, a second destination, NAS and LUT grading.

No account, no ads, no tracking: your media never goes through our servers.

Privacy policy: %s""",
)

L["fr-FR"] = dict(
short="Sauvegardez photos et vidéos sur SSD, carte SD ou NAS, vérifiées par SHA-256.",
body="""PhotoVideoBackup copie vos photos et vidéos depuis votre téléphone, ou depuis une carte mémoire d'appareil photo, vers un SSD externe, une clé USB ou un NAS. Chaque fichier est vérifié octet par octet : jamais de sauvegarde corrompue sans le savoir.

• Sauvegardez votre galerie vers n'importe quel dossier : un SSD ou une clé USB branchés au téléphone, ou le stockage du téléphone.
• Cartes d'appareils et drones (Pro) : DJI, DJI 360 / Action, GoPro, Insta360 et cartes génériques sont reconnus automatiquement.
• NAS en Wi-Fi (Pro) : copie directe vers un Synology ou tout partage SMB, sur votre réseau ou à distance via un VPN.
• Deux destinations à la fois (Pro) : copie miroir sur deux disques, ou un disque et un NAS. Si l'un disparaît en cours de route, l'autre continue.
• Vérification SHA-256 : chaque copie est relue et comparée à l'original.
• Pas de doublons : un fichier déjà sauvegardé est reconnu et ignoré, même retouché depuis, et un fichier différent n'est jamais écrasé.
• Vos dossiers, vos noms : classement par date, mois ou année/mois, et noms de fichiers selon un modèle comme 2025-06-14 15H30M12 Pixel.
• Parcourez votre sauvegarde : dossiers, miniatures, visionneuse plein écran avec balayage et zoom, lecture vidéo, sélection multiple et partage.
• LUT Grade (Pro) : appliquez une LUT .cube à vos rushs LOG et exportez une copie H.265 étalonnée. L'aperçu LUT en temps réel est gratuit.
• Libérez de la place en toute sécurité : après une sauvegarde, supprimez les fichiers source copiés et vérifiés, protégé par un code de confirmation.
• Rapports et historique : ce qui a été copié, ignoré ou en échec, par destination.
• Fonctionne en arrière-plan avec notification et bouton Arrêter ; reprend là où il s'est arrêté.
• Disponible en français, anglais, allemand, espagnol, italien, portugais, chinois simplifié et russe.

Gratuit : sauvegarde de la galerie vers un dossier, navigation et aperçu des sauvegardes. Pro est un achat unique, sans abonnement : sources appareil photo et carte SD, seconde destination, NAS et étalonnage LUT.

Sans compte, sans publicité, sans suivi : vos médias ne passent jamais par nos serveurs.

Politique de confidentialité : %s""",
)

L["de-DE"] = dict(
short="Fotos und Videos auf SSD, SD-Karte oder NAS sichern – per SHA-256 geprüft.",
body="""PhotoVideoBackup kopiert Ihre Fotos und Videos vom Smartphone oder von einer Kamera-Speicherkarte auf eine externe SSD, einen USB-Stick oder ein NAS. Jede Datei wird Byte für Byte geprüft – so gibt es kein unbemerkt beschädigtes Backup.

• Sichern Sie Ihre Galerie in einen beliebigen Ordner: auf eine am Handy angeschlossene SSD oder einen USB-Stick oder in den Telefonspeicher.
• Kamerakarten und Drohnen (Pro): DJI, DJI 360 / Action, GoPro, Insta360 und allgemeine Karten werden automatisch erkannt.
• NAS per WLAN (Pro): direkt auf ein Synology oder eine beliebige SMB-Freigabe kopieren, im Heimnetz oder per VPN von unterwegs.
• Zwei Ziele gleichzeitig (Pro): Spiegelung auf zwei Laufwerke oder auf Laufwerk und NAS. Fällt eines mitten im Backup aus, läuft das andere weiter.
• SHA-256-Prüfung: Jede Kopie wird zurückgelesen und mit dem Original verglichen.
• Keine Duplikate: Bereits gesicherte Dateien werden erkannt und übersprungen – auch wenn Sie sie seitdem bearbeitet haben. Eine andere Datei wird nie überschrieben.
• Ihre Ordner, Ihre Namen: Ordnung nach Datum, Monat oder Jahr/Monat und Dateinamen nach einem Muster wie 2025-06-14 15H30M12 Pixel.
• Backup durchsuchen: Ordner, Vorschaubilder, Vollbildansicht mit Wischen und Zoom, Videowiedergabe, Mehrfachauswahl und Teilen.
• LUT Grade (Pro): Wenden Sie eine .cube-LUT auf LOG-Material an und exportieren Sie eine gegradete H.265-Kopie. Die LUT-Echtzeitvorschau ist kostenlos.
• Speicher sicher freigeben: Löschen Sie nach dem Backup die kopierten und geprüften Quelldateien, geschützt durch einen Bestätigungscode.
• Berichte und Verlauf: was kopiert, übersprungen oder fehlgeschlagen ist, pro Ziel.
• Läuft im Hintergrund mit Benachrichtigung und Stopp-Taste und macht dort weiter, wo es aufgehört hat.
• Verfügbar auf Deutsch, Englisch, Französisch, Spanisch, Italienisch, Portugiesisch, Chinesisch (vereinfacht) und Russisch.

Kostenlos: Galerie in einen Ordner sichern, Backups durchsuchen und ansehen. Pro ist ein Einmalkauf ohne Abo: Kamera- und SD-Quellen, ein zweites Ziel, NAS und LUT-Grading.

Kein Konto, keine Werbung, kein Tracking: Ihre Medien laufen nie über unsere Server.

Datenschutzerklärung: %s""",
)

L["es-ES"] = dict(
short="Copia fotos y vídeos en SSD, tarjeta SD o NAS, verificadas con SHA-256.",
body="""PhotoVideoBackup copia tus fotos y vídeos desde el móvil, o desde una tarjeta de memoria de cámara, a un SSD externo, una unidad USB o un NAS. Cada archivo se verifica byte a byte, así que nunca tendrás una copia dañada sin saberlo.

• Copia tu galería a cualquier carpeta: un SSD o una unidad USB conectados al móvil, o el almacenamiento del propio teléfono.
• Tarjetas de cámara y drones (Pro): DJI, DJI 360 / Action, GoPro, Insta360 y tarjetas genéricas se reconocen automáticamente.
• NAS por Wi-Fi (Pro): copia directa a un Synology o a cualquier recurso SMB, en tu red o a distancia mediante VPN.
• Dos destinos a la vez (Pro): réplica en dos discos, o en un disco y un NAS. Si uno desaparece a mitad de copia, el otro continúa.
• Verificación SHA-256: cada copia se vuelve a leer y se compara con el original.
• Sin duplicados: un archivo ya copiado se reconoce y se omite, aunque lo hayas retocado después, y un archivo distinto nunca se sobrescribe.
• Tus carpetas, tus nombres: organiza por fecha, mes o año/mes y nombra los archivos con un patrón como 2025-06-14 15H30M12 Pixel.
• Explora tu copia: carpetas, miniaturas, visor a pantalla completa con deslizamiento y zoom, reproducción de vídeo, selección múltiple y compartir.
• LUT Grade (Pro): aplica una LUT .cube a tu material LOG y exporta una copia H.265 gradada. La vista previa de la LUT en tiempo real es gratuita.
• Libera espacio con seguridad: tras una copia, borra los archivos de origen copiados y verificados, protegido con un código de confirmación.
• Informes e historial: qué se copió, omitió o falló, por destino.
• Funciona en segundo plano con notificación y botón Detener; continúa donde se quedó.
• Disponible en español, inglés, francés, alemán, italiano, portugués, chino simplificado y ruso.

Gratis: copia de la galería a una carpeta, exploración y vista previa de tus copias. Pro es una compra única, sin suscripción: fuentes de cámara y SD, un segundo destino, NAS y gradación LUT.

Sin cuenta, sin anuncios, sin rastreo: tus archivos nunca pasan por nuestros servidores.

Política de privacidad: %s""",
)

L["it-IT"] = dict(
short="Copia foto e video su SSD, scheda SD o NAS, verificati con SHA-256.",
body="""PhotoVideoBackup copia le tue foto e i tuoi video dal telefono, o da una scheda di memoria della fotocamera, su un SSD esterno, un'unità USB o un NAS. Ogni file viene verificato byte per byte, così non avrai mai un backup danneggiato senza saperlo.

• Copia la galleria in una cartella qualsiasi: un SSD o un'unità USB collegati al telefono, oppure la memoria del telefono.
• Schede di fotocamere e droni (Pro): DJI, DJI 360 / Action, GoPro, Insta360 e schede generiche sono riconosciuti automaticamente.
• NAS via Wi-Fi (Pro): copia diretta su un Synology o su qualsiasi condivisione SMB, sulla tua rete o da remoto tramite VPN.
• Due destinazioni insieme (Pro): mirror su due dischi, oppure su un disco e un NAS. Se uno scompare durante il backup, l'altro continua.
• Verifica SHA-256: ogni copia viene riletta e confrontata con l'originale.
• Niente duplicati: un file già salvato viene riconosciuto e saltato, anche se lo hai modificato dopo, e un file diverso non viene mai sovrascritto.
• Le tue cartelle, i tuoi nomi: organizza per data, mese o anno/mese e dai ai file un nome secondo un modello come 2025-06-14 15H30M12 Pixel.
• Sfoglia il backup: cartelle, miniature, visualizzatore a schermo intero con scorrimento e zoom, riproduzione video, selezione multipla e condivisione.
• LUT Grade (Pro): applica una LUT .cube ai filmati LOG ed esporta una copia H.265 con color grading. L'anteprima LUT in tempo reale è gratuita.
• Libera spazio in sicurezza: dopo un backup, elimina i file di origine copiati e verificati, protetto da un codice di conferma.
• Report e cronologia: cosa è stato copiato, saltato o fallito, per destinazione.
• Funziona in background con notifica e pulsante Interrompi; riprende da dove si era fermato.
• Disponibile in italiano, inglese, francese, tedesco, spagnolo, portoghese, cinese semplificato e russo.

Gratis: backup della galleria in una cartella, esplorazione e anteprima dei backup. Pro è un acquisto una tantum, senza abbonamento: sorgenti fotocamera e SD, una seconda destinazione, NAS e color grading LUT.

Nessun account, nessuna pubblicità, nessun tracciamento: i tuoi contenuti non passano mai dai nostri server.

Informativa sulla privacy: %s""",
)

L["pt-PT"] = dict(
short="Copie fotos e vídeos para SSD, cartão SD ou NAS, verificados por SHA-256.",
body="""O PhotoVideoBackup copia as suas fotos e vídeos do telemóvel, ou de um cartão de memória de câmara, para um SSD externo, uma unidade USB ou um NAS. Cada ficheiro é verificado byte a byte, por isso nunca terá uma cópia danificada sem o saber.

• Copie a sua galeria para qualquer pasta: um SSD ou unidade USB ligados ao telemóvel, ou o armazenamento do próprio telemóvel.
• Cartões de câmaras e drones (Pro): DJI, DJI 360 / Action, GoPro, Insta360 e cartões genéricos são reconhecidos automaticamente.
• NAS por Wi-Fi (Pro): cópia direta para um Synology ou qualquer partilha SMB, na sua rede ou à distância através de VPN.
• Dois destinos em simultâneo (Pro): espelho em dois discos, ou num disco e num NAS. Se um desaparecer a meio, o outro continua.
• Verificação SHA-256: cada cópia é lida de novo e comparada com o original.
• Sem duplicados: um ficheiro já copiado é reconhecido e ignorado, mesmo que o tenha editado entretanto, e um ficheiro diferente nunca é substituído.
• As suas pastas, os seus nomes: organize por data, mês ou ano/mês e dê nome aos ficheiros com um padrão como 2025-06-14 15H30M12 Pixel.
• Explore a sua cópia: pastas, miniaturas, visualizador em ecrã inteiro com deslize e zoom, reprodução de vídeo, seleção múltipla e partilha.
• LUT Grade (Pro): aplique uma LUT .cube a imagens LOG e exporte uma cópia H.265 com correção de cor. A pré-visualização da LUT em tempo real é gratuita.
• Liberte espaço em segurança: depois de uma cópia, elimine os ficheiros de origem copiados e verificados, protegido por um código de confirmação.
• Relatórios e histórico: o que foi copiado, ignorado ou falhou, por destino.
• Funciona em segundo plano com notificação e botão Parar; retoma onde ficou.
• Disponível em português, inglês, francês, alemão, espanhol, italiano, chinês simplificado e russo.

Grátis: cópia da galeria para uma pasta, exploração e pré-visualização das cópias. O Pro é uma compra única, sem subscrição: fontes de câmara e SD, um segundo destino, NAS e correção de cor LUT.

Sem conta, sem anúncios, sem rastreio: os seus ficheiros nunca passam pelos nossos servidores.

Política de privacidade: %s""",
)

L["zh-CN"] = dict(
short="将照片和视频备份到 SSD、SD 卡或 NAS，并以 SHA-256 校验。",
body="""PhotoVideoBackup 可将手机或相机存储卡中的照片和视频复制到外置 SSD、USB 存储设备或 NAS。每个文件都会逐字节校验，绝不会在不知情的情况下留下损坏的备份。

• 将相册备份到任意文件夹：连接到手机的 SSD 或 USB 存储设备，或手机自身存储。
• 相机存储卡与无人机（Pro）：自动识别 DJI、DJI 360 / Action、GoPro、Insta360 及通用存储卡。
• 通过 Wi-Fi 备份到 NAS（Pro）：直接复制到群晖或任何 SMB 共享，局域网内或通过 VPN 远程均可。
• 同时备份到两个目的地（Pro）：镜像到两块硬盘，或一块硬盘加一台 NAS。备份中途若其中一个断开，另一个会继续。
• SHA-256 校验：每份副本都会被重新读取并与原件比对。
• 不产生重复文件：已备份的文件会被识别并跳过，即使之后被修改过也一样；不同的文件绝不会被覆盖。
• 自定义文件夹与命名：按日期、月份或年/月整理，并按 2025-06-14 15H30M12 Pixel 这样的模板命名文件。
• 浏览备份：文件夹、缩略图、支持滑动和缩放的全屏查看器、视频播放、多选和分享。
• LUT 调色（Pro）：为 LOG 素材应用 .cube LUT，导出调色后的 H.265 副本。实时 LUT 预览免费。
• 安全释放空间：备份后可删除已复制并校验的源文件，并有确认码保护。
• 报告与历史记录：按目的地显示已复制、已跳过和失败的文件。
• 在后台运行，带通知和停止按钮；可从中断处继续。
• 支持简体中文、英语、法语、德语、西班牙语、意大利语、葡萄牙语和俄语。

免费：将相册备份到一个文件夹，浏览和预览备份。Pro 为一次性购买，无需订阅：相机和 SD 卡来源、第二个目的地、NAS 与 LUT 调色。

无需账号，无广告，无跟踪：您的媒体文件绝不会经过我们的服务器。

隐私政策：%s""",
)

L["ru-RU"] = dict(
short="Резервные копии фото и видео на SSD, SD-карту или NAS с проверкой SHA-256.",
body="""PhotoVideoBackup копирует ваши фото и видео с телефона или с карты памяти камеры на внешний SSD, USB-накопитель или NAS. Каждый файл проверяется побайтово, поэтому вы не получите повреждённую копию, не заметив этого.

• Копируйте галерею в любую папку: на SSD или USB-накопитель, подключённые к телефону, либо в память самого телефона.
• Карты камер и дроны (Pro): DJI, DJI 360 / Action, GoPro, Insta360 и обычные карты распознаются автоматически.
• NAS по Wi-Fi (Pro): прямое копирование на Synology или любую SMB-папку — в вашей сети или удалённо через VPN.
• Два места назначения сразу (Pro): зеркальная копия на два диска или на диск и NAS. Если один пропадёт посреди копирования, второй продолжит работу.
• Проверка SHA-256: каждая копия считывается заново и сравнивается с оригиналом.
• Без дубликатов: уже сохранённый файл распознаётся и пропускается, даже если вы его потом отредактировали; другой файл никогда не перезаписывается.
• Ваши папки, ваши имена: раскладка по дате, месяцу или году/месяцу и имена файлов по шаблону вроде 2025-06-14 15H30M12 Pixel.
• Просмотр копии: папки, миниатюры, полноэкранный просмотр со свайпом и масштабированием, воспроизведение видео, множественный выбор и отправка.
• LUT Grade (Pro): примените LUT .cube к LOG-материалу и экспортируйте обработанную копию в H.265. Предпросмотр LUT в реальном времени бесплатен.
• Безопасное освобождение места: после копирования удалите исходные файлы, которые скопированы и проверены, — под защитой кода подтверждения.
• Отчёты и история: что скопировано, пропущено или не удалось — по каждому месту назначения.
• Работает в фоне с уведомлением и кнопкой «Стоп»; продолжает с того места, где остановился.
• Доступно на русском, английском, французском, немецком, испанском, итальянском, португальском и китайском (упрощённом).

Бесплатно: копирование галереи в одну папку, просмотр копий. Pro — разовая покупка без подписки: источники камеры и SD-карты, второе место назначения, NAS и цветокоррекция LUT.

Без аккаунта, без рекламы, без отслеживания: ваши файлы никогда не проходят через наши серверы.

Политика конфиденциальности: %s""",
)

out, ok = {}, True
for k, v in L.items():
    full = v["body"] % POLICY
    out[k] = {"title": TITLE, "short": v["short"], "full": full}
    for f, lim in (("title", 30), ("short", 80), ("full", 4000)):
        if len(out[k][f]) > lim:
            print("TOO LONG", k, f, len(out[k][f]), ">", lim); ok = False
(pathlib.Path(__file__).resolve().parent.parent / "store" / "play_listing.json").write_text(json.dumps(out, ensure_ascii=False, indent=1))
print("OK" if ok else "ERRORS", {k: (len(v["short"]), len(v["full"])) for k, v in out.items()})
