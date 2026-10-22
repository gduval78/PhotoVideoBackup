UI = {
    "guide_title": "PhotoVideoBackup — Guide utilisateur",
    "tagline": "Sauvegardez vos photos et vidéos sur un SSD externe, une carte SD ou un NAS — depuis votre iPhone ou votre téléphone Android.",
    "version_line": "Guide de PhotoVideoBackup 2.6 (iPhone, iOS 16 ou plus récent) et 1.0 (Android 9 ou plus récent)",
    "toc": "Sommaire",
    "privacy_link": "Politique de confidentialité",
    "contact": "Support",
    "back": "Retour au guide utilisateur",
    "footer": "PhotoVideoBackup · Photos et vidéos, copiées en toute sécurité",
    "chooser_tagline": "Sauvegardez vos photos et vidéos en toute sécurité",
    "chooser_privacy": "Politique de confidentialité",
}

GUIDE = [
    ("what", "Qu'est-ce que PhotoVideoBackup ?", [
        ("p", "PhotoVideoBackup copie vos photos et vidéos depuis votre téléphone — ou depuis une carte mémoire d'appareil photo — vers un SSD portable, une clé USB ou un <b>NAS</b>. Vos fichiers ne passent jamais par un service en ligne : l'application n'a ni serveur ni compte."),
        ("ul", ["Le stockage de votre téléphone est plein et vous voulez libérer de la place en toute sécurité.", "Vous rentrez de voyage avec une carte SD pleine de rushs (DJI, GoPro, Insta360, Blackmagic…) et voulez les mettre à l'abri tout de suite.", "Vous voulez une copie personnelle qui ne dépende ni d'iCloud ni de Google Photos."]),
        ("p", "<b>Qu'est-ce qui la rend fiable ?</b> Chaque fichier copié est relu et vérifié par une empreinte mathématique (SHA-256). Si un seul octet est faux, l'application vous le dit — vous n'avez jamais une sauvegarde corrompue sans le savoir."),
        ("p", "L'application ne fait que <b>copier</b>. Elle ne déplace ni ne supprime jamais rien de la source, sauf si vous le demandez explicitement après une sauvegarde (voir « Historique et rapports »)."),
    ]),
    ("pro", "Gratuit et Pro", [
        ("p", "PhotoVideoBackup se télécharge gratuitement. Un achat <b>Pro</b> — payé une seule fois, <b>sans abonnement</b> — débloque les fonctions avancées :"),
        ("table", ["Fonction", "Gratuit", "Pro"], [
            ["Sauvegarder la photothèque vers un disque ou un dossier", "✓", "✓"],
            ["Parcourir et prévisualiser les sauvegardes (aperçu LUT compris)", "✓", "✓"],
            ["Sauvegarder cartes d'appareils et disques USB (SD, DJI, GoPro, Insta360…)", "—", "✓"],
            ["Copie miroir vers un second disque", "—", "✓"],
            ["Sauvegarder vers un NAS en Wi-Fi", "—", "✓"],
            ["Étalonner des vidéos LOG avec une LUT (export H.265)", "—", "✓"],
        ]),
        ("fig", "paywall", "L'écran de mise à niveau. Ouvrez-le quand vous voulez depuis l'onglet Réglages."),
    ]),
    ("need", "Ce qu'il vous faut", [
        ("table", ["", "iPhone / iPad", "Android"], [
            ["L'appareil", "Un iPhone avec port USB-C (iPhone 15 ou plus récent), iOS 16 ou plus récent", "Un téléphone ou une tablette Android, Android 9 ou plus récent"],
            ["Un disque", "N'importe quel SSD USB-C (Samsung T7, SanDisk Extreme, WD My Passport…)", "N'importe quel SSD ou clé USB-C, ou un dossier du téléphone"],
            ["Un hub ou un lecteur (facultatif)", "Un petit hub USB-C pour brancher ensemble un SSD et un lecteur de cartes", "Un lecteur de cartes USB-C, ou un hub OTG"],
        ]),
        ("note", "Copier beaucoup de vidéo consomme de la batterie. Branchez votre téléphone, ou partez avec une bonne charge."),
    ]),
    ("start", "Premier lancement et autorisations", [
        ("p", "Un écran d'accueil présente l'application et cinq montages types — du simple téléphone → SSD jusqu'au NAS atteint par un VPN. Touchez <b>Commencer</b>."),
        ("fig", "onboarding_simple", "Le montage le plus simple : téléphone → SSD."),
        ("ul", ["<b>iPhone / iPad</b> : autorisez l'<b>accès complet</b> à votre photothèque. Sans lui, l'application ne peut pas lire vos photos.", "<b>Android</b> : autorisez l'accès à vos photos et vidéos. Autorisez aussi l'accès à la <b>position de vos photos</b> — sans cela, Android retire les données GPS des fichiers qu'il fournit et la sauvegarde ne serait pas l'original. Autorisez les notifications pour être prévenu à la fin d'une sauvegarde."]),
        ("note", "L'application lit vos photos uniquement pour les copier. Elle ne les modifie, ne les partage et ne les envoie nulle part."),
    ]),
    ("setup", "Définir le nom de l'appareil et la destination", [
        ("ol", ["Ouvrez l'onglet <b>Réglages</b>. Dans la section <b>Appareil</b>, saisissez un <b>nom de dossier</b> — par exemple <i>iPhone d'Anna</i> ou <i>Pixel 8</i>. C'est le nom du dossier sur le disque : deux téléphones qui sauvegardent sur le même disque restent ainsi séparés. Une sauvegarde ne démarre pas tant qu'aucun nom n'est défini.", "Branchez votre disque.", "Sous <b>Destinations</b>, touchez <b>Choisir…</b> et sélectionnez le disque, ou un dossier du disque, dans le navigateur de fichiers du système. Sur Android, vous pouvez aussi choisir un dossier dans le stockage du téléphone.", "Le nom du disque apparaît dans les Réglages et dans l'onglet Sauvegarde, avec son espace libre. Vous ne le faites qu'une fois : l'application reconnaît le disque la fois suivante."]),
        ("fig", "settings_configured", "Réglages : nom de l'appareil et première destination."),
        ("note", "Une destination peut aussi être un dossier d'<b>iCloud Drive</b> (iPhone) — l'application libère la copie locale dès qu'iCloud confirme l'envoi, pour que le téléphone ne se remplisse pas."),
    ]),
    ("photos", "Sauvegarder vos photos et vidéos", [
        ("p", "Ouvrez l'onglet <b>Sauvegarde</b>. En haut, vous voyez vos destinations avec leur espace libre. Dans <b>Sources</b>, la ligne <b>Bibliothèque Photos</b> affiche le nom de votre appareil. Touchez son bouton <b>Sauvegarde</b>."),
        ("fig", "dashboard_ready", "L'onglet Sauvegarde : destination connectée, photothèque prête."),
        ("p", "L'application analyse la photothèque, puis copie. La <b>première sauvegarde est la plus longue</b> ; les suivantes ne copient que les nouveautés et sont bien plus rapides."),
        ("ul", ["Les photos stockées uniquement dans iCloud / Google Photos sont d'abord téléchargées — cela demande une connexion et un peu de temps.", "L'application copie chaque fichier directement vers la destination : cela fonctionne même quand le téléphone est presque plein.", "Vous pouvez quitter l'application : une notification vous prévient à la fin de la sauvegarde."]),
    ]),
    ("sd", "Sauvegarder une carte d'appareil photo (Pro)", [
        ("ol", ["Branchez le lecteur de cartes au téléphone et insérez la carte (utilisez un hub si le SSD doit rester branché aussi).", "Dans l'onglet Sauvegarde, touchez <b>Ajouter une source (carte SD, clé USB…)</b>, trouvez la carte dans le navigateur de fichiers et validez.", "Donnez un nom à la source — <i>Blackmagic</i>, <i>Voyage au Japon</i>… Le type d'appareil est reconnu automatiquement.", "Touchez <b>Sauvegarde</b> sur la ligne de la source."]),
        ("table", ["Appareil reconnu", "Ce qui est sauvegardé"], [
            ["DJI Mini 3 Pro", "Photos, vidéos, DNG et la télémétrie (.srt)"],
            ["DJI 360 / Action (Neo 2…)", "Vidéos, photos, DNG, audio et la télémétrie (.srt)"],
            ["Insta360 (X5…)", "Fichiers .insv, .insp et .lrv"],
            ["GoPro HERO", "Vidéos et photos ; les fichiers proxy (.lrv) et miniatures (.thm) sont ignorés"],
            ["Tout le reste", "Formats courants de photo, vidéo et RAW"],
        ]),
        ("note", "Une carte éjectée puis remise demande un appui sur <b>Reconnecter</b> : le système donne à l'application un nouvel accès à chaque montage de la carte. Le nom et le type de la source sont conservés."),
        ("p", "Pour retirer une source de la liste, utilisez le <b>–</b> rouge (iPhone) ou le bouton de suppression de la ligne (Android). Aucun fichier n'est supprimé."),
    ]),
    ("progress", "Pendant la sauvegarde", [
        ("p", "Un panneau <b>Sauvegarde en cours</b> apparaît dès que vous touchez Sauvegarde. D'abord <b>Préparation…</b> (connexion à vos destinations), puis <b>Analyse de la source…</b> avec un compteur de fichiers trouvés en direct — sur une grande photothèque cela peut prendre un moment, ce n'est pas bloqué."),
        ("fig", "progress_backup", "Sauvegarde en cours : pourcentage, fichiers faits, temps restant, fichier en cours."),
        ("table", ["Phase", "Ce que fait l'application"], [
            ["Analyse", "Compte les fichiers et détermine ceux à copier."],
            ["Copie", "Écrit le fichier vers la destination."],
            ["Vérification", "Relit la copie et la compare à l'original."],
            ["Ignorés", "Le fichier est déjà sauvegardé — rien à faire."],
        ]),
        ("note", "Ne débranchez ni le disque ni la carte pendant une sauvegarde. Si un disque disparaît malgré tout, les autres destinations continuent et la session est marquée <b>Partielle</b>."),
        ("p", "Un bouton <b>Arrêter</b> arrête proprement la sauvegarde à tout moment. Réglages → Sauvegarde propose aussi une limite <b>Fichiers max par session</b> : laissez vide pour illimité."),
    ]),
    ("done", "Quand la sauvegarde est terminée", [
        ("fig", "completion_banner", "Le bandeau de fin : copiés, ignorés, en échec, taille et durée."),
        ("table", ["Nombre", "Signification"], [
            ["Copiés", "Fichiers enregistrés pour la première fois sur la destination."],
            ["Ignorés", "Fichiers déjà présents — normal et sans risque."],
            ["Échoués", "Fichiers qui n'ont pas pu être copiés (rare)."],
        ]),
        ("p", "Un échec vient d'une carte abîmée, d'un disque plein, d'une connexion coupée, ou d'un seul fichier trop gros pour l'espace libre — seul ce fichier est signalé et le reste continue. Libérez de la place ou reconnectez, puis relancez la sauvegarde : les fichiers manquants sont repris."),
    ]),
    ("history", "Historique et rapports", [
        ("p", "L'onglet <b>Historique</b> liste chaque sauvegarde : source, destinations, structure de dossiers, nombre de fichiers, et une couleur — vert pour un succès, orange pour <b>Partielle</b>, rouge en cas d'échecs."),
        ("fig", "history_list", "Historique : une session terminée."),
        ("p", "<b>Partielle</b> signifie que la sauvegarde s'est arrêtée avant la fin, pour l'une de trois raisons que le rapport précise : vous avez touché <b>Arrêter</b>, la <b>limite de fichiers</b> a été atteinte, ou une <b>destination s'est déconnectée</b>. Reconnectez le disque et relancez — la sauvegarde reprend là où elle s'est arrêtée."),
        ("p", "Touchez une session pour son rapport : résumé, état SHA-256, et listes des fichiers copiés, ignorés et en échec — avec la raison de chaque échec. Avec deux destinations, le rapport montre chaque disque séparément."),
        ("fig", "report_summary", "Un rapport de session."),
        ("p", "<b>Supprimer les fichiers source…</b> libère de la place sur la carte ou dans la photothèque quand la sauvegarde vous satisfait. Il ne propose que les fichiers copiés <i>et</i> vérifiés, et vous devez saisir un code à quatre chiffres pour confirmer. Votre sauvegarde n'est pas touchée. Sur iPhone et Android, le système demande une confirmation de plus pour les photos."),
        ("fig", "report_delete_confirm", "La saisie du code confirme la suppression."),
        ("note", "<b>Effacer l'historique</b> ne supprime que les enregistrements de l'application. Vos fichiers restent où ils sont."),
    ]),
    ("browse", "Parcourir, voir et partager vos sauvegardes", [
        ("p", "L'onglet <b>Parcourir</b> montre ce qu'il y a sur vos disques, dans l'application : un dossier par appareil, puis vos dossiers par date, puis une grille de miniatures. Touchez une photo pour l'ouvrir en plein écran — balayez pour passer d'un fichier à l'autre, pincez pour zoomer — ou touchez une vidéo pour la lire. Le disque doit être branché."),
        ("fig", "browse_device_folders", "Parcourir : les dossiers d'appareils d'un disque."),
        ("fig", "browse_media_grid", "La grille de médias d'un jour."),
        ("p", "Pour envoyer des fichiers ailleurs : touchez <b>Sélectionner</b>, cochez les fichiers, puis <b>Partager</b> — AirDrop, messages, e-mail, une autre application."),
        ("fig", "android_viewer", "Android : la visionneuse plein écran."),
        ("p", "Sur un NAS, Parcourir liste les fichiers et ne télécharge chacun que lorsque vous l'ouvrez."),
    ]),
    ("naming", "Dossiers et noms de fichiers", [
        ("p", "Dans <b>Réglages → Sauvegarde</b>, <b>Structure des dossiers</b> définit l'organisation d'un dossier d'appareil : <i>Flat</i> (à plat), <i>By month</i> (par mois), <i>By date</i> (par date, par défaut) ou <i>By year / month</i> (année / mois). L'onglet Parcourir s'adapte à ce qui se trouve sur le disque."),
        ("p", "<b>Nommage des fichiers</b> donne à chaque fichier son nom définitif <b>au moment de sa première copie</b> — il n'est jamais enregistré sous son nom d'appareil puis renommé. Activez <b>Renommer les fichiers pendant la sauvegarde</b> et modifiez le modèle : touchez un jeton pour l'insérer, tout le reste est du texte littéral. Une ligne <b>Exemple</b> montre le résultat."),
        ("fig", "settings_file_naming", "Nommage des fichiers : modèle, jetons et exemple en direct."),
        ("table", ["Jeton", "Remplacé par"], [
            ["{YYYY} {MM} {DD}", "Année, mois, jour de la prise de vue"],
            ["{hh} {mm} {ss}", "Heure, minute, seconde de la prise de vue (heure locale)"],
            ["{device}", "Le nom du dossier de l'appareil, sans espaces"],
            ["{original}", "Le nom d'origine du fichier, sans son extension"],
        ]),
        ("ul", ["<b>Rien n'est jamais écrasé.</b> Si le nom est pris par un fichier différent, le nouveau reçoit un suffixe <code>-1</code>, <code>-2</code>… Incluez les secondes dans votre modèle pour que deux prises de vue simultanées gardent des noms différents.", "<b>Les doublons sont reconnus par ce nom.</b> Un fichier déjà sauvegardé est ignoré — même si vous l'avez retouché depuis — et un fichier différent portant le même nom est mis à part.", "<b>Les fichiers existants ne sont pas renommés.</b> Le profil s'applique aux fichiers copiés à partir de maintenant. Profil désactivé (par défaut), les fichiers gardent leur nom d'appareil."]),
        ("p", "Vous pouvez aussi ajouter des <b>extensions de fichiers supplémentaires</b> à copier avec les médias — par exemple les journaux GPS <code>gpx</code>."),
    ]),
    ("lut", "LUT Grade : donner son look aux rushs LOG (Pro)", [
        ("p", "Les images tournées en <b>LOG</b> (DJI D-Log M, GoPro Protune…) paraissent plates et grises tant qu'une <b>LUT</b> n'est pas appliquée. Dans Parcourir, associez une LUT à un dossier d'appareil pour prévisualiser et étalonner sans quitter l'application."),
        ("ol", ["Ouvrez un dossier d'appareil et, dans <b>LUT Grade</b>, touchez <b>Assigner un LUT…</b> puis <b>Importer un LUT (.cube)…</b>. Tout fichier <code>.cube</code> standard convient (DaVinci Resolve, Final Cut Pro, le fabricant de votre caméra).", "Touchez une vidéo de ce dossier : elle se lit avec la LUT appliquée en temps réel. Cet aperçu est <b>gratuit</b>.", "Pour créer des copies définitives (Pro), touchez <b>Sélectionner</b>, choisissez les vidéos, puis <b>Étalonner</b>. Chacune est réencodée en <b>H.265</b> avec la LUT intégrée, dans un dossier frère nommé <b>Appareil (Graded)</b>."]),
        ("fig", "browse_lut_picker", "Choix d'une LUT pour un dossier."),
        ("fig", "android_lut", "Android : la section LUT Grade d'un dossier d'appareil."),
        ("ul", ["L'étalonnage se fait vidéo par vidéo, jamais « tout » — un dossier mélange souvent des plans LOG et ordinaires, et une LUT LOG abîmerait ces derniers.", "Les fichiers déjà étalonnés sont ignorés : on peut relancer sans risque. Annulez à tout moment : les fichiers terminés sont conservés.", "L'étalonnage est exigeant : gardez l'application ouverte et le disque connecté. Le téléphone peut chauffer.", "Sur un NAS, les plans sont téléchargés, étalonnés sur le téléphone puis envoyés dans un dossier <b>Appareil (Graded)</b> du NAS — plus lent, et cela consomme des données."]),
    ]),
    ("mirror", "Deux destinations à la fois (Pro)", [
        ("p", "Dans les Réglages, ajoutez une seconde destination : chaque fichier est copié sur les deux en même temps — deux disques, ou un disque et un NAS. La sauvegarde ne dure pas deux fois plus longtemps. Si une destination tombe ou disparaît, <b>l'autre continue</b>, et le rapport indique ce qui manque à laquelle."),
        ("note", "Si un seul des deux disques est branché au démarrage, l'application copie quand même vers lui et marque la session comme incomplète pour l'autre."),
    ]),
    ("nas", "Sauvegarder vers un NAS en Wi-Fi (Pro)", [
        ("p", "À la place d'un disque — ou en plus —, vous pouvez sauvegarder directement vers un <b>NAS</b> (Synology, QNAP, TrueNAS, tout appareil parlant SMB) par le réseau. Pas de câble, pas de cloud, et chaque fichier est vérifié par SHA-256."),
        ("ol", ["Sur le NAS, activez le <b>partage de fichiers SMB</b> et donnez à un utilisateur un accès en lecture et écriture à un dossier partagé.", "Dans l'application : <b>Réglages → Destinations → NAS (SMB)</b>.", "Renseignez l'<b>hôte</b> (par ex. <code>192.168.1.20</code>), le <b>partage</b> (par ex. <code>photo</code>), un <b>dossier</b> facultatif, ainsi que votre <b>nom d'utilisateur</b> et votre <b>mot de passe</b>. Le mot de passe est conservé dans le Trousseau iOS ou le Keystore Android.", "Touchez <b>Tester la connexion</b> : un message vous indique que la connexion est établie et combien d'éléments ont été trouvés. Puis <b>Enregistrer</b>."]),
        ("p", "Le NAS apparaît maintenant dans l'onglet Sauvegarde avec son espace libre. Vous pouvez sauvegarder <b>hors de chez vous</b> si le NAS est joignable — le plus simple et sûr est un VPN comme <b>Tailscale</b> : installez-le sur le NAS et sur le téléphone, puis utilisez l'adresse <code>100.x.x.x</code> du NAS comme hôte."),
        ("note", "En données mobiles, un bandeau orange vous avertit que de grosses vidéos peuvent consommer beaucoup de données ; <b>Arrêter</b> interrompt la sauvegarde (elle est marquée Partielle)."),
    ]),
    ("android", "Android et iPhone : les différences", [
        ("p", "Les deux applications partagent le même moteur : même détection des doublons, même nommage, même vérification SHA-256, même index — une sauvegarde commencée sur l'une est reconnue par l'autre."),
        ("table", ["", "iPhone / iPad", "Android"], [
            ["Source bibliothèque", "Photothèque", "Galerie (photos et vidéos)"],
            ["Destination", "Dossier choisi dans Fichiers (SSD, iCloud Drive, SMB)", "Dossier choisi avec le sélecteur système (SSD, USB, stockage du téléphone), NAS"],
            ["Arrière-plan", "Environ 30 secondes, puis l'écran reste allumé pendant la sauvegarde", "Une notification au premier plan la maintient, avec un bouton Arrêter"],
            ["Pro", "Achat intégré (App Store)", "Achat unique (Google Play)"],
            ["Mac", "Fonctionne sur les Mac Apple silicon (« conçu pour iPad »)", "—"],
        ]),
        ("note", "Sur Android, une destination dans le stockage interne du téléphone est masquée de la galerie (un fichier <code>.nomedia</code>) pour que la sauvegarde ne soit pas sauvegardée à nouveau."),
        ("fig", "android_backup", "Android : l'onglet Sauvegarde."),
        ("fig", "android_settings", "Android : les Réglages."),
    ]),
    ("faq", "Questions fréquentes", [
        ("p", "<b>Va-t-elle copier deux fois le même fichier si je relance ?</b> Non. Chaque fichier reçoit un nom à la destination et la sauvegarde suivante le cherche sous ce nom. Si les enregistrements de l'application montrent qu'il vient du même original, il est ignoré — même retouché depuis. Seuls des fichiers réellement différents portant le même nom reçoivent un suffixe <code>-1</code>, <code>-2</code>…, et rien n'est jamais écrasé."),
        ("p", "<b>Où l'application garde-t-elle la mémoire de ce qu'elle a sauvegardé ?</b> Dans sa propre base de données, et dans un petit <b>fichier caché, <code>.pvb-index.json</code>, à la racine de chaque destination</b>. Cette copie voyage avec la sauvegarde : après une réinstallation, ou depuis un autre téléphone, l'application la lit et ne recopie pas. Vous pouvez la laisser tranquille ; si vous la supprimez, l'application la reconstruit."),
        ("p", "<b>Puis-je sauvegarder vers un NAS et un disque ensemble ?</b> Oui — chaque destination connectée reçoit la sauvegarde en même temps."),
        ("p", "<b>La connexion à mon NAS expire.</b> Le NAS n'est généralement pas joignable : vérifiez que vous êtes sur le même Wi-Fi (ou que le VPN est actif), que le partage SMB est activé et que le pare-feu du NAS autorise la connexion."),
        ("p", "<b>Puis-je utiliser deux téléphones avec le même disque ?</b> Oui. Donnez à chacun un nom de dossier différent dans les Réglages ; chacun crée son propre dossier sur le disque."),
        ("p", "<b>La barre indique 3 % et semble bloquée.</b> Les premiers fichiers sont souvent de grosses vidéos. Patientez quelques minutes."),
        ("p", "<b>Ma carte apparaît comme « Documents ».</b> Certains appareils utilisent un dossier générique. Saisissez un nom parlant quand vous ajoutez la source."),
        ("p", "<b>Puis-je sauvegarder quand mon téléphone est presque plein ?</b> Oui. Les fichiers sont envoyés en flux vers la destination : seuls quelques mégaoctets sont retenus à la fois. Seule une sauvegarde vers un NAS <i>seul</i> demande la place d'un fichier à la fois. Un fichier qui ne tient vraiment pas est signalé en échec et le reste continue."),
        ("p", "<b>Mes données sont-elles envoyées quelque part ?</b> Non. Tout se passe entre votre téléphone et votre disque ou NAS. L'application n'a ni serveur ni compte. Le seul trafic réseau va vers le NAS que vous configurez vous-même, et vers le téléchargement par le système de vos propres photos iCloud / Google."),
        ("p", "<b>Quelles langues ?</b> Anglais, français, allemand, espagnol, italien, portugais, chinois simplifié et russe. L'application suit la langue du téléphone ; vous pouvez en forcer une dans <b>Réglages → Langue</b>, sans redémarrage."),
    ]),
]

PRIVACY = {
    "title": "Politique de confidentialité — PhotoVideoBackup",
    "updated": "Dernière mise à jour : {date}",
    "summary": "PhotoVideoBackup ne collecte, ne stocke, ne transmet ni ne partage aucune donnée personnelle. Elle n'a ni compte, ni outil d'analyse, ni publicité, ni serveur propre.",
    "sections": [
        ("Ce à quoi l'application accède", [
            ("ul", ["Vos photos et vidéos — en <b>lecture seule</b>, pour les copier vers le disque, le dossier ou le NAS que vous choisissez. Sur Android, cela inclut la position enregistrée dans vos photos, afin que la copie soit identique à l'original.", "Les dossiers et cartes que vous choisissez avec le navigateur de fichiers du système.", "Les notifications, pour vous prévenir à la fin d'une sauvegarde."]),
        ]),
        ("Ce qui quitte votre appareil", [
            ("ul", ["<b>Rien ne nous parvient.</b> Vos fichiers ne sont écrits que vers les destinations que vous choisissez.", "Si vous configurez un NAS, l'application se connecte à <b>ce serveur</b>, à l'adresse que vous avez saisie, et nulle part ailleurs. Le mot de passe est conservé dans le Trousseau iOS ou le Keystore Android.", "iOS ou Android peut télécharger vos propres photos iCloud ou Google pour que l'application les lise ; c'est le système qui le fait, pour votre compte.", "Les achats sont gérés par Apple ou Google. Nous ne recevons aucune information de paiement."]),
        ]),
        ("Journal de diagnostic", [
            ("p", "L'application tient sur votre appareil un petit journal de diagnostic, sans contenu personnel. Il n'est envoyé que si vous choisissez de l'adresser au support par e-mail depuis l'application."),
        ]),
        ("Contact avec le support", [
            ("p", "Si vous écrivez au support, nous recevons ce que vous envoyez — votre adresse et votre message — et ne l'utilisons que pour vous répondre."),
        ]),
    ],
}
