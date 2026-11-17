# Protocole de réalisation d'une app iOS + Android (de l'idée à la production)

Protocole entre Gérard et Claude, tiré de l'expérience PhotoVideoBackup (2.0 → 2.7, Android 2.6/2.7).
Chaque phase se termine par une **porte** (☐ à cocher). On ne passe pas à la phase suivante tant qu'une porte est ouverte. Claude relit ce fichier au début d'un nouveau projet et à chaque livraison, et annonce la phase en cours.

Légende : 🤖 Claude fait seul · 👤 Gérard seul (compte, argent, soumission, appareil réel) · 🤝 les deux.

---

## Phase 0 — Cadrage
🤝 Décider et écrire dans `CLAUDE.md` :
- Problème, public, cas d'usage réel de Gérard (ex. : voyage, SSD) ; ce que l'app ne fait **pas**.
- Plateformes : iOS d'abord ? Android ensuite ? **Règle de parité : x.y.z identique = mêmes fonctions sur les deux** (pas de version « d'alignement » vide).
- Modèle économique : gratuit / Pro (achat unique ?), ce qui est gratuit, ce qui est Pro, prix. Identifiant produit IAP identique des deux côtés.
- Langues cibles (par défaut les 13 : en fr de es it pt zh-Hans zh-Hant ru ja ko hi ar ; RTL pour ar). Anglais = langue source dans le code.
  - **Variantes à fixer dès le cadrage** : `pt` = portugais d'Europe (pt-PT) ou du Brésil (pt-BR) ? `es` = neutre (Espagne + Amérique latine) ? Les fiches des stores suivent (`pt-PT`/`pt-BR`, `es-ES`/`es-MX`). Sur PhotoVideoBackup : `pt` = pt-PT, `es` = neutre ; le Brésil n'a pas de variante propre (candidat prioritaire).
  - **Chinois traditionnel (Taïwan)** : dérivé du simplifié par `hant_convert.py` + `regen_hant.py` (jamais traduit à la main) ; à faire relire.
  - **Ajouter une langue** : seulement d'après les statistiques de territoires (App Store Connect → Analytics), par vagues, avec relecture par un natif.
- Données touchées / réseau → conséquence sur la politique de confidentialité.
- Appareils minimum (iOS min, Android `minSdk`), cas Mac « Designed for iPad » oui/non.

☐ Porte : spec courte (`Documentation/<Feature>-x.y.z.md`) validée par Gérard.

## Phase 1 — Fondations du dépôt (avant la première fonction)
🤖
- Dépôt git, `.gitignore` (secrets, keystore, `nas-test-config.json`…), branche `main` + branches `release/x.y.z`.
- `CLAUDE.md` : règles de langue, versioning, architecture, pièges connus (à enrichir en continu).
- Localisation dès le premier écran : `Localizable.xcstrings` + `InfoPlist.xcstrings` (iOS), `gen_android_strings.py` (Android, strings **générées**, jamais éditées à la main).
- Page Réglages standard (Pro, Langue, À propos, Support) et chaîne de support IA : voir sections dédiées. Journal de diagnostic (`DiagnosticLog`, chaîne `[LAUNCH]→[STORE_OK]→[UI_READY]→[STARTUP_OK]`) et mail de support structuré `[Support:<App>]` + bloc `SUPPORT-META`.
- Cible de tests + `Makefile` (`test-all`, `build-test`) ; logique risquée = **fonctions pures testables** (leçon dédup/NAS).
- Squelette de doc **versionné** (voir « Documentation multi-versions ») : `Documentation/site/<lang>.py` + `build_site.py` + `check_docs.py` + `images/manifest.json`, `.nojekyll`, GitHub Pages depuis `main`.
- Dossier `support/` (`knowledge.md`, `agent.json`).
- Mémoire Claude : `MEMORY.md` + notes projet.

☐ Porte : le projet compile, un test vide passe, une chaîne traduite apparaît dans les langues.

## Phase 2 — Développement d'une fonction (boucle répétée)
Pour **chaque** fonction :
1. 🤖 Spec courte → implémentation (architecture `@Observable`, pas de Combine ; core Kotlin pur côté Android).
2. 🤖 Chaînes en anglais dans le code + **toutes** les traductions (jamais une vue sans ses 11 traductions) ; règles LanguageManager respectées (`Text(LocalizedStringKey)`, dates/octets avec la locale de l'app).
3. 🤖 Tests : scénario avec commentaire `SCENARIO:` obligatoire ; si une décision change côté Swift, la changer côté Kotlin et réciproquement.
4. 🤖 Gating Pro appliqué **à l'exécution**, pas seulement dans l'UI.
5. 🤖 Journal : tags de diagnostic pour les nouveaux chemins d'erreur.
6. 🤖 Mise à jour immédiate de `CLAUDE.md` (décisions, pièges, « pourquoi ») — pas en fin de projet.
7. 🤝 Test sur appareil réel pour ce que les tests ne couvrent pas (PhotoKit, SAF, bookmarks, NAS réel, iCloud, USB-C). Claude liste explicitement ce qui n'est **pas** validé.

☐ Porte par fonction : build OK, tests verts, 13 langues, `CLAUDE.md` à jour, liste « non validé sur appareil » écrite.

**Ne jamais** incrémenter la version pendant le développement.

## Phase 3 — Parité iOS ↔ Android
🤖 Avant toute livraison : tableau des fonctions iOS vs Android. Écart = soit on le comble, soit la version reste en test. Les formats d'échange (ex. `.pvb-index.json`) doivent rester compatibles octet à octet ; ajouter un test.

☐ Porte : tableau de parité sans écart non assumé.

## Phase 4 — Documentation, légal, support (avant toute build de test publique)
- 🤖 Guide utilisateur : `en.py` en référence puis les 11 autres ; `build_site.py` doit passer (structure identique). Instantané `v/<major.minor>/` de la version en cours créé/régénéré.
- 🤖 Politique de confidentialité (`PRIVACY`) à jour si données/réseau nouveaux.
- 🤖 `images/manifest.json` : une entrée par capture avec `version` ; `check_docs.py` sans STALE bloquant.
- 🤝 Captures : iPhone par simulateur (1206×2622, anglais, 9:41, noms d'exemple) = 🤖 ; appareil réel / émulateur Android = 🤝. Claude indique **exactement** ce que la capture doit montrer.
- 🤖 `support/knowledge.md` : nouvelle fonction, limites, problèmes connus, version.
- 🤖 Notes de version (App Store 13 langues ; Play 8+ locales ; limites de caractères vérifiées).
- 🤖 Traductions des nouvelles langues : signaler « non relues par un natif ».

☐ Porte : site généré (racine + instantané de la version) et commité, politique de confidentialité en ligne, notes de version prêtes.

## Phase 5 — Release de TEST
### iOS — TestFlight
1. 🤝 Gérard dit « prépare la build de test » (c'est le signal ; sinon pas de bump).
2. 🤖 Bump `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` (Debug **et** Release), ligne dans le changelog de `CLAUDE.md`, `UI["version_line"]`.
3. 🤖 `make test-all` vert ; archive Release.
4. 🤝 Upload App Store Connect (acte irréversible → confirmation explicite).
5. 🤝 **Attacher gduvalsc@gmail.com à la build** (sans testeur rien ne bouge) ; autres testeurs (ex. Andreas) seulement sur demande. L'upload n'est pas terminé tant que ce n'est pas attaché.
6. 🤝 Gérard teste ; Claude lit le journal de diagnostic remonté et corrige (build suivante = build +1).

### Android — test fermé Google Play
1. 🤖 Bump `versionName` (le `versionCode` en découle), `gradle :core:test`, `:app:assembleQa` (smoke test sous R8), `:app:bundleRelease` signé → `android/dist/`.
2. 👤 Console Play : app, produit IAP, piste Alpha/fermée, groupe de testeurs (compte personnel : 12 testeurs × 14 jours), questionnaires (Data safety, contenu, public cible), URL de confidentialité.
3. 🤝 Envoi du AAB, lien d'inscription aux testeurs.
4. 🤝 Sauvegarde du keystore **hors dépôt** (sa perte = plus de mises à jour).

☐ Porte test : build installée par au moins Gérard, parcours principal + achat Pro (sandbox) + restauration validés, aucun crash dans le journal, retours traités.

## Phase 6 — Release de PRODUCTION
Déclenchée **uniquement** par un signal explicite de Gérard (« passe en production »).
1. 🤖 Revue finale : parité, changelog, `check_docs.py --strict` (aucune capture STALE), `support/knowledge.md`, `latest_version` dans `support/agent.json`.
2. 🤖 `release/x.y.z` fusionnée dans `main` **seulement quand iOS et Android sont prêts ensemble**.
3. 👤/🤝 Fiches stores : descriptions, mots-clés, captures (6.9" iPhone ; tailles Play), notes de version dans toutes les langues, prix, catégories, âge, confidentialité (App Privacy / Data safety), compte de test si nécessaire.
4. 👤 Soumission à la revue (iOS : sortie **manuelle** après approbation ; Android : déploiement progressif possible).
5. 🤖 Pendant l'attente : rien d'autre ne modifie la build soumise ; préparer les réponses aux rejets probables.
6. 👤 Clic de mise en ligne après approbation.
7. 🤖 Tags : `git tag release-ios-x.y.z` / `release-android-x.y.z` + `git push origin <tag>` **après** la mise en ligne (l'agent de support lit le dernier tag `release-*`). Ne pas créer ces tags tant que la version n'est pas publique.
8. 🤖 Mise à jour de la mémoire projet (état de release, points ouverts).

☐ Porte : app visible sur les deux stores, tags poussés, site documentaire publié, agent de support à jour.

## Phase 7 — Après la mise en ligne
- 🤖 Surveiller les mails de support (sujet `[Support:<App>]`), lire `envSnapshot()` (langue, mémoire, disque) pour répondre dans la langue de l'utilisateur.
- 🤖 Chaque bug → test de non-régression **qui échoue sans le correctif**, puis ligne de changelog (correctif = patch).
- 🤝 Faire relire les traductions par des natifs ; retours stores (avis, crashes Play Vitals / Xcode Organizer).
- 🤖 Rétrospective : ce qui a été oublié → ajouté à ce protocole.

---

## Page Réglages — sections « À propos » et « Support » (standard de toute app)
Chaque app a, en bas de ses Réglages, les mêmes blocs (iOS : `SettingsView` ; Android : `SettingsScreen`), tous localisés dans les 13 langues :
1. **Pro** (si l'app a un palier Pro) : statut, *Passer à Pro*, *Restaurer les achats*. Obligatoire pour les stores.
2. **Langue** : sélecteur dans l'app (« Système » par défaut) + prise en charge RTL.
3. **À propos** : nom, **version et numéro de build** (c'est ce que l'utilisateur nous donne en premier), accès à l'écran de bienvenue.
4. **Support** :
   - **Documentation** → guide de **la version de la build** (`v/<major.minor>/`, voir ci-dessous), jamais une URL racine en dur ;
   - **Contacter le support** → mail pré-rempli, sujet routable `[Support:<NomApp>]` et bloc `SUPPORT-META` (app, version, build, appareil, OS, langue du téléphone et de l'app) ;
   - adresse de support affichée (constante unique `AppConstants.supportEmail`, jamais en dur ailleurs) ;
   - **Journal de diagnostic** : consultable et envoyable par le même circuit (même sujet et même bloc méta) ; supprimable par l'utilisateur.
5. Les liens légaux exigés par les stores (politique de confidentialité, conditions si besoin) restent joignables depuis l'app.

### Chaîne de support assistée par IA (à mettre en place avec l'app, pas après)
- **Entrée** : le mail de l'utilisateur arrive dans la boîte de support avec le sujet `[Support:<NomApp>]` et le bloc `SUPPORT-META`.
- **Préparation automatique** : l'agent de support (hors dépôt iOS, sur le VPS, multi-apps) détecte l'app, lit la version et la langue, puis **rédige un brouillon de réponse dans la langue de l'utilisateur**, en s'appuyant sur le guide, `support/knowledge.md` et le journal joint. Il escalade sans répondre sur : remboursements/facturation, comptes Apple/Google, questions de revue des stores (`escalate` de `agent.json`).
- **Validation humaine** : le brouillon est relu par Gérard avant envoi ; l'IA ne répond pas seule à l'utilisateur. L'app ne doit jamais promettre une réponse instantanée ou « de l'IA » : elle dit simplement « Contacter le support ».
- **Connaissance versionnée** : l'agent lit `support/agent.json`, `support/knowledge.md` et la doc **au dernier tag `release-*`** ; c'est pourquoi les tags ne sont posés qu'après la mise en ligne (phase 6). Chaque fonction/limite/problème connu entre dans `knowledge.md` avec sa version (phase 2, étape 6 ; phase 4).
- **Confidentialité** : la politique de confidentialité dit que le contenu du mail de support (et du journal joint) est traité pour préparer la réponse, y compris par un service d'IA ; à vérifier dans `PRIVACY` à chaque évolution de l'agent.
- **Mise en place pour une nouvelle app** : entrée dans l'agent (nom, plateformes, `latest_version`, signature, `docs`, `escalate`, `never_say`), `support/` dans le dépôt, test de bout en bout avec un mail réel envoyé depuis l'app avant la première build de test publique.

☐ Porte (phase 5, avant la build de test) : les 5 blocs sont présents sur iOS et Android ; un mail envoyé depuis chaque app produit un brouillon correct dans la bonne langue ; le lien Documentation ouvre la bonne version.

## Documentation multi-versions (exigence)
Plusieurs versions du guide sont **en ligne en parallèle** ; chaque build ouvre le guide de **sa** version (une app encore installée en 2.6 ne doit pas renvoyer vers une doc 2.7).
- **Clé = `major.minor`** de l'app (un patch ne change pas la doc ; c'est aussi la granularité de `check_docs.py`). iOS et Android partagent le même numéro, donc la même doc.
- **Disposition** : la racine du site = la **dernière** version publique (URL stable pour les stores et les liens existants) ; chaque version a un instantané `v/<major.minor>/<lang>/…` avec **ses propres captures et assets** (chemins relatifs inchangés, rien ne pointe vers la racine).
- **Cycle de vie** : instantané créé au **premier build de test** de la version (sinon le lien de la build TestFlight/Play serait mort) et **régénéré** à chaque build de test ; **figé** (jamais réécrit) à la mise en production. Les instantanés figés ne sont jamais régénérés par `build_site.py`.
- **Lien dans l'app** : construit depuis la version de la build (`…/v/<major.minor>/<lang>/`), via une constante unique (`AppConstants.documentationURL` iOS, équivalent Android) ; jamais une URL racine en dur. Le snapshot doit exister avant la build : `check_docs.py` échoue sinon.
- **Outillage** : `build_site.py` (un build normal régénère le snapshot de la version courante tant qu'il n'est pas figé ; `--snapshot X.Y [--freeze]` pour une autre version ou pour figer ; marqueur `v/X.Y/.frozen`) ; `check_docs.py` vérifie que l'instantané de la version courante existe et que ses images sont présentes ; un `versions.html` à la racine liste les versions disponibles.
- **Politique de confidentialité** : une seule version à jour à la racine (URL stable exigée par les stores) ; chaque instantané garde en plus la sienne pour l'historique.
- **Poids** : conserver les N dernières versions majeures/mineures encore installées, élaguer les plus anciennes sur décision de Gérard.

## Règles transverses (rappel)
- Actions irréversibles ou externes (upload, soumission, suppression distante/données, envoi de mail, push de tag) : **confirmation explicite de Gérard**, toujours.
- Claude fait le maximum seul ; il signale ce qu'il ne peut pas faire (appareil réel, comptes, prix, soumission).
- Jamais de secret en clair (keystore, mots de passe NAS, tokens) dans le dépôt, les logs ou les chats.
- Rien n'est « validé » sans l'avoir vu tourner ; ce qui ne l'est pas est écrit comme tel.
- Une fonction n'est pas finie tant que : 13 langues, tests, doc, `CLAUDE.md`, `support/knowledge.md` ne sont pas à jour.
- Pas de bump de version, pas de merge sur `main`, pas de tag de release hors signal explicite.

## Check-list éclair « rien oublié » avant chaque livraison
☐ Parité iOS/Android · ☐ Tests verts (core + app) · ☐ 13 langues + InfoPlist · ☐ Gating Pro à l'exécution · ☐ Version + build (Debug & Release) · ☐ Changelog · ☐ Réglages (À propos/Support) + agent de support testés de bout en bout · ☐ Guide 12 langues généré · ☐ Instantané `v/x.y/` (régénéré en test, figé en production) et lien in-app sur la bonne version · ☐ Politique de confidentialité · ☐ Captures + manifest · ☐ `support/knowledge.md` + `agent.json` · ☐ Notes de version stores · ☐ Testeur attaché (TestFlight) · ☐ Keystore sauvegardé · ☐ Soumission (👤) · ☐ Tags après mise en ligne · ☐ Mémoire mise à jour
