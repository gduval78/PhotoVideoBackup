UI = {
    "guide_title": "PhotoVideoBackup — Guida utente",
    "tagline": "Copia le tue foto e i tuoi video su un SSD esterno, una scheda SD o un NAS — dal tuo iPhone o dal tuo telefono Android.",
    "version_line": "Guida di PhotoVideoBackup 2.6 (iPhone, iOS 16 o successivo) e 1.0 (Android 9 o successivo)",
    "toc": "Indice",
    "privacy_link": "Informativa sulla privacy",
    "contact": "Assistenza",
    "back": "Torna alla guida utente",
    "footer": "PhotoVideoBackup · Foto e video, copiati in sicurezza",
    "chooser_tagline": "Copia le tue foto e i tuoi video in sicurezza",
    "chooser_privacy": "Informativa sulla privacy",
}

GUIDE = [
    ("what", "Che cos'è PhotoVideoBackup?", [
        ("p", "PhotoVideoBackup copia le tue foto e i tuoi video dal telefono — o da una scheda di memoria di una fotocamera — su un SSD portatile, un'unità USB o un <b>NAS</b>. I tuoi file non passano mai da un servizio online: l'app non ha server né account."),
        ("ul", ["La memoria del telefono è piena e vuoi liberare spazio in sicurezza.", "Torni da un viaggio con una scheda SD piena di filmati (DJI, GoPro, Insta360, Blackmagic…) e vuoi metterli subito al sicuro.", "Vuoi una copia personale che non dipenda da iCloud o da Google Foto."]),
        ("p", "<b>Che cosa la rende affidabile?</b> Ogni file copiato viene riletto e controllato con un'impronta matematica (SHA-256). Se anche un solo byte è sbagliato, l'app te lo dice: non avrai mai un backup danneggiato senza saperlo."),
        ("p", "L'app si limita a <b>copiare</b>. Non sposta né elimina mai nulla dalla sorgente, a meno che tu non lo chieda esplicitamente dopo un backup (vedi «Cronologia e report»)."),
    ]),
    ("pro", "Gratis e Pro", [
        ("p", "PhotoVideoBackup è gratuita. Un acquisto <b>Pro</b> — pagato una sola volta, <b>senza abbonamento</b> — sblocca le funzioni avanzate:"),
        ("table", ["Funzione", "Gratis", "Pro"], [
            ["Copiare la libreria foto su un'unità o una cartella", "✓", "✓"],
            ["Sfogliare e visualizzare i backup (anteprima LUT inclusa)", "✓", "✓"],
            ["Copiare schede di fotocamere e unità USB (SD, DJI, GoPro, Insta360…)", "—", "✓"],
            ["Mirror su una seconda unità", "—", "✓"],
            ["Copiare su un NAS via Wi-Fi", "—", "✓"],
            ["Applicare una LUT a video LOG (esportazione H.265)", "—", "✓"],
        ]),
        ("fig", "paywall", "La schermata di aggiornamento. Aprila quando vuoi dalla scheda Impostazioni."),
    ]),
    ("need", "Che cosa ti serve", [
        ("table", ["", "iPhone / iPad", "Android"], [
            ["Il dispositivo", "Un iPhone con porta USB-C (iPhone 15 o successivo), iOS 16 o successivo", "Un telefono o tablet Android, Android 9 o successivo"],
            ["Un'unità", "Qualsiasi SSD USB-C (Samsung T7, SanDisk Extreme, WD My Passport…)", "Qualsiasi SSD o chiavetta USB-C, o una cartella del telefono"],
            ["Un hub o un lettore (facoltativo)", "Un piccolo hub USB-C per collegare insieme SSD e lettore di schede", "Un lettore di schede USB-C o un hub OTG"],
        ]),
        ("note", "Copiare molti video consuma batteria. Collega il telefono al caricatore o parti con una buona carica."),
    ]),
    ("start", "Primo avvio e autorizzazioni", [
        ("p", "Una schermata di benvenuto presenta l'app e cinque configurazioni tipiche — dal semplice telefono → SSD fino al NAS raggiunto tramite VPN. Tocca <b>Inizia</b>."),
        ("fig", "onboarding_simple", "La configurazione più semplice: telefono → SSD."),
        ("ul", ["<b>iPhone / iPad</b>: consenti l'<b>accesso completo</b> alla libreria foto. Senza di esso l'app non può leggere le tue foto.", "<b>Android</b>: consenti l'accesso a foto e video. Consenti anche l'accesso alla <b>posizione delle foto</b> — altrimenti Android toglie i dati GPS dai file che fornisce e il backup non sarebbe l'originale. Consenti le notifiche per essere avvisato alla fine di un backup."]),
        ("note", "L'app legge le tue foto solo per copiarle. Non le modifica, non le condivide e non le invia da nessuna parte."),
    ]),
    ("setup", "Imposta il nome del dispositivo e la destinazione", [
        ("ol", ["Apri la scheda <b>Impostazioni</b>. Nella sezione <b>Dispositivo</b>, scrivi un <b>nome cartella</b> — per esempio <i>iPhone di Anna</i> o <i>Pixel 8</i>. Diventa il nome della cartella sull'unità, così due telefoni che salvano sulla stessa unità restano separati. Un backup non parte finché non c'è un nome.", "Collega la tua unità.", "In <b>Destinazioni</b>, tocca <b>Scegli…</b> e seleziona l'unità, o una cartella al suo interno, nel gestore file del sistema. Su Android puoi anche scegliere una cartella nella memoria del telefono.", "Il nome dell'unità appare in Impostazioni e nella scheda Backup, con lo spazio libero. Lo fai una volta sola: la prossima volta l'app riconosce l'unità."]),
        ("fig", "settings_configured", "Impostazioni: nome del dispositivo e prima destinazione."),
        ("note", "Una destinazione può anche essere una cartella di <b>iCloud Drive</b> (iPhone) — l'app libera la copia locale quando iCloud conferma il caricamento, così il telefono non si riempie."),
    ]),
    ("photos", "Copia le tue foto e i tuoi video", [
        ("p", "Apri la scheda <b>Backup</b>. In alto vedi le destinazioni con lo spazio libero. In <b>Sorgenti</b>, la riga <b>Libreria Foto</b> mostra il nome del tuo dispositivo. Tocca il suo pulsante <b>Backup</b>."),
        ("fig", "dashboard_ready", "La scheda Backup: destinazione collegata, libreria foto pronta."),
        ("p", "L'app analizza la libreria e poi copia. Il <b>primo backup è il più lungo</b>; i successivi copiano solo il nuovo e sono molto più veloci."),
        ("ul", ["Le foto presenti solo su iCloud / Google Foto vengono prima scaricate — servono una connessione e un po' di tempo.", "L'app copia ogni file direttamente nella destinazione, quindi funziona anche con il telefono quasi pieno.", "Puoi uscire dall'app: una notifica ti avvisa quando il backup finisce."]),
    ]),
    ("sd", "Copia una scheda di fotocamera (Pro)", [
        ("ol", ["Collega il lettore di schede al telefono e inserisci la scheda (usa un hub se anche l'SSD deve restare collegato).", "Nella scheda Backup, tocca <b>Aggiungi sorgente (SD, USB…)</b>, trova la scheda nel gestore file e conferma.", "Dai un nome alla sorgente — <i>Blackmagic</i>, <i>Viaggio in Giappone</i>… Il tipo di dispositivo viene riconosciuto da solo.", "Tocca <b>Backup</b> sulla riga della sorgente."]),
        ("table", ["Dispositivo riconosciuto", "Che cosa viene copiato"], [
            ["DJI Mini 3 Pro", "Foto, video, DNG e la telemetria (.srt)"],
            ["DJI 360 / Action (Neo 2…)", "Video, foto, DNG, audio e la telemetria (.srt)"],
            ["Insta360 (X5…)", "File .insv, .insp e .lrv"],
            ["GoPro HERO", "Video e foto; i file proxy (.lrv) e delle miniature (.thm) vengono ignorati"],
            ["Tutto il resto", "Formati comuni di foto, video e RAW"],
        ]),
        ("note", "Una scheda espulsa e reinserita richiede un tocco su <b>Riconnetti</b>: il sistema dà all'app un nuovo accesso a ogni montaggio della scheda. Nome e tipo della sorgente restano invariati."),
        ("p", "Per rimuovere una sorgente dall'elenco usa il <b>–</b> rosso (iPhone) o il pulsante di rimozione della riga (Android). Nessun file viene eliminato."),
    ]),
    ("progress", "Mentre il backup è in corso", [
        ("p", "Un pannello <b>Backup in corso</b> compare appena tocchi Backup. Prima <b>Preparazione…</b> (connessione alle destinazioni), poi <b>Analisi della sorgente…</b> con un contatore in tempo reale dei file trovati — su una libreria grande può richiedere un po', non è bloccata."),
        ("fig", "progress_backup", "Backup in corso: percentuale, file completati, tempo rimanente, file corrente."),
        ("table", ["Fase", "Che cosa fa l'app"], [
            ["Analisi", "Conta i file e controlla quali vanno copiati."],
            ["Copia", "Scrive il file nella destinazione."],
            ["Verifica", "Rilegge la copia e la confronta con l'originale."],
            ["Ignorati", "Il file è già salvato — niente da fare."],
        ]),
        ("note", "Non scollegare l'unità o la scheda mentre un backup è in corso. Se un'unità sparisce comunque, le altre destinazioni proseguono e la sessione viene contrassegnata come <b>Parziale</b>."),
        ("p", "Un pulsante <b>Interrompi</b> termina il backup in modo pulito in qualsiasi momento. Impostazioni → Backup offre anche il limite <b>Max file per sessione</b>: lascialo vuoto per nessun limite."),
    ]),
    ("done", "Quando il backup è finito", [
        ("fig", "completion_banner", "Il banner finale: copiati, ignorati, falliti, dimensione e durata."),
        ("table", ["Numero", "Significato"], [
            ["Copiati", "File salvati per la prima volta nella destinazione."],
            ["Ignorati", "File già presenti — normale e senza rischi."],
            ["Falliti", "File che non è stato possibile copiare (raro)."],
        ]),
        ("p", "Un errore deriva da una scheda danneggiata, un'unità piena, una connessione caduta o un singolo file troppo grande per lo spazio libero — solo quel file viene segnalato e il resto prosegue. Libera spazio o ricollega, e rilancia il backup: i file mancanti vengono recuperati."),
    ]),
    ("history", "Cronologia e report", [
        ("p", "La scheda <b>Cronologia</b> elenca ogni backup: sorgente, destinazioni, struttura delle cartelle, numero di file e un colore — verde se è andato bene, arancione per <b>Parziale</b>, rosso in caso di errori."),
        ("fig", "history_list", "Cronologia: una sessione completata."),
        ("p", "<b>Parziale</b> significa che il backup si è fermato prima della fine, per uno di tre motivi indicati dal report: hai toccato <b>Interrompi</b>, è stato raggiunto il <b>limite di file</b> o una <b>destinazione si è scollegata</b>. Ricollega l'unità e rilancia — riprende da dove si era fermato."),
        ("p", "Tocca una sessione per il suo report: riepilogo, stato SHA-256 ed elenchi dei file copiati, ignorati e falliti — con il motivo di ogni errore. Con due destinazioni il report mostra ogni unità separatamente."),
        ("fig", "report_summary", "Il report di una sessione."),
        ("p", "<b>Elimina file sorgente…</b> libera spazio sulla scheda o nella libreria quando sei soddisfatto del backup. Propone solo i file copiati <i>e</i> verificati, e per confermare devi digitare un codice di quattro cifre. Il tuo backup non viene toccato. Su iPhone e Android il sistema chiede un'ulteriore conferma per le foto."),
        ("fig", "report_delete_confirm", "Digitare il codice conferma l'eliminazione."),
        ("note", "<b>Cancella cronologia</b> rimuove solo i registri all'interno dell'app. I tuoi file restano dove sono."),
    ]),
    ("browse", "Sfoglia, guarda e condividi i tuoi backup", [
        ("p", "La scheda <b>Sfoglia</b> mostra, dentro l'app, ciò che c'è sulle tue unità: una cartella per dispositivo, poi le cartelle per data, poi una griglia di miniature. Tocca una foto per aprirla a schermo intero — scorri per passare da un file all'altro, pizzica per ingrandire — o tocca un video per riprodurlo. L'unità deve essere collegata."),
        ("fig", "browse_device_folders", "Sfoglia: le cartelle dei dispositivi di un'unità."),
        ("fig", "browse_media_grid", "La griglia dei contenuti di un giorno."),
        ("p", "Per inviare file altrove: tocca <b>Seleziona</b>, spunta i file e poi <b>Condividi</b> — AirDrop, messaggi, e-mail, un'altra app."),
        ("fig", "android_viewer", "Android: il visualizzatore a schermo intero."),
        ("p", "Su un NAS, Sfoglia elenca i file e scarica ciascuno solo quando lo apri."),
    ]),
    ("naming", "Cartelle e nomi dei file", [
        ("p", "In <b>Impostazioni → Backup</b>, <b>Struttura cartelle</b> stabilisce come è organizzata una cartella di dispositivo: <i>Flat</i> (piatta), <i>By month</i> (per mese), <i>By date</i> (per data, predefinita) o <i>By year / month</i> (anno / mese). La scheda Sfoglia si adatta a ciò che c'è sull'unità."),
        ("p", "<b>Nome dei file</b> dà a ogni file il suo nome definitivo <b>al momento della prima copia</b> — non viene mai salvato con il nome della fotocamera e rinominato dopo. Attiva <b>Rinomina i file durante il backup</b> e modifica il modello: tocca un segnaposto per inserirlo, tutto il resto è testo letterale. Una riga <b>Esempio</b> mostra il risultato."),
        ("fig", "settings_file_naming", "Nome dei file: modello, segnaposto ed esempio dal vivo."),
        ("table", ["Segnaposto", "Sostituito da"], [
            ["{YYYY} {MM} {DD}", "Anno, mese, giorno dello scatto"],
            ["{hh} {mm} {ss}", "Ora, minuto, secondo dello scatto (ora locale)"],
            ["{device}", "Il nome della cartella del dispositivo, senza spazi"],
            ["{original}", "Il nome originale del file, senza estensione"],
        ]),
        ("ul", ["<b>Nulla viene mai sovrascritto.</b> Se il nome è occupato da un file diverso, il nuovo riceve un suffisso <code>-1</code>, <code>-2</code>… Includi i secondi nel modello perché due scatti simultanei mantengano nomi diversi.", "<b>I duplicati vengono riconosciuti da quel nome.</b> Un file già salvato viene ignorato — anche se l'hai modificato nel frattempo — e un file diverso con lo stesso nome resta separato.", "<b>I file esistenti non vengono rinominati.</b> Il profilo si applica ai file copiati da ora in poi. Con il profilo disattivato (predefinito) i file mantengono il nome della fotocamera."]),
        ("p", "Puoi anche aggiungere <b>estensioni di file aggiuntive</b> da copiare insieme ai contenuti — per esempio i log GPS <code>gpx</code>."),
    ]),
    ("lut", "LUT Grade: dare il look ai filmati LOG (Pro)", [
        ("p", "I filmati girati in <b>LOG</b> (DJI D-Log M, GoPro Protune…) appaiono piatti e grigi finché non si applica una <b>LUT</b>. In Sfoglia, assegna una LUT a una cartella di dispositivo per visualizzare l'anteprima e applicare la gradazione senza uscire dall'app."),
        ("ol", ["Apri una cartella di dispositivo e, in <b>LUT Grade</b>, tocca <b>Assegna LUT…</b> e poi <b>Importa LUT (.cube)…</b>. Va bene qualsiasi file <code>.cube</code> standard (DaVinci Resolve, Final Cut Pro, il produttore della tua fotocamera).", "Tocca un video di quella cartella: viene riprodotto con la LUT applicata in tempo reale. Questa anteprima è <b>gratuita</b>.", "Per creare copie permanenti (Pro), tocca <b>Seleziona</b>, scegli i video e poi <b>Gradazione</b>. Ognuno viene ricodificato in <b>H.265</b> con la LUT incorporata, in una cartella affiancata chiamata <b>Dispositivo (Graded)</b>."]),
        ("fig", "browse_lut_picker", "Scegliere una LUT per una cartella."),
        ("fig", "android_lut", "Android: la sezione LUT Grade di una cartella di dispositivo."),
        ("ul", ["La gradazione si fa video per video, mai «tutto» — una cartella spesso mescola clip LOG e normali, e una LUT LOG rovinerebbe quelle normali.", "I file già graduati vengono ignorati, quindi puoi rilanciare senza rischi. Annulla quando vuoi: i file terminati restano.", "La gradazione è impegnativa: tieni l'app aperta e l'unità collegata. Il telefono può scaldarsi.", "Su un NAS i clip vengono scaricati, graduati sul telefono e caricati in una cartella <b>Dispositivo (Graded)</b> sul NAS — più lento e consuma dati."]),
    ]),
    ("mirror", "Due destinazioni insieme (Pro)", [
        ("p", "In Impostazioni, aggiungi una seconda destinazione: ogni file viene copiato su entrambe contemporaneamente — due unità, oppure un'unità e un NAS. Il backup non dura il doppio. Se una destinazione si guasta o sparisce, <b>l'altra prosegue</b>, e il report dice che cosa manca dove."),
        ("note", "Se all'avvio è collegata una sola delle due unità, l'app copia comunque su di essa e contrassegna la sessione come incompleta per l'altra."),
    ]),
    ("nas", "Copia su un NAS via Wi-Fi (Pro)", [
        ("p", "Al posto di un'unità — o in aggiunta — puoi copiare direttamente su un <b>NAS</b> (Synology, QNAP, TrueNAS, qualsiasi dispositivo che parli SMB) attraverso la rete. Niente cavo, niente cloud, e ogni file viene verificato con SHA-256."),
        ("ol", ["Sul NAS, abilita la <b>condivisione file SMB</b> e dai a un utente accesso in lettura e scrittura a una cartella condivisa.", "Nell'app: <b>Impostazioni → Destinazioni → NAS (SMB)</b>.", "Compila <b>host</b> (es. <code>192.168.1.20</code>), <b>condivisione</b> (es. <code>photo</code>), una <b>cartella</b> facoltativa, e il tuo <b>nome utente</b> e <b>password</b>. La password è conservata nel Portachiavi di iOS o nel Keystore di Android.", "Tocca <b>Prova connessione</b>: un messaggio conferma la connessione e quanti elementi sono stati trovati. Poi <b>Salva</b>."]),
        ("p", "Il NAS ora compare nella scheda Backup con il suo spazio libero. Puoi copiare anche <b>fuori casa</b> se il NAS è raggiungibile — il modo più semplice e sicuro è una VPN come <b>Tailscale</b>: installala sul NAS e sul telefono e usa l'indirizzo <code>100.x.x.x</code> del NAS come host."),
        ("note", "Con i dati mobili, un banner arancione ti avverte che i video grandi possono consumare molti dati; <b>Interrompi</b> ferma il backup (viene contrassegnato come Parziale)."),
    ]),
    ("android", "Android e iPhone: le differenze", [
        ("p", "Le due app condividono lo stesso motore: stesso rilevamento dei duplicati, stessi nomi, stessa verifica SHA-256, stesso indice — un backup iniziato su una viene riconosciuto dall'altra."),
        ("table", ["", "iPhone / iPad", "Android"], [
            ["Sorgente libreria", "Libreria Foto", "Galleria (foto e video)"],
            ["Destinazione", "Cartella scelta in File (SSD, iCloud Drive, SMB)", "Cartella scelta con il selettore di sistema (SSD, USB, memoria del telefono), NAS"],
            ["Sfondo", "Circa 30 secondi, poi lo schermo resta acceso durante il backup", "Una notifica in primo piano lo mantiene attivo, con un pulsante Interrompi"],
            ["Pro", "Acquisto in-app (App Store)", "Acquisto una tantum (Google Play)"],
            ["Mac", "Funziona sui Mac con chip Apple («progettata per iPad»)", "—"],
        ]),
        ("note", "Su Android, una destinazione nella memoria interna del telefono viene nascosta alla galleria (un file <code>.nomedia</code>) perché il backup non venga copiato di nuovo."),
        ("fig", "android_backup", "Android: la scheda Backup."),
        ("fig", "android_settings", "Android: Impostazioni."),
    ]),
    ("faq", "Domande frequenti", [
        ("p", "<b>Copierà due volte lo stesso file se rilancio?</b> No. Ogni file riceve un nome nella destinazione e il backup successivo lo cerca con quel nome. Se i registri dell'app mostrano che proviene dallo stesso originale, viene ignorato — anche se l'hai modificato nel frattempo. Solo file davvero diversi con lo stesso nome ricevono un suffisso <code>-1</code>, <code>-2</code>…, e nulla viene mai sovrascritto."),
        ("p", "<b>Dove ricorda l'app ciò che ha copiato?</b> Nel suo database e in un piccolo <b>file nascosto, <code>.pvb-index.json</code>, nella radice di ogni destinazione</b>. Quella copia viaggia con il backup: dopo una reinstallazione, o da un altro telefono, l'app la legge e non copia di nuovo. Puoi lasciarla stare; se la elimini, l'app la ricostruisce."),
        ("p", "<b>Posso copiare su un NAS e su un'unità insieme?</b> Sì — ogni destinazione collegata riceve il backup nello stesso momento."),
        ("p", "<b>La connessione al mio NAS va in timeout.</b> Di solito il NAS non è raggiungibile: controlla di essere sulla stessa rete Wi-Fi (o che la VPN sia attiva), che la condivisione SMB sia abilitata e che il firewall del NAS consenta la connessione."),
        ("p", "<b>Posso usare due telefoni con la stessa unità?</b> Sì. Dai a ciascuno un nome cartella diverso in Impostazioni; ognuno crea la propria cartella sull'unità."),
        ("p", "<b>La barra indica il 3% e sembra bloccata.</b> I primi file sono spesso video grandi. Attendi qualche minuto."),
        ("p", "<b>La mia scheda appare come «Documents».</b> Alcune fotocamere usano una cartella generica. Scrivi un nome significativo quando aggiungi la sorgente."),
        ("p", "<b>Posso fare il backup con il telefono quasi pieno?</b> Sì. I file vengono trasmessi in streaming alla destinazione, quindi si trattengono solo pochi megabyte alla volta. Solo un backup su un NAS <i>da solo</i> richiede spazio per un file alla volta. Un file che davvero non ci sta viene segnalato come fallito e il resto prosegue."),
        ("p", "<b>I miei dati vengono inviati da qualche parte?</b> No. Tutto avviene tra il telefono e la tua unità o il tuo NAS. L'app non ha server né account. L'unico traffico di rete è verso il NAS che configuri tu e il download, da parte del sistema, delle tue foto iCloud / Google."),
        ("p", "<b>Quali lingue?</b> Inglese, francese, tedesco, spagnolo, italiano, portoghese, cinese semplificato e russo. L'app segue la lingua del telefono; puoi forzarne una in <b>Impostazioni → Lingua</b>, senza riavviare."),
    ]),
]

PRIVACY = {
    "title": "Informativa sulla privacy — PhotoVideoBackup",
    "updated": "Ultimo aggiornamento: {date}",
    "summary": "PhotoVideoBackup non raccoglie, conserva, trasmette né condivide alcun dato personale. Non ci sono account, analisi, pubblicità né un server proprio.",
    "sections": [
        ("A che cosa accede l'app", [
            ("ul", ["Alle tue foto e ai tuoi video — in <b>sola lettura</b>, per copiarli sull'unità, la cartella o il NAS che scegli. Su Android ciò include la posizione salvata nelle foto, perché la copia sia identica all'originale.", "Alle cartelle e alle schede che scegli con il gestore file del sistema.", "Alle notifiche, per avvisarti quando un backup finisce."]),
        ]),
        ("Che cosa esce dal tuo dispositivo", [
            ("ul", ["<b>Nulla arriva a noi.</b> I tuoi file vengono scritti solo nelle destinazioni che scegli.", "Se configuri un NAS, l'app si connette a <b>quel server</b>, all'indirizzo che hai inserito, e da nessun'altra parte. La password è conservata nel Portachiavi di iOS o nel Keystore di Android.", "iOS o Android può scaricare le tue foto iCloud o Google perché l'app possa leggerle; lo fa il sistema, per il tuo account.", "Gli acquisti sono gestiti da Apple o Google. Non riceviamo alcuna informazione di pagamento."]),
        ]),
        ("Registro diagnostico", [
            ("p", "L'app tiene sul tuo dispositivo un piccolo registro diagnostico, senza contenuti personali. Viene inviato solo se scegli di inviarlo per e-mail all'assistenza dall'app."),
        ]),
        ("Contatto con l'assistenza", [
            ("p", "Se scrivi all'assistenza, riceviamo ciò che invii — il tuo indirizzo e il tuo messaggio — e lo usiamo solo per risponderti."),
        ]),
    ],
}
