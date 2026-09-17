# Tranche 2 — Plan d'implémentation

Complète `TRANCHE-2.md` (la spec). Référence des sessions « Implémente
l'étape N du plan de la tranche 2 ». Établi le 15/09/2026 après vérification
des API dans la documentation Apple (Xcode 26.6, SDK iOS 26.5, cible iOS 18)
et validé par Jinkuro.

## A. API vérifiées dans la documentation Apple (15/09/2026)

- `RealityView(make:update:placeholder:)` — iOS 18. `make` est `async` (chargement sans figer l'UI).
- `RealityViewCameraContent` — iOS 18 : `camera`, `cameraTarget` (cible de l'orbite), `entities`.
  Conforme à `RealityCoordinateSpaceProjecting` : `ray(through:in:to:) -> (origin:, direction:)?`,
  `hitTest(point:in:query:mask:)`, `entity(at:in:)`, `project`, `unproject` — iOS 18.
- `.realityViewCameraControls(_:)` — iOS 18 : `.orbit`, `.pan`, `.tilt`, `.dolly`.
- `Entity(contentsOf:withName:) async throws` — iOS 18, USD/USDZ.
- `SpatialTapGesture.Value.location` et `.location3D` — iOS 16 ; `.targetedToAnyEntity()` — iOS 18.
- `ShapeResource.generateStaticMesh(from:) async throws` — iOS 18 (repli seulement).
- `.accessibilityDirectTouch(_:options:)` — iOS 17 (`.requiresActivation` pour VoiceOver).
- SwiftData `ModelConfiguration` : **aucune option de protection de fichiers ni d'exclusion de
  sauvegarde** dans l'API → pèse dans la décision E1.
- SceneKit : **déprécié (soft) depuis iOS 26** (WWDC25) → écarté.
- `QLThumbnailGenerator` — iOS 13, support USDZ non documenté → vignettes hors périmètre.

### Incertitudes et mitigations

| # | Incertitude | Mitigation |
|---|-------------|------------|
| 1 | Obtenir un rayon depuis un toucher : `ray(through:in:to:)` n'est accessible que via `content` (dans `make`/`update`), pas dans le geste. | Essai en début d'étape 2 : le geste mémorise le point 2D, `update` calcule le rayon. Repli : `targetedToAnyEntity()` + `location3D` sur une collision `generateStaticMesh`. |
| 2 | Même repère entre l'entité chargée par RealityKit et `MeshLoader` (Model I/O ignore `metersPerUnit`/`upAxis`, RealityKit peut les appliquer). | Racine du modèle laissée à l'identité ; test terrain : distance entre deux coins ≈ cotes de la boîte englobante. |
| 3 | `realityViewCameraControls(.orbit)` exige-t-il une caméra virtuelle et une `cameraTarget` ? | Essai d'étape 2 ; `cameraTarget` = entité au centre de la boîte englobante. |
| 4 | Temps d'intersection rayon / 50 k triangles en force brute. | Test de performance dans `Scan3DCore` (objectif < 20 ms) ; structure accélératrice seulement si nécessaire. |
| 5 | Cause de l'écart de hauteur (fond bouché trop bas ? dessus bombé ?). | Étape 4 : diagnostic chiffré avec l'outil de mesure avant toute correction. |
| 6 | `scan.json` venu d'ailleurs (tranche 4) ou d'une ancienne version. | Champ `schemaVersion`, décodage validé, taille maximale. |

---

## B. Décisions validées par Jinkuro (15/09/2026)

| Décision | Choix | Conséquence |
|----------|-------|-------------|
| E1 Stockage de la bibliothèque | **`scan.json` dans chaque dossier `Scans/<UUID>/`** (pas SwiftData) | Supprimer le dossier = supprimer le scan ; protection `.complete` héritée (D2) ; testable dans `Scan3DCore` ; dossier = unité de transfert vers le Mac. `CLAUDE.md` (stack) à mettre à jour. |
| E2 Portée du calibrage | **Par scan** | Facteur stocké dans `scan.json`, appliqué aux cotes, mesures et export du scan ; annulable. |
| E3 Visionneuse et mesure | **`RealityView` + intersection calculée dans `Scan3DCore`** | Modèle texturé affiché ; point touché calculé sur le même `Mesh` que cotes, calibrage et export ; testable sur Mac. |
| E4 Hauteur | **Diagnostic d'abord**, plan de coupe seulement si mesuré | Étape 4 conditionnelle. |

---

## C. Étapes

Convention inchangée : « Core » = `Packages/Scan3DCore/Sources/Scan3DCore/`, « App » = `Scan3D/`.
Chaque étape : `make test-core` + `make build-check` (+ build simulateur), explication fichier par
fichier, revue sécurité / accessibilité, scénario iPhone, commit local ; push après le test de
Jinkuro.

### Étape 0 — Spec, plan et vérifications en attente ✅ (15/09/2026 ; tests iPhone de la tranche 1 à faire par Jinkuro)

- `docs/TRANCHE-2.md` — spec au format de `TRANCHE-1.md` : parcours (bibliothèque → détail →
  visionneuse / mesure → calibrage → export), principes UX, spec technique, sécurité, accessibilité,
  scénario de test, protocole des 3 objets.
- `docs/TRANCHE-2-PLAN.md` — sections A à D de ce plan.
- `docs/MESURES-TRANCHE-2.md` — gabarit de campagne (tableau par objet : référence physique, boîte
  englobante, point à point, après calibrage).
- `CLAUDE.md` — stack : « bibliothèque en `scan.json` par dossier (tranche 2) » au lieu de SwiftData ;
  tranche en cours → `docs/TRANCHE-2.md`. `ROADMAP.md` — décisions E1-E4.
- Jinkuro : tests iPhone non rapportés de la tranche 1 (point ouvert 4 du bilan).

### Étape 1 — Bibliothèque des scans (et découpage de `ScanFlowModel`) — livrée le 15/09/2026, test iPhone en attente

Core (`Sources/Scan3DCore/Library/`) :
- `ScanRecord.swift` — `struct ScanRecord: Codable, Equatable, Sendable,
  Identifiable` : `id`, `name`, `createdAt` (arrondie à la seconde),
  `triangleCount`, `dimensions` (brutes), `calibration?`. `schemaVersion`
  n'est pas une propriété : écrit à 1, lu **avant** le reste (une version
  future a peut-être une autre structure). Décodage validé : nom 1-80
  caractères visibles après nettoyage (`sanitizedName` : contrôles et
  retours à la ligne → espaces fusionnés), triangles 1…2 M, date ISO 8601
  écrite par le type lui-même, cotes et calibrage revalidés. Erreurs
  `ScanRecordError` ; `rename(to:)` ; `defaultName(date:)` → « Scan du
  15/09/2026 à 14:32 » ; `recoveredName` → « Scan récupéré ».
- `ScanLibrary.swift` — `inspect(scansDirectory:)` classe chaque dossier :
  `complete`, `missingRecord`, `invalidRecord` (corrompu, trop gros,
  identifiant incohérent), `unreadableRecord` (lecture refusée → jamais
  réécrite), `newerRecord(version:)` (jamais touchée), `incomplete` (pas de
  modèle) ; `shouldPurge`, `shouldRemoveCaptureData` (photos restées à côté
  d'un modèle). Seuls les dossiers nommés par un UUID en majuscules sont
  considérés. `readRecord` lit au plus 64 Ko + 1 octet ; `write` atomique,
  protection `.complete` par défaut ; `sortedNewestFirst` (ordre stable à
  date égale).
- `ScanLayout` : `recordFile`, `Hashable` ; `Dimensions` et
  `ScaleCalibration` `Codable` (le calibrage stocke ses deux cotes, le
  facteur est recalculé et revalidé).
- Tests (`ScanLibraryTests.swift`, 2 suites, 22 tests) : aller-retour JSON,
  date à la seconde, format du fichier, fiche manuelle, 4 non-fiches,
  version future / nulle, 10 champs hors limites, nettoyage et longueur du
  nom (émoji), renommage, nom par défaut, fiche depuis un maillage ;
  classement de vrais dossiers temporaires, décisions de purge, dossier vide,
  entrées inconnues (dont UUID en minuscules), `Scans/` absent, écriture puis
  lecture, identifiant incohérent, fiche de 10 Mo, fiche absente, tri.

App :
- `Features/Bibliotheque/BibliothequeModel.swift` — liste et actions
  (`charger`, `renommer`, `supprimer`, erreurs `BibliothequeErreur`) ; détient
  l'unique `ScanStore`. **Premier inventaire de la session seulement** :
  purge des dossiers incomplets et retrait des photos restées (plus tard, un
  dossier sans modèle pourrait être un scan en cours). Scans sans fiche ou à
  fiche invalide → fiche recréée d'après le modèle (« Scan récupéré », date
  du jour : lire la date d'un fichier est une API à raison requise) ; modèle
  illisible → ligne « Scan illisible », supprimable.
- `Features/Bibliotheque/BibliothequeView.swift` — liste (nom, cotes, date,
  « Calibré »), glisser pour supprimer + confirmation, bouton « Nouveau
  scan » en bas ; vide → « Prêt à scanner ». `ScanRecord+Texte.swift` —
  dates en français, phrase VoiceOver.
- `Features/DetailScan/DetailScanModel.swift` (maillage, taille, export repris
  de `ScanFlowModel`) et `DetailScanView.swift` (ex-`ApercuView` : cotes lues
  dans la fiche, « Voir en 3D », « Exporter en STL », « Renommer » dans la
  barre, « Supprimer le scan » + confirmation ; « Terminer » disparaît au
  profit du retour).
- `Features/Accueil/AccueilView.swift` — `NavigationStack(path:)` sur
  `[ScanLayout]` ; à la fermeture du parcours : rechargement, puis ouverture
  du détail du nouveau scan.
- `Features/Scan/ScanFlowModel.swift` (312 lignes, contre 359) — s'arrête à
  `enregistrer()` : fiche (nom daté du début du scan) **puis** suppression
  des photos ; `ScanFlowView` affiche « Enregistrement du scan… » sans bouton
  Annuler et se ferme seul.
- `Features/Scan/ScanStore.swift` — `inventaire`, `purger`, `lireMaillage`,
  `creerFiche`, `ecrireFiche`.

Écarts au plan : le nom par défaut porte « à » (« Scan du 15/09/2026 à
14:32 ») ; `ScanLibrary.write` prend ses options d'écriture en paramètre
(macOS refuse la classe de protection dans `swift test`) ; les scans sans
fiche lisible restent listés (« Scan illisible ») pour pouvoir les supprimer.
Sécurité : `scan.json` = entrée non fiable (taille bornée, version, champs
validés, identifiant = dossier) ; le nom n'entre jamais dans un chemin ni
dans un journal ; purge des captures interrompues et des photos restées ;
suppression = dossier entier ; aucune nouvelle permission ni API à raison
requise.
Accessibilité : ligne lue en une phrase (nom, date longue, cotes en
centimètres, « calibré ») ; glisser pour supprimer exposé au rotor
VoiceOver, doublé d'un bouton dans le détail ; champ de renommage étiqueté,
longueur bornée pendant la frappe ; annonces « Scan enregistré dans la
bibliothèque », « Scan renommé », « Scan supprimé » ; Dynamic Type (textes
sur plusieurs lignes, pas de largeur fixe).

Test iPhone :
1. Installer par-dessus la version de la tranche 1 → les anciens scans
   apparaissent, nommés « Scan récupéré », avec leurs cotes (dont la boîte
   189,2 × 163,0 × 56,8 mm) ; Console (`stockage`) : « récupéré
   (missingRecord) », « fiche écrite ».
2. Ouvrir un scan → cotes, « Voir en 3D », « Exporter en STL » fonctionnent
   comme en tranche 1.
3. « Renommer » → « Boîte carton » → titre et liste mis à jour ; tuer l'app,
   relancer → nom conservé. Essayer un nom vide → « Enregistrer » inactif
   (à défaut, message « Le nom doit contenir entre 1 et 80 caractères »).
4. Glisser un scan vers la gauche → « Supprimer » → confirmation → la ligne
   disparaît ; Console : « Scan … supprimé ». Idem depuis le détail
   (« Supprimer le scan ») → retour à la liste.
5. Nouveau scan complet → « Enregistrement du scan… » → le détail s'ouvre
   (« Scan du … ») ; retour → il est en tête ; Console : « fiche écrite »,
   « photos et checkpoint supprimés ».
6. Lancer un scan, capturer quelques secondes, **tuer l'app** (balayage dans
   le sélecteur d'apps), relancer → Console : « dossier incomplet purgé,
   photos comprises » ; aucun scan fantôme dans la liste.
7. VoiceOver : une ligne est lue en une phrase ; balayer vers le haut sur
   une ligne → action « Supprimer ». Plus grande taille de texte (Réglages →
   Accessibilité → Affichage et taille du texte) : liste et détail lisibles.

### Étape 2 — Visionneuse intégrée et mesure point à point — livrée le 16/09/2026, test iPhone en attente

**Écart au plan, assumé** : le plan passait par `ray(through:in:to:)` de RealityKit
(incertitude 1). Vérification dans le SDK : cette méthode existe bien sur
`RealityViewCameraContent` **et** sur `EntityTargetValue`, mais l'utiliser
imposait une forme de collision et un geste ciblé sur l'entité, et laissait la
caméra aux contrôles système (donc hors de portée des tests). Choix retenu :
**piloter la caméra nous-mêmes**. La même caméra sert au rendu (un
`PerspectiveCamera` RealityKit) et au calcul du rayon (`OrbitCamera` dans
`Scan3DCore`) ; tout le calcul se teste sur Mac. `.realityViewCameraControls`
n'est pas utilisé ; les gestes (tourner, zoomer) sont à nous.

Core (`Sources/Scan3DCore/Measure/`) :
- `Ray.swift` — demi-droite validée (`init?` refuse une direction nulle ou non
  finie), direction normalisée : les distances sont donc des mètres.
- `MeshPicking.swift` — `Mesh.firstIntersection(with:) -> MeshHit?`
  (Möller-Trumbore, **double face** car un scan a des triangles retournés et des
  trous ; garde le contact positif le plus proche ; lecture par pointeurs non
  vérifiés, les indices ayant déjà été validés par `Mesh.init`).
- `OrbitCamera.swift` — cible, azimut, élévation (bornée avant la verticale),
  distance (bornée) ; `init(framing:)` cadre une boîte englobante ;
  `ray(throughViewPoint:viewSize:)` et `project(_:viewSize:)`.
- `SegmentMeasurement.swift` — distance A-B en mètres et en millimètres, milieu.
- Tests (`MeasureTests.swift`, 4 suites, 22 tests) : rayon normalisé et refusé,
  face avant / à côté / vers l'arrière / depuis l'intérieur / parallèle /
  triangle dégénéré, pose de la caméra, cadrage vérifié en projetant les 8 coins,
  rayon central, ouverture verticale, aller-retour projection → rayon, bornes,
  valeurs non finies, 70,7 mm et 50 mm sur le cube, et une mesure **de bout en
  bout** (caméra → rayon → intersection → 50,0 mm).

App (`Features/Visionneuse/`) :
- `MesureModel.swift` — possède la scène RealityKit : modèle chargé par
  `Entity(contentsOf:)` puis **recalé** sur la boîte englobante du maillage,
  caméra, lumière solidaire de la caméra, marqueurs A (jaune) / B (bleu) et
  trait. Toucher → rayon → intersection → point posé ; troisième toucher =
  nouvelle mesure ; annonces VoiceOver ; distance journalisée.
- `VisionneuseView.swift` — `RealityView` sur fond dégradé, glisser pour
  tourner, pincer pour zoomer, toucher pour poser, boutons « Effacer les
  points » et « Recadrer », distance en grand dans le panneau du bas.
- `DetailScanView.swift` — bouton « Mesurer » (plein écran) au-dessus de
  « Voir en 3D » ; `Journal.swift` — catégorie `mesure`.

**Banc d'essai (16/09/2026, simulateur iPhone 17 Pro)** : l'app a été lancée
avec deux touchers automatiques à des coordonnées connues de la zone 3D, puis
une capture d'écran a été comparée à ces coordonnées.

| Incertitude du plan | Résultat |
|---|---|
| 1. Obtenir un rayon depuis un toucher | ✅ Les repères A et B tombent **exactement** sous les points touchés (35 % / 52 % et 68 % / 58 % de la zone 3D), sans forme de collision ni geste ciblé. |
| 2. Même repère RealityKit / Model I/O | ✅ Facteur journalisé **1,000000** sur un USD en mètres (le cas de la reconstruction) ; **100** sur un fichier déclaré en centimètres, où le recalage aligne l'affichage sur le maillage mesuré. |
| 3. Caméra virtuelle | ✅ RealityKit rend depuis notre `PerspectiveCamera` ajoutée à la scène (`content.camera = .virtual`), lumière comprise. |
| 4. Temps d'intersection | ✅ 6,8 ms pour 51 200 triangles, pire cas, **sans optimisation** (objectif : < 20 ms). |

Découverte annexe : un `.usda` **exporté par Model I/O** se charge (géométrie et
matériau lus, mesurable) mais **ne s'affiche pas** dans RealityKit ; un USD écrit
à la main ou produit par la reconstruction s'affiche normalement. Noté dans
`CLAUDE.md` — à se rappeler si l'on écrit des fichiers 3D en tranche 3.

Sécurité : aucune donnée nouvelle, aucune permission, aucun accès à la caméra de
l'iPhone (rendu virtuel) ; le modèle affiché est celui déjà validé par
`MeshLoader` ; seule la distance mesurée est journalisée (ce n'est pas une donnée
personnelle).
Accessibilité : `accessibilityDirectTouch(options: .requiresActivation)` sur la
zone 3D (VoiceOver garde ses gestes tant que l'utilisateur n'a pas activé la
zone), annonces « Point A posé », « Point B posé. Distance : … », « Aucun point
du modèle à cet endroit », « Vue recadrée » ; distance toujours écrite en toutes
lettres dans le panneau. Limite assumée : viser un point précis reste un geste
visuel.

Test iPhone :
1. Un scan → « Mesurer » : le modèle apparaît entier, de trois quarts, sur fond
   gris. Console (`reconstruction`) : « échelle RealityKit / maillage = 1.0 »
   (toute autre valeur est à me signaler).
2. Glisser pour tourner, pincer pour zoomer, « Recadrer » pour revenir.
3. Toucher les deux coins d'une grande arête du dessus de la boîte : comparer à
   la règle (184 mm) et à la boîte englobante (189,2 mm). Console (`mesure`) :
   « Mesure A-B : … mm ».
4. Mesurer la **hauteur en 3 endroits** (bord, milieu, autre bord) : ce sont les
   chiffres du diagnostic de l'étape 4.
5. Toucher à côté de l'objet : rien ne se pose.
6. VoiceOver : la zone 3D demande une activation (double toucher) ; vérifier les
   annonces à chaque point.
7. Plus grande taille de texte : le panneau du bas reste lisible.

**Résultats (16/09/2026, boîte en carton de la tranche 1, sans retournement)** :
mesure point à point de la grande arête **177,9 mm** (règle 184), hauteur en
3 points **46,0 / 46,9 / 45,0 mm** (règle 50). Les deux méthodes encadrent la
vérité et l'écart est **additif** (−6,1 mm sur 184, −4,0 mm sur 50), ce qui
confirme qu'un facteur d'échelle seul ne suffira pas. Détail et analyse :
`MESURES-TRANCHE-2.md`. Reste à faire : scan **avec** passe « Retourner »
(diagnostic de l'étape 4), VoiceOver et grande taille de texte.

### Étape 3 — Calibrage par scan — livrée le 17/09/2026, test iPhone en attente

Core :
- `MillimeterInput.swift` — analyse stricte d'une cote saisie : virgule ou
  point, espaces (même insécables) retirés, un seul séparateur, chiffres ASCII
  seulement, plage 0,1 à 10 000 mm. Refuse « 1e3 », « -3 », « 0 », « 184,0,0 »,
  « 18,4mm », « ½ », « ٧ ».
- `CalibrationReference.swift` — les deux cotes de la carte bancaire (85,60 et
  53,98 mm), avec leurs libellés.
- `Dimensions.scaled(by:)` ; `ScanRecord.calibratedDimensions` (les cotes
  **brutes** restent dans la fiche : le calibrage s'annule sans rien perdre) ;
  `SegmentMeasurement.lengthMM(calibratedBy:)` ;
  `STLWriter.binaryData(for:scale:)` avec `STLError.invalidScale`.
- Tests (7 saisies valides, 12 refusées, cotes et mesures calibrées,
  références, STL du cube 50 mm × 1,02 → 51,0 mm, facteur invalide refusé) :
  **99 tests, 20 suites**.

App :
- `Features/Calibrage/CalibrageView.swift` — feuille ouverte depuis la mesure :
  cote saisie (`.decimalPad`) ou carte bancaire, aperçu (facteur, cotes barrées
  puis corrigées), « Appliquer » inactif tant que la saisie ne donne rien de
  valable, « Réinitialiser le calibrage » quand le scan en a un, et un rappel
  honnête : le calibrage corrige une **échelle**, pas des arêtes arrondies.
- `VisionneuseView` — bouton « Calibrer avec cette mesure » ; la distance
  affichée et annoncée est la cote calibrée (la brute reste au journal).
- `DetailScanView` — cotes calibrées, ligne « Calibré sur 177,9 → 184,0 mm »,
  réinitialisation, et export STL **à l'échelle** du calibrage.
- `BibliothequeModel.calibrer(_:_:)`, avec l'écriture de fiche factorisée avec
  le renommage ; le badge « Calibré » existait depuis l'étape 1.

**Ce que le calibrage corrige, et ce qu'il ne corrige pas** (mesuré le
16/09/2026) : calibrer sur une mesure point à point (177,9 → 184) rend justes
les **mesures point à point**, mais porte la boîte englobante de 189,2 à
195,7 mm, alors que la règle dit 184. L'inverse est vrai si l'on calibre sur la
boîte englobante. Aucun facteur unique ne peut corriger les deux, puisque
l'erreur est additive : **calibrer sur ce que l'on va utiliser**, c'est-à-dire
sur une mesure point à point quand on dessine une pièce ajustée.

Sécurité : la cote saisie passe par `MillimeterInput` puis par
`ScaleCalibration` (±20 %) ; aucun facteur nul, négatif ou non fini ne peut
exister ; l'export refuse une échelle invalide ; le calibrage enregistré dans
`scan.json` est revalidé au décodage (étape 1).
Accessibilité : champ étiqueté « Cote réelle en millimètres », aperçu lu en une
phrase, messages d'erreur explicites, annonces « Calibrage appliqué » et
« Calibrage réinitialisé ».
Vérification visuelle (simulateur, 17/09/2026) : écran de calibrage avec la
carte bancaire — facteur 1,019, 189,2 × 163,0 × 56,8 → 192,8 × 166,1 × 57,9 mm.

Test iPhone :
1. Mesurer la grande arête de la boîte → « Calibrer avec cette mesure » →
   saisir 184 → l'aperçu annonce un facteur ≈ 1,034 et des cotes ≈ 195,7 ×
   168,6 × 58,7 mm → Appliquer.
2. Détail : les cotes affichées sont les nouvelles, la ligne « Calibré sur
   177,9 → 184,0 mm » apparaît, la bibliothèque affiche « Calibré ».
3. Remesurer la même arête : elle doit tomber sur 184,0 mm.
4. Exporter en STL → dans Bambu Studio, la pièce mesure ce que l'app affiche.
5. « Réinitialiser le calibrage » → retour aux cotes brutes ; tuer l'app et la
   relancer → l'état est conservé dans les deux cas.
6. Saisies refusées : « abc », « -3 », « 12000 » laissent « Appliquer »
   inactif ; « 260 » (écart > 20 %) affiche le message d'écart.
7. VoiceOver sur l'écran de calibrage, puis plus grande taille de texte.

### Étape 4 — Hauteur : diagnostic fait le 16/09/2026 → **pas de plan de coupe**

Diagnostic (Jinkuro, boîte en carton, outil de mesure de l'étape 2) :

| Modèle | Hauteur point à point | Boîte englobante | Règle |
|--------|----------------------|------------------|-------|
| Sans passe « Retourner » | 46,0 mm (46,0 / 46,9 / 45,0) | 56,8 mm | 50 mm |
| Avec passe « Retourner » | **≈ 50 mm** aux 3 points | polluée par des artefacts | 50 mm |

**Décision : aucun plan de coupe.** L'écart de hauteur ne venait pas d'un défaut
que le code devrait rattraper, mais d'une **face jamais photographiée** que
l'algorithme comblait. Dès que le dessous est capté, la hauteur tombe juste. Un
`Mesh.clipped(belowHeightMeters:)` aurait masqué le symptôme en rabotant un fond
inventé, sans rien apprendre à l'utilisateur.

Ce qui est livré à la place (16/09/2026) :
- `Features/Scan/PreparationView.swift` — quatrième point dans la checklist :
  « Prévoir de retourner l'objet », avec le pourquoi (le dessous n'est jamais
  photographié) et la condition (coller des repères sur un objet uni).
- `Features/Capture/FinDePasseView.swift` — le texte explique l'ordre des
  passes : celles « à une autre hauteur » ne déplacent pas l'objet et sont sans
  risque, le retournement capte le dessous mais demande des repères.

Limite constatée, à garder en tête pour la tranche 3 : sur un carton uni, la
passe retournée s'est recollée avec un décalage et a laissé des **voiles plats
le long des arêtes**, qui faussent la boîte englobante (pas les mesures point à
point sur zones propres). Les repères visuels sont donc une condition, pas un
conseil de confort.

### Étape 5 — Campagne de mesure (validation de la tranche) — outillage livré le 17/09/2026

Trois objets : **cube étalon de 50 mm** (imprimé depuis notre propre STL),
**boîte en carton**, **interphone Wi-Fi** (objet cible de la tranche 3).

Livré :
- `Packages/Scan3DCore/Sources/Etalon/main.swift` + produit `etalon` du paquet
  et cible `make etalon` : écrit `build/etalon-cube-50mm.stl` (cube de 50,000 mm,
  12 triangles, 684 octets) avec le `STLWriter` de l'app. Si la pièce imprimée
  mesure 50,0 mm au pied à coulisse, toute la chaîne maillage → millimètres →
  STL → slicer est prouvée.
- `MESURES-TRANCHE-2.md` : protocole pas à pas et feuilles de relevé.

**Point de méthode** : on calibre sur **une** cote (la longueur) et on vérifie
sur **les deux autres**. Vérifier la cote qui a servi au calibrage ne prouverait
rien — elle tombe juste par construction.

À faire par Jinkuro : imprimer le cube, puis dérouler le protocole sur les trois
objets et remplir `MESURES-TRANCHE-2.md`. Critère : écart documenté sur les 3
objets, et une mesure point à point après calibrage du cube à **≤ 2 mm** du pied
à coulisse.

## D. Vérification

1. `make test-core` et `make build-check` verts à chaque étape ; build simulateur (doublures).
2. Scénario iPhone de chaque étape, résultats consignés dans `TRANCHE-2-PLAN.md`.
3. Revue sécurité par fonctionnalité (`SECURITY.md`) : `scan.json` non fiable, purge des photos
   orphelines, saisies du calibrage.
4. Critère ROADMAP : `docs/MESURES-TRANCHE-2.md` rempli pour les 3 objets.

## Réutilisation (fichiers existants)

- `Mesh/Mesh.swift` (`Mesh`, `BoundingBox`), `Mesh/MeshLoader.swift`, `Mesh/Dimensions.swift`
  (`Dimensions`, `DimensionsFormatter`), `Units.swift`, `ScaleCalibration.swift`
  (+ `CalibrationError`, `plausibleRange`), `ReferenceObject.swift` (`creditCard`),
  `Scan/ScanLayout.swift`, `Export/STLWriter.swift`, `Export/ExportFilename.swift`.
- App : `Features/Scan/ScanStore.swift` (actor, protection `.complete`, `supprimer`,
  `tailleFichier`), `Features/Export/STLExporter.swift`, `Features/Export/FeuilleDePartage.swift`,
  `Features/Apercu/ApercuView.swift` (base du détail), `App/Journal.swift`.
