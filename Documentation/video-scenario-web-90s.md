# PhotoVideoBackup — Scénario film web (16:9, ~90 s)

> **Destination :** page produit / web · **Ratio :** 16:9 (1920×1080) · **Durée cible :** 90 s
> **Voix off :** français · **Textes à l'écran :** anglais (UI de l'app) — variante FR entre crochets
> **Ton :** posé, rassurant, « aventure + tranquillité d'esprit ». Musique acoustique/ambient douce, montée légère à l'Acte 2.

---

## Principe d'animation « photo → vidéo »

Chaque image fixe (style Ghibli, comme les 5 photos jointes) est animée par un léger mouvement pour donner vie sans re-tourner :

- **Parallaxe / Ken Burns lent** : zoom avant ou latéral très doux (2–4 s par plan).
- **Micro-mouvements diégétiques** : nuages qui dérivent, eau qui scintille, hélices du drone qui tournent, reflets sur l'écran de l'appareil.
- **Technique** : image-to-video IA (Runway Gen-3 / Kling / Luma) sur chaque photo, prompt type *« subtle camera push-in, drifting clouds, shimmering water, gentle parallax, cinematic »*, puis montage.
- **Cohérence** : garder le même personnage (hoodie bleu, cheveux bruns) sur tous les plans capture → fil rouge visuel.

---

## ACTE 1 — Le problème du vidéaste (0:00 → 0:30)

*Objectif : montrer qu'on capture partout, avec plein d'appareils… et que tout ce contenu est fragile et éparpillé.*

| # | Time | Visuel (source + animation) | Texte écran (EN) [FR] | Voix off (FR) | Transition / SFX |
|---|------|------------------------------|------------------------|----------------|-------------------|
| 1 | 0:00–0:04 | **Photo 1 — smartphone** face au lac/montagnes. Push-in doux, nuages qui dérivent, scintillement de l'eau. | *(aucun texte — on installe l'ambiance)* | « Un voyage. Des paysages qu'on ne reverra peut-être jamais. » | Fondu depuis noir. Ambiance nature (vent, oiseaux). |
| 2 | 0:04–0:09 | **Photo 5 — reflex** viseur à l'œil, gros téléobjectif. Léger travelling latéral. | — | « Alors on filme. On photographie. » | Cut sec rythmé sur la musique. Déclencheur photo (clic). |
| 3 | 0:09–0:14 | **Photo 2 — drone DJI** en vol, hélices animées, radiocommande en main. | — | « Avec le drone… » | Whoosh + bourdonnement drone. |
| 4 | 0:14–0:18 | **Photo 3 — Insta360 X5** sur perche. Léger orbit. | — | « …la 360… » | Cut. |
| 5 | 0:18–0:22 | **Photo 4 — DJI Osmo Pocket** en main, écran allumé. | — | « …la caméra de poche. » | Cut. |
| 6 | 0:22–0:26 | **Montage split-screen 2×2** des 4 appareils qui s'accumulent. Chaque case = une carte SD / un stockage différent. Overlay d'icônes de cartes SD qui se remplissent en rouge. | **5 devices. 5 memory cards. 0 backups.** [5 appareils. 5 cartes. 0 sauvegarde.] | « Cinq appareils. Cinq cartes mémoire… » | Tension musicale monte. |
| 7 | 0:26–0:30 | **Écran iPhone** : pop-up iOS « Storage Almost Full ». Vibration. L'image se fige, désaturation légère. | **"iPhone Storage Almost Full"** + ⚠️ | « …et un iPhone déjà plein. Une seule carte perdue, et le voyage disparaît. » | Coupure musicale nette (beat de silence) → tension. |

---

## ACTE 2 — La solution : PhotoVideoBackup (0:30 → 1:15)

*Objectif : le geste simple (brancher), la couverture (tous les appareils), la garantie (SHA-256), le NAS/SSD, les plus Pro.*

| # | Time | Visuel (source + animation) | Texte écran (EN) [FR] | Voix off (FR) | Transition / SFX |
|---|------|------------------------------|------------------------|----------------|-------------------|
| 8 | 0:30–0:34 | **Logo/app** apparaît. Fond clair. Mockup iPhone avec un SSD USB-C qui se branche (animation du câble qui se connecte). | **PhotoVideoBackup** | « Il suffit de brancher. » | Reprise musicale (résolution, majeur). « Click » de connexion USB-C. |
| 9 | 0:34–0:40 | Capture `Documentation/images/appstore/01_settings_ssd_configured.png` — animée en slide-up dans le mockup. | **Plug in an SSD — or back up to your NAS.** [Un SSD, ou votre NAS] | « Un SSD portable… ou directement votre NAS, en Wi-Fi. » | Slide. |
| 10 | 0:40–0:47 | Capture `03_dashboard_multi_sources.png` / `07_dashboard_pro_sources.png` — les sources (iPhone, SD, Insta360, DJI, Blackmagic) apparaissent en liste, une par une, avec les icônes des appareils de l'Acte 1 qui « atterrissent » dans l'app. | **iPhone · SD cards · Insta360 · DJI · Blackmagic** | « Vos photos, vos rushes — de tous vos appareils, réunis au même endroit. » | Chaque source = petit « pop ». Rappel visuel des 5 appareils. |
| 11 | 0:47–0:54 | Capture `04_backup_in_progress.png` — barre de progression animée qui se remplit. Compteur de fichiers qui défile. | **Backing up…** [Sauvegarde…] | « La copie démarre. » | Léger « tick » par fichier. |
| 12 | 0:54–1:00 | Zoom sur un badge **SHA-256 ✓** qui se coche sur chaque fichier. Micro-animation d'empreinte/checkmark. | **Every file verified — SHA-256.** [Chaque fichier vérifié] | « Et chaque fichier est vérifié, octet par octet. Aucune copie corrompue, jamais. » | « Ding » de validation, rassurant. |
| 13 | 1:00–1:05 | Capture `05_backup_complete.png` + `completion_banner.png` — bannière verte de fin. | **Backup complete.** [Sauvegarde terminée] | « En quelques minutes, tout est en sécurité. » | Accord résolu. Soupir de soulagement visuel (couleurs qui reviennent). |
| 14 | 1:05–1:10 | **Bonus Pro** — montage rapide 3 captures : `browse_lut_picker.png` (LUT preview), mirror backup (2 SSD), `history_report.png`. Transitions vives. | **Pro: LUT grading · Mirror backup · History** | « Et pour aller plus loin : l'étalonnage LUT, la double sauvegarde miroir, l'historique complet. » | Rythme rapide, punchy. |

---

## ACTE 3 — Payoff & CTA (1:15 → 1:30)

*Objectif : boucler l'émotion (le vidéaste tranquille) + appel à l'action clair.*

| # | Time | Visuel | Texte écran (EN) [FR] | Voix off (FR) | Transition / SFX |
|---|------|--------|------------------------|----------------|-------------------|
| 15 | 1:15–1:22 | Retour **Photo 1** (le lac) mais apaisée, lumineuse. Le personnage range son matériel, serein. Léger push-out. | **Shoot everything. Lose nothing.** [Filmez tout. Ne perdez rien.] | « Filmez tout. Ne perdez rien. » | Musique s'ouvre, respiration. |
| 16 | 1:22–1:30 | Fond clair. Logo **PhotoVideoBackup** + badge **App Store** + accroche prix. | **Free to try · Pro $1.99 — one-time, no subscription** [Gratuit · Pro 1,99 $, paiement unique] | « PhotoVideoBackup. Gratuit à l'essai, sur l'App Store. » | Note finale, fondu au blanc. |

---

## Notes de production

- **Assets à préparer :** les 5 photos jointes → 5 clips animés (2–5 s chacun). Captures d'app listées ci-dessus (dispo dans `Documentation/images/appstore/` et `Documentation/images/`).
- **Mockups iPhone :** intégrer les captures dans un cadre iPhone 15 (USB-C) pour crédibiliser le geste « brancher ».
- **Rappel NAS :** la mémoire projet note que la cible NAS passe par SMB natif (AMSMB2). Le plan 9 doit montrer SSD **et** NAS pour couvrir les deux usages.
- **Si on doit tenir 90 s pile :** l'Acte 1 peut passer de 30 à 24 s (fusionner plans 4 et 5), et le bonus Pro (plan 14) est le premier candidat à raccourcir.
- **Sous-titres :** prévoir un burn-in optionnel des textes EN pour la lecture sans son.

---

## Points de valeur couverts (checklist)

- [x] Multi-appareils (iPhone, SD, Insta360, DJI, Blackmagic)
- [x] iPhone plein / peur de perdre les rushes
- [x] Brancher un SSD **ou** NAS (SMB)
- [x] Vérification SHA-256 (intégrité)
- [x] Indépendance vis-à-vis d'iCloud / du cloud
- [x] Pro : LUT grading, mirror backup, historique
- [x] Modèle Free / Pro 1,99 $ paiement unique
- [x] CTA App Store
