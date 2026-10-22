UI = {
    "guide_title": "PhotoVideoBackup — Benutzerhandbuch",
    "tagline": "Sichern Sie Ihre Fotos und Videos auf einer externen SSD, einer SD-Karte oder einem NAS — von Ihrem iPhone oder Android-Smartphone.",
    "version_line": "Handbuch für PhotoVideoBackup 2.6 (iPhone, iOS 16 oder neuer) und 1.0 (Android 9 oder neuer)",
    "toc": "Inhalt",
    "privacy_link": "Datenschutzerklärung",
    "contact": "Support",
    "back": "Zurück zum Benutzerhandbuch",
    "footer": "PhotoVideoBackup · Fotos und Videos, sicher kopiert",
    "chooser_tagline": "Fotos und Videos sicher sichern",
    "chooser_privacy": "Datenschutzerklärung",
}

GUIDE = [
    ("what", "Was ist PhotoVideoBackup?", [
        ("p", "PhotoVideoBackup kopiert Ihre Fotos und Videos von Ihrem Smartphone — oder von einer Kamera-Speicherkarte — auf eine tragbare SSD, einen USB-Stick oder ein <b>NAS</b>. Ihre Dateien laufen nie über einen Online-Dienst: Die App hat weder Server noch Konto."),
        ("ul", ["Der Speicher Ihres Telefons ist voll und Sie möchten sicher Platz schaffen.", "Sie kommen von einer Reise zurück, mit einer SD-Karte voller Aufnahmen (DJI, GoPro, Insta360, Blackmagic…), und wollen sie sofort sichern.", "Sie möchten eine eigene Kopie, die nicht von iCloud oder Google Fotos abhängt."]),
        ("p", "<b>Was macht sie zuverlässig?</b> Jede kopierte Datei wird zurückgelesen und mit einem mathematischen Fingerabdruck (SHA-256) geprüft. Ist auch nur ein Byte falsch, sagt Ihnen die App Bescheid — Sie haben nie ein unbemerkt beschädigtes Backup."),
        ("p", "Die App <b>kopiert</b> nur. Sie verschiebt oder löscht nie etwas an der Quelle, außer Sie verlangen es nach einem Backup ausdrücklich (siehe „Verlauf und Berichte“)."),
    ]),
    ("pro", "Kostenlos und Pro", [
        ("p", "PhotoVideoBackup ist kostenlos. Ein einmaliger <b>Pro</b>-Kauf — <b>ohne Abo</b> — schaltet die erweiterten Funktionen frei:"),
        ("table", ["Funktion", "Kostenlos", "Pro"], [
            ["Fotomediathek auf ein Laufwerk oder einen Ordner sichern", "✓", "✓"],
            ["Backups durchsuchen und ansehen (inkl. LUT-Vorschau)", "✓", "✓"],
            ["Kamerakarten und USB-Laufwerke sichern (SD, DJI, GoPro, Insta360…)", "—", "✓"],
            ["Spiegelung auf ein zweites Laufwerk", "—", "✓"],
            ["Per WLAN auf ein NAS sichern", "—", "✓"],
            ["LOG-Videos mit einer LUT graden (H.265-Export)", "—", "✓"],
        ]),
        ("fig", "paywall", "Der Upgrade-Bildschirm. Sie öffnen ihn jederzeit im Tab „Einstellungen“."),
    ]),
    ("need", "Was Sie brauchen", [
        ("table", ["", "iPhone / iPad", "Android"], [
            ["Das Gerät", "Ein iPhone mit USB-C-Anschluss (iPhone 15 oder neuer), iOS 16 oder neuer", "Ein Android-Smartphone oder -Tablet, Android 9 oder neuer"],
            ["Ein Laufwerk", "Jede USB-C-SSD (Samsung T7, SanDisk Extreme, WD My Passport…)", "Jede USB-C-SSD oder jeder USB-Stick, oder ein Ordner auf dem Telefon"],
            ["Hub oder Kartenleser (optional)", "Ein kleiner USB-C-Hub, um SSD und Kartenleser zusammen anzuschließen", "Ein USB-C-Kartenleser oder ein OTG-Hub"],
        ]),
        ("note", "Viel Video zu kopieren verbraucht Akku. Schließen Sie das Telefon an oder starten Sie mit gutem Ladestand."),
    ]),
    ("start", "Erster Start und Berechtigungen", [
        ("p", "Ein Willkommensbildschirm stellt die App und fünf typische Aufbauten vor — vom einfachen Telefon → SSD bis zum NAS über ein VPN. Tippen Sie auf <b>Loslegen</b>."),
        ("fig", "onboarding_simple", "Der einfachste Aufbau: Telefon → SSD."),
        ("ul", ["<b>iPhone / iPad</b>: Erlauben Sie den <b>vollen Zugriff</b> auf Ihre Fotomediathek. Ohne ihn kann die App Ihre Fotos nicht lesen.", "<b>Android</b>: Erlauben Sie den Zugriff auf Ihre Fotos und Videos. Erlauben Sie auch den Zugriff auf den <b>Standort Ihrer Fotos</b> — sonst entfernt Android die GPS-Daten aus den Dateien, die es herausgibt, und das Backup wäre nicht das Original. Erlauben Sie Benachrichtigungen, damit Sie am Ende eines Backups Bescheid bekommen."]),
        ("note", "Die App liest Ihre Fotos nur, um sie zu kopieren. Sie verändert, teilt oder sendet sie nirgendwohin."),
    ]),
    ("setup", "Gerätenamen und Ziel festlegen", [
        ("ol", ["Öffnen Sie den Tab <b>Einstellungen</b>. Geben Sie im Abschnitt <b>Gerät</b> einen <b>Ordnernamen</b> ein — zum Beispiel <i>Annas iPhone</i> oder <i>Pixel 8</i>. Er wird zum Ordnernamen auf dem Laufwerk, sodass zwei Telefone auf demselben Laufwerk getrennt bleiben. Ohne Namen startet kein Backup.", "Schließen Sie Ihr Laufwerk an.", "Tippen Sie unter <b>Ziele</b> auf <b>Auswählen…</b> und wählen Sie das Laufwerk oder einen Ordner darauf im Dateibrowser des Systems. Unter Android können Sie auch einen Ordner im Telefonspeicher wählen.", "Der Laufwerksname erscheint in den Einstellungen und im Tab Backup, mit dem freien Speicherplatz. Das tun Sie nur einmal: Beim nächsten Mal erkennt die App das Laufwerk wieder."]),
        ("fig", "settings_configured", "Einstellungen: Gerätename und erstes Ziel."),
        ("note", "Ein Ziel kann auch ein Ordner in <b>iCloud Drive</b> sein (iPhone) — die App gibt die lokale Kopie frei, sobald iCloud den Upload bestätigt, damit das Telefon nicht volläuft."),
    ]),
    ("photos", "Fotos und Videos sichern", [
        ("p", "Öffnen Sie den Tab <b>Backup</b>. Oben sehen Sie Ihre Ziele mit dem freien Speicherplatz. Unter <b>Quellen</b> zeigt die Zeile <b>Fotomediathek</b> Ihren Gerätenamen. Tippen Sie auf <b>Backup</b>."),
        ("fig", "dashboard_ready", "Der Tab Backup: Ziel verbunden, Fotomediathek bereit."),
        ("p", "Die App durchsucht die Mediathek und kopiert dann. Das <b>erste Backup dauert am längsten</b>; die folgenden kopieren nur Neues und sind viel schneller."),
        ("ul", ["Fotos, die nur in iCloud / Google Fotos liegen, werden zuerst geladen — das braucht eine Verbindung und etwas Zeit.", "Die App kopiert jede Datei direkt zum Ziel, es funktioniert also auch bei fast vollem Telefon.", "Sie können die App verlassen: Eine Benachrichtigung meldet das Ende des Backups."]),
    ]),
    ("sd", "Eine Kamerakarte sichern (Pro)", [
        ("ol", ["Schließen Sie den Kartenleser an und stecken Sie die Karte ein (nutzen Sie einen Hub, wenn die SSD angeschlossen bleiben soll).", "Tippen Sie im Tab Backup auf <b>Quelle hinzufügen (SD-Karte, USB-Laufwerk…)</b>, suchen Sie die Karte im Dateibrowser und bestätigen Sie.", "Geben Sie der Quelle einen Namen — <i>Blackmagic</i>, <i>Japanreise</i>… Der Gerätetyp wird automatisch erkannt.", "Tippen Sie in der Zeile der Quelle auf <b>Backup</b>."]),
        ("table", ["Erkanntes Gerät", "Was gesichert wird"], [
            ["DJI Mini 3 Pro", "Fotos, Videos, DNG und die Telemetrie (.srt)"],
            ["DJI 360 / Action (Neo 2…)", "Videos, Fotos, DNG, Audio und die Telemetrie (.srt)"],
            ["Insta360 (X5…)", "Dateien .insv, .insp und .lrv"],
            ["GoPro HERO", "Videos und Fotos; Proxy- (.lrv) und Vorschaudateien (.thm) werden übersprungen"],
            ["Alles andere", "Gängige Foto-, Video- und RAW-Formate"],
        ]),
        ("note", "Eine ausgeworfene und wieder eingesteckte Karte braucht einen Tipp auf <b>Erneut verbinden</b>: Das System gibt der App bei jedem Einbinden der Karte einen neuen Zugriff. Name und Typ der Quelle bleiben erhalten."),
        ("p", "Um eine Quelle aus der Liste zu entfernen, nutzen Sie das rote <b>–</b> (iPhone) oder die Entfernen-Taste der Zeile (Android). Es wird keine Datei gelöscht."),
    ]),
    ("progress", "Während das Backup läuft", [
        ("p", "Ein Feld <b>Backup läuft</b> erscheint, sobald Sie auf Backup tippen. Zuerst <b>Vorbereiten…</b> (Verbindung zu Ihren Zielen), dann <b>Quelle wird analysiert…</b> mit einem Live-Zähler der gefundenen Dateien — bei einer großen Mediathek kann das dauern, es hängt nicht."),
        ("fig", "progress_backup", "Backup läuft: Prozent, erledigte Dateien, Restzeit, aktuelle Datei."),
        ("table", ["Phase", "Was die App tut"], [
            ["Analyse", "Zählt die Dateien und prüft, welche kopiert werden müssen."],
            ["Kopieren", "Schreibt die Datei auf das Ziel."],
            ["Prüfen", "Liest die Kopie zurück und vergleicht sie mit dem Original."],
            ["Übersprungen", "Die Datei ist schon gesichert — nichts zu tun."],
        ]),
        ("note", "Trennen Sie Laufwerk oder Karte nicht, solange ein Backup läuft. Verschwindet ein Laufwerk trotzdem, machen die anderen Ziele weiter, und die Sitzung wird als <b>Teilweise</b> markiert."),
        ("p", "Mit <b>Stoppen</b> beenden Sie das Backup jederzeit sauber. Unter Einstellungen → Backup gibt es außerdem die Grenze <b>Max. Dateien pro Sitzung</b>: Leer lassen heißt unbegrenzt."),
    ]),
    ("done", "Wenn das Backup fertig ist", [
        ("fig", "completion_banner", "Das Abschlussbanner: kopiert, übersprungen, fehlgeschlagen, Größe und Dauer."),
        ("table", ["Zahl", "Bedeutung"], [
            ["Kopiert", "Dateien, die zum ersten Mal auf dem Ziel gespeichert wurden."],
            ["Übersprungen", "Dateien, die schon da waren — normal und unbedenklich."],
            ["Fehlgeschlagen", "Dateien, die nicht kopiert werden konnten (selten)."],
        ]),
        ("p", "Ein Fehler kommt von einer beschädigten Karte, einem vollen Laufwerk, einer abgebrochenen Verbindung oder einer einzelnen Datei, die für den freien Platz zu groß ist — nur diese Datei wird gemeldet, der Rest läuft weiter. Schaffen Sie Platz oder verbinden Sie neu und starten Sie das Backup erneut: Fehlendes wird nachgeholt."),
    ]),
    ("history", "Verlauf und Berichte", [
        ("p", "Der Tab <b>Verlauf</b> listet jedes Backup: Quelle, Ziele, Ordnerstruktur, Dateianzahl und eine Farbe — grün für Erfolg, orange für <b>Teilweise</b>, rot bei Fehlern."),
        ("fig", "history_list", "Verlauf: eine abgeschlossene Sitzung."),
        ("p", "<b>Teilweise</b> heißt, dass das Backup vorzeitig endete, aus einem von drei Gründen, die der Bericht nennt: Sie haben <b>Stoppen</b> getippt, die <b>Dateigrenze</b> wurde erreicht oder ein <b>Ziel wurde getrennt</b>. Laufwerk wieder anschließen und erneut starten — es macht dort weiter, wo es aufgehört hat."),
        ("p", "Tippen Sie auf eine Sitzung für ihren Bericht: Zusammenfassung, SHA-256-Status und die Listen der kopierten, übersprungenen und fehlgeschlagenen Dateien — mit dem Grund jedes Fehlers. Bei zwei Zielen zeigt der Bericht jedes Laufwerk getrennt."),
        ("fig", "report_summary", "Ein Sitzungsbericht."),
        ("p", "<b>Quelldateien löschen…</b> schafft Platz auf der Karte oder in der Mediathek, wenn Sie mit dem Backup zufrieden sind. Angeboten werden nur Dateien, die kopiert <i>und</i> geprüft wurden, und zur Bestätigung geben Sie einen vierstelligen Code ein. Ihr Backup bleibt unberührt. Bei Fotos verlangt das System auf iPhone und Android noch eine weitere Bestätigung."),
        ("fig", "report_delete_confirm", "Die Eingabe des Codes bestätigt das Löschen."),
        ("note", "<b>Verlauf löschen</b> entfernt nur die Einträge in der App. Ihre Dateien bleiben, wo sie sind."),
    ]),
    ("browse", "Backups durchsuchen, ansehen und teilen", [
        ("p", "Der Tab <b>Durchsuchen</b> zeigt in der App, was auf Ihren Laufwerken liegt: ein Ordner pro Gerät, dann Ihre Datumsordner, dann ein Raster aus Vorschaubildern. Tippen Sie auf ein Foto, um es im Vollbild zu öffnen — wischen zum Wechseln, zwei Finger zum Zoomen — oder auf ein Video, um es abzuspielen. Das Laufwerk muss angeschlossen sein."),
        ("fig", "browse_device_folders", "Durchsuchen: die Geräteordner eines Laufwerks."),
        ("fig", "browse_media_grid", "Das Medienraster eines Tages."),
        ("p", "Um Dateien weiterzugeben: Tippen Sie auf <b>Auswählen</b>, markieren Sie die Dateien und dann auf <b>Teilen</b> — AirDrop, Nachrichten, E-Mail, eine andere App."),
        ("fig", "android_viewer", "Android: der Vollbild-Betrachter."),
        ("p", "Bei einem NAS listet Durchsuchen die Dateien und lädt jede erst, wenn Sie sie öffnen."),
    ]),
    ("naming", "Ordner und Dateinamen", [
        ("p", "Unter <b>Einstellungen → Backup</b> legt <b>Ordnerstruktur</b> fest, wie ein Geräteordner aufgebaut ist: <i>Flat</i> (flach), <i>By month</i> (nach Monat), <i>By date</i> (nach Datum, Standard) oder <i>By year / month</i> (Jahr / Monat). Der Tab Durchsuchen passt sich an, was auf dem Laufwerk liegt."),
        ("p", "<b>Dateibenennung</b> gibt jeder Datei ihren endgültigen Namen <b>beim ersten Kopieren</b> — sie wird nie unter dem Kameranamen gespeichert und danach umbenannt. Schalten Sie <b>Dateien beim Backup umbenennen</b> ein und bearbeiten Sie das Muster: Tippen Sie auf ein Token, um es einzufügen; alles andere ist Text. Eine Zeile <b>Beispiel</b> zeigt das Ergebnis."),
        ("fig", "settings_file_naming", "Dateibenennung: Muster, Token und Live-Beispiel."),
        ("table", ["Token", "Ersetzt durch"], [
            ["{YYYY} {MM} {DD}", "Jahr, Monat, Tag der Aufnahme"],
            ["{hh} {mm} {ss}", "Stunde, Minute, Sekunde der Aufnahme (Ortszeit)"],
            ["{device}", "Der Name des Geräteordners, ohne Leerzeichen"],
            ["{original}", "Der ursprüngliche Dateiname ohne Endung"],
        ]),
        ("ul", ["<b>Nichts wird je überschrieben.</b> Ist der Name von einer anderen Datei belegt, erhält die neue ein Suffix <code>-1</code>, <code>-2</code>… Nehmen Sie die Sekunden ins Muster auf, damit zwei gleichzeitige Aufnahmen verschiedene Namen behalten.", "<b>Duplikate werden an diesem Namen erkannt.</b> Eine bereits gesicherte Datei wird übersprungen — auch wenn Sie sie inzwischen bearbeitet haben — und eine andere Datei mit demselben Namen bleibt getrennt.", "<b>Vorhandene Dateien werden nicht umbenannt.</b> Das Profil gilt für Dateien, die ab jetzt kopiert werden. Bei ausgeschaltetem Profil (Standard) behalten die Dateien ihre Kameranamen."]),
        ("p", "Sie können auch <b>zusätzliche Dateiendungen</b> angeben, die neben den Medien kopiert werden — zum Beispiel <code>gpx</code>-GPS-Logs."),
    ]),
    ("lut", "LUT Grade: LOG-Material den Look geben (Pro)", [
        ("p", "In <b>LOG</b> gedrehtes Material (DJI D-Log M, GoPro Protune…) wirkt flach und grau, bis eine <b>LUT</b> angewendet wird. Weisen Sie in Durchsuchen einem Geräteordner eine LUT zu, um in der App Vorschau und Grading zu nutzen."),
        ("ol", ["Öffnen Sie einen Geräteordner und tippen Sie unter <b>LUT Grade</b> auf <b>LUT zuweisen…</b>, dann auf <b>LUT importieren (.cube)…</b>. Jede gängige <code>.cube</code>-Datei funktioniert (DaVinci Resolve, Final Cut Pro, Ihr Kamerahersteller).", "Tippen Sie auf ein Video dieses Ordners: Es wird mit der LUT in Echtzeit abgespielt. Diese Vorschau ist <b>kostenlos</b>.", "Für dauerhafte Kopien (Pro) tippen Sie auf <b>Auswählen</b>, wählen die Videos und dann auf <b>Graden</b>. Jedes wird in <b>H.265</b> mit eingebrannter LUT neu codiert, in einen Nachbarordner namens <b>Gerät (Graded)</b>."]),
        ("fig", "browse_lut_picker", "Eine LUT für einen Ordner wählen."),
        ("fig", "android_lut", "Android: der Bereich LUT Grade eines Geräteordners."),
        ("ul", ["Gegradet wird Video für Video, nie „alles“ — ein Ordner mischt oft LOG- und normale Clips, und eine LOG-LUT würde die normalen verderben.", "Bereits gegradete Dateien werden übersprungen, ein erneuter Lauf ist unbedenklich. Abbrechen jederzeit: Fertiges bleibt erhalten.", "Grading ist aufwendig: Lassen Sie die App geöffnet und das Laufwerk verbunden. Das Telefon kann warm werden.", "Bei einem NAS werden die Clips geladen, auf dem Telefon gegradet und in einen Ordner <b>Gerät (Graded)</b> auf dem NAS hochgeladen — langsamer und datenhungrig."]),
    ]),
    ("mirror", "Zwei Ziele gleichzeitig (Pro)", [
        ("p", "Fügen Sie in den Einstellungen ein zweites Ziel hinzu: Jede Datei wird gleichzeitig auf beide kopiert — zwei Laufwerke oder ein Laufwerk und ein NAS. Das Backup dauert nicht doppelt so lang. Fällt ein Ziel aus oder verschwindet, <b>macht das andere weiter</b>, und der Bericht nennt, was wo fehlt."),
        ("note", "Ist beim Start nur eines der beiden Laufwerke angeschlossen, kopiert die App trotzdem darauf und markiert die Sitzung für das andere als unvollständig."),
    ]),
    ("nas", "Per WLAN auf ein NAS sichern (Pro)", [
        ("p", "Statt eines Laufwerks — oder zusätzlich — können Sie direkt auf ein <b>NAS</b> (Synology, QNAP, TrueNAS, jedes SMB-fähige Gerät) über das Netzwerk sichern. Kein Kabel, keine Cloud, und jede Datei wird per SHA-256 geprüft."),
        ("ol", ["Aktivieren Sie am NAS die <b>SMB-Dateifreigabe</b> und geben Sie einem Benutzer Lese- und Schreibzugriff auf einen freigegebenen Ordner.", "In der App: <b>Einstellungen → Ziele → NAS (SMB)</b>.", "Tragen Sie <b>Host</b> (z. B. <code>192.168.1.20</code>), <b>Freigabe</b> (z. B. <code>photo</code>), einen optionalen <b>Ordner</b> sowie <b>Benutzername</b> und <b>Passwort</b> ein. Das Passwort liegt im iOS-Schlüsselbund bzw. im Android Keystore.", "Tippen Sie auf <b>Verbindung testen</b>: Eine Meldung bestätigt die Verbindung und die Zahl der gefundenen Einträge. Dann <b>Sichern</b>."]),
        ("p", "Das NAS erscheint jetzt im Tab Backup mit seinem freien Speicherplatz. Sie können auch <b>von unterwegs</b> sichern, wenn das NAS erreichbar ist — am einfachsten und sichersten mit einem VPN wie <b>Tailscale</b>: auf NAS und Telefon installieren und die <code>100.x.x.x</code>-Adresse des NAS als Host verwenden."),
        ("note", "Bei mobilen Daten warnt ein oranger Hinweis, dass große Videos viel Datenvolumen verbrauchen können; <b>Stoppen</b> hält das Backup an (es wird als Teilweise markiert)."),
    ]),
    ("android", "Android und iPhone: die Unterschiede", [
        ("p", "Beide Apps teilen sich denselben Kern: dieselbe Duplikaterkennung, dieselbe Benennung, dieselbe SHA-256-Prüfung, denselben Index — ein auf dem einen begonnenes Backup wird vom anderen erkannt."),
        ("table", ["", "iPhone / iPad", "Android"], [
            ["Quelle Mediathek", "Fotomediathek", "Galerie (Fotos und Videos)"],
            ["Ziel", "In Dateien gewählter Ordner (SSD, iCloud Drive, SMB)", "Mit der Systemauswahl gewählter Ordner (SSD, USB, Telefonspeicher), NAS"],
            ["Hintergrund", "Etwa 30 Sekunden, danach bleibt der Bildschirm während des Backups an", "Eine Vordergrund-Benachrichtigung hält es am Laufen, mit Stopp-Taste"],
            ["Pro", "In-App-Kauf (App Store)", "Einmalkauf (Google Play)"],
            ["Mac", "Läuft auf Macs mit Apple-Chip („Für iPad entwickelt“)", "—"],
        ]),
        ("note", "Unter Android wird ein Ziel im internen Speicher des Telefons vor der Galerie versteckt (eine Datei <code>.nomedia</code>), damit das Backup nicht erneut gesichert wird."),
        ("fig", "android_backup", "Android: der Tab Backup."),
        ("fig", "android_settings", "Android: Einstellungen."),
    ]),
    ("faq", "Häufige Fragen", [
        ("p", "<b>Kopiert sie dieselbe Datei zweimal, wenn ich erneut starte?</b> Nein. Jede Datei erhält am Ziel einen Namen, und das nächste Backup sucht sie unter diesem Namen. Zeigen die Aufzeichnungen der App, dass sie vom selben Original stammt, wird sie übersprungen — auch wenn Sie sie inzwischen bearbeitet haben. Nur wirklich verschiedene Dateien mit gleichem Namen erhalten ein Suffix <code>-1</code>, <code>-2</code>…, und nichts wird je überschrieben."),
        ("p", "<b>Wo merkt sich die App, was gesichert ist?</b> In ihrer eigenen Datenbank und in einer kleinen <b>versteckten Datei, <code>.pvb-index.json</code>, im Stammverzeichnis jedes Ziels</b>. Diese Kopie wandert mit dem Backup: Nach einer Neuinstallation oder von einem anderen Telefon liest die App sie und kopiert nichts doppelt. Sie können sie in Ruhe lassen; löschen Sie sie, baut die App sie neu auf."),
        ("p", "<b>Kann ich gleichzeitig auf ein NAS und ein Laufwerk sichern?</b> Ja — jedes verbundene Ziel erhält das Backup zur selben Zeit."),
        ("p", "<b>Die Verbindung zu meinem NAS läuft in ein Timeout.</b> Meist ist das NAS nicht erreichbar: Prüfen Sie, ob Sie im selben WLAN sind (oder das VPN läuft), ob die SMB-Freigabe aktiv ist und ob die NAS-Firewall die Verbindung erlaubt."),
        ("p", "<b>Kann ich zwei Telefone mit demselben Laufwerk nutzen?</b> Ja. Geben Sie jedem in den Einstellungen einen anderen Ordnernamen; jedes legt seinen eigenen Ordner auf dem Laufwerk an."),
        ("p", "<b>Der Balken zeigt 3 % und hängt scheinbar.</b> Die ersten Dateien sind oft große Videos. Warten Sie einige Minuten."),
        ("p", "<b>Meine Karte erscheint als „Documents“.</b> Manche Kameras nutzen einen allgemeinen Ordner. Geben Sie beim Hinzufügen der Quelle einen aussagekräftigen Namen ein."),
        ("p", "<b>Kann ich sichern, wenn mein Telefon fast voll ist?</b> Ja. Dateien werden direkt zum Ziel gestreamt, es werden nur wenige Megabyte gleichzeitig gehalten. Nur ein Backup <i>allein</i> auf ein NAS braucht Platz für jeweils eine Datei. Eine Datei, die wirklich nicht passt, wird als fehlgeschlagen gemeldet, der Rest läuft weiter."),
        ("p", "<b>Werden meine Daten irgendwohin gesendet?</b> Nein. Alles geschieht zwischen Ihrem Telefon und Ihrem Laufwerk oder NAS. Die App hat weder Server noch Konto. Netzwerkverkehr gibt es nur zum NAS, das Sie selbst einrichten, und beim Laden Ihrer eigenen iCloud- / Google-Fotos durch das System."),
        ("p", "<b>Welche Sprachen?</b> Englisch, Französisch, Deutsch, Spanisch, Italienisch, Portugiesisch, vereinfachtes Chinesisch und Russisch. Die App folgt der Telefonsprache; unter <b>Einstellungen → Sprache</b> können Sie eine erzwingen, ohne Neustart."),
    ]),
]

PRIVACY = {
    "title": "Datenschutzerklärung — PhotoVideoBackup",
    "updated": "Zuletzt aktualisiert: {date}",
    "summary": "PhotoVideoBackup erhebt, speichert, überträgt oder teilt keinerlei personenbezogene Daten. Es gibt kein Konto, keine Analyse, keine Werbung und keinen eigenen Server.",
    "sections": [
        ("Worauf die App zugreift", [
            ("ul", ["Ihre Fotos und Videos — <b>nur lesend</b>, um sie auf das von Ihnen gewählte Laufwerk, den Ordner oder das NAS zu kopieren. Unter Android umfasst das den in Ihren Fotos gespeicherten Standort, damit die Kopie dem Original entspricht.", "Die Ordner und Karten, die Sie im Dateibrowser des Systems auswählen.", "Benachrichtigungen, um Sie über das Ende eines Backups zu informieren."]),
        ]),
        ("Was Ihr Gerät verlässt", [
            ("ul", ["<b>Nichts gelangt zu uns.</b> Ihre Dateien werden nur auf die von Ihnen gewählten Ziele geschrieben.", "Wenn Sie ein NAS einrichten, verbindet sich die App mit <b>diesem Server</b> unter der von Ihnen eingegebenen Adresse und sonst nirgendwohin. Das Passwort liegt im iOS-Schlüsselbund oder im Android Keystore.", "iOS oder Android lädt möglicherweise Ihre eigenen iCloud- oder Google-Fotos, damit die App sie lesen kann; das erledigt das System für Ihr Konto.", "Käufe werden von Apple oder Google abgewickelt. Wir erhalten keine Zahlungsdaten."]),
        ]),
        ("Diagnoseprotokoll", [
            ("p", "Die App führt auf Ihrem Gerät ein kleines Diagnoseprotokoll ohne persönliche Inhalte. Es wird nur gesendet, wenn Sie es in der App per E-Mail an den Support schicken."),
        ]),
        ("Kontakt mit dem Support", [
            ("p", "Wenn Sie dem Support schreiben, erhalten wir, was Sie senden — Ihre Adresse und Ihre Nachricht — und verwenden es nur, um Ihnen zu antworten."),
        ]),
    ],
}
