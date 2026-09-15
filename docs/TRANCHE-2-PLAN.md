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

### Étape 1 — Bibliothèque des scans (et découpage de `ScanFlowModel`)

Core (`Library/`) :
- `ScanRecord.swift` — `struct ScanRecord: Codable, Equatable, Sendable, Identifiable` :
  `schemaVersion`, `id`, `name`, `createdAt`, `triangleCount`, `dimensions` (brutes), `calibration:
  ScaleCalibration?` ; décodage **validé** (nom 1-80 caractères après nettoyage, nombres finis,
  facteur dans `ScaleCalibration.plausibleRange`) ; `defaultName(date:)` (« Scan du 15/09/2026 14:32 »).
- `ScanLibrary.swift` — classe les dossiers de `Scans/` : `.complete` (modèle + `scan.json` valide),
  `.modelWithoutRecord` (scans de la tranche 1 → récupérables), `.incomplete` (pas de modèle → photos
  orphelines à purger) ; lecture bornée (`scan.json` ≤ 64 Ko), écriture atomique, tri par date.
- `ScanLayout` + `recordFile` ; `Dimensions` et `ScaleCalibration` deviennent `Codable` (décodage
  revalidé par `init(measuredMM:actualMM:)` / `CalibrationError`).
- Tests : aller-retour JSON, JSON invalide / trop gros / version inconnue refusés, classification de
  dossiers dans un répertoire temporaire, tri, nom par défaut.

App :
- Refactor : `Features/DetailScan/DetailScanModel.swift` reprend de `ScanFlowModel` la mesure
  (`mesurerModele`), le `maillage`, l'export (`preparerExportSTL`, `exportTermine`) ;
  `Features/Apercu/ApercuView.swift` devient `Features/DetailScan/DetailScanView.swift` (+ renommer,
  supprimer). `ScanFlowModel` s'arrête à la reconstruction : à la fin, il écrit `scan.json` et passe la
  main au détail.
- `Features/Bibliotheque/BibliothequeModel.swift` + `BibliothequeView.swift` — liste (nom, date,
  cotes compactes, badge « Calibré »), glisser pour supprimer (avec confirmation), « Nouveau scan » ;
  état vide = l'actuel « Prêt à scanner » ; écran « non compatible » conservé. Au lancement :
  récupère les scans de la tranche 1 (mesure + `scan.json`), **purge les dossiers incomplets**.
- `Features/Accueil/AccueilView.swift` → héberge la bibliothèque (`NavigationStack` avec chemin).
- `Features/Scan/ScanStore.swift` — lister, lire / écrire `scan.json`, supprimer, purger (réutilise
  `supprimer`, la protection `.complete`, l'exclusion de sauvegarde).

Sécurité : `scan.json` traité comme entrée non fiable ; le nom saisi n'entre jamais dans un chemin
(dossier = UUID) ; purge des photos orphelines ; suppression = dossier entier.
Accessibilité : actions de glissement exposées à VoiceOver + bouton « Supprimer » dans le détail ;
champ de renommage étiqueté ; Dynamic Type sur la liste.
Test iPhone : les scans de la tranche 1 apparaissent avec leurs cotes ; renommer ; supprimer (Console :
dossier supprimé) ; un nouveau scan arrive en tête ; tuer l'app pendant une capture puis relancer →
Console : dossier incomplet purgé.

### Étape 2 — Visionneuse intégrée et mesure point à point

Core (`Measure/`) :
- `Ray.swift`, `MeshPicking.swift` — `Mesh.firstIntersection(with: Ray) -> MeshHit?`
  (Möller-Trumbore : point, triangle, distance le long du rayon) ; `SegmentMeasurement` (deux points →
  distance en mm via `Units`, calibrage appliqué à l'étape 3).
- Tests : rayon vers une face du cube (point attendu), rayon qui manque, rayon parallèle, face la plus
  proche retenue, deux coins opposés du cube de 50 mm → 70,7 mm, arête → 50 mm, performance 50 k
  triangles.

App (`Features/Visionneuse/`) :
- `VisionneuseView.swift` — **essai en tête d'étape** (incertitudes 1-3) : `RealityView`,
  `Entity(contentsOf:)` à racine identité, `cameraTarget` au centre de la boîte englobante,
  `.realityViewCameraControls(.orbit)` ; toucher → point 2D mémorisé → rayon dans `update` →
  `Mesh.firstIntersection` ; marqueurs A et B (petites sphères) et segment ; distance en surimpression
  SwiftUI (pas d'étiquette 3D).
- `MesureModel.swift` — points A/B, distance, effacer ; annonces VoiceOver (« Point A posé »,
  « Distance : 18,4 centimètres »).
- `DetailScanView` : bouton « Mesurer » → visionneuse plein écran ; Quick Look conservé pour l'AR.

Sécurité : aucune donnée nouvelle ; lecture du modèle déjà validée par `MeshLoader`.
Accessibilité : `.accessibilityDirectTouch(options: .requiresActivation)` sur la vue 3D ; résultat
toujours en texte ; limite assumée et documentée : poser un point précis reste un geste visuel.
Test iPhone : faire tourner le modèle ; toucher deux coins d'une grande arête du dessus → distance à
comparer à la règle (184 mm) et à la boîte englobante (189,2 mm) ; mesurer la hauteur en 3 endroits
(données pour l'étape 4).

### Étape 3 — Calibrage par scan

Core :
- `ScaleCalibration` `Codable` (étape 1) ; `CalibrationReference` : cote saisie ou
  `ReferenceObject.creditCard` (85,60 / 53,98 mm) ; `Dimensions.scaled(by:)` ; échelle appliquée à
  `SegmentMeasurement` et à l'export (`STLWriter.binaryData(for:scale:)`, par défaut 1) ;
  `MillimeterInput.parse(_:locale:)` (virgule française, refus du vide, du négatif, du non fini).
- Tests : facteur appliqué aux cotes, à une distance et au STL (cube 50 mm × 1,02 → 51 mm), saisie
  « 184,0 » / « 184.0 » / « abc » / « -3 », facteur hors plage refusé au décodage.

App (`Features/Calibrage/CalibrageView.swift`) : depuis une mesure A-B, « Calibrer avec cette
mesure » → cote réelle saisie (`.decimalPad`) ou « Carte bancaire » ; aperçu avant application
(« facteur 0,973 → 184,0 × 158,6 × 55,3 mm ») ; Appliquer / Réinitialiser ; enregistré dans
`scan.json` ; badge « Calibré ».

Sécurité : saisie validée par `ScaleCalibration` (±20 %) et le parseur ; aucune valeur saisie ne
peut provoquer d'arrêt.
Accessibilité : champ étiqueté avec l'unité ; erreur annoncée ; facteur et nouvelles cotes lus en phrase.
Test iPhone : calibrer la boîte sur sa longueur (184) → cotes recalculées ; exporter → Bambu Studio
affiche 184 mm ; réinitialiser → retour aux cotes brutes ; relancer l'app → calibrage conservé.

### Étape 4 — Hauteur : diagnostic, puis plan de coupe si confirmé

Diagnostic (Jinkuro, avec l'outil d'étape 2) : scanner la boîte **sans** puis **avec** passe
« Retourner » ; mesurer la hauteur en 3 points sur chaque modèle ; comparer à 50 mm.
Décision (consignée dans `TRANCHE-2-PLAN.md`) :
- **Fond trop bas de façon systématique** → plan de coupe : Core `Mesh.clipped(belowHeightMeters:)`
  (triangles sous le plan supprimés, triangles traversants découpés ; fond laissé ouvert) + tests ;
  App : réglage « Retirer X mm en bas » visualisé par un plan translucide dans la visionneuse,
  `cutHeightMM` dans `scan.json`, appliqué aux cotes et à l'export.
- **Sinon** → conseil seulement : ligne « retournez l'objet pour scanner le dessous » dans la
  checklist de préparation ; aucun code de coupe.

### Étape 5 — Campagne de mesure (validation de la tranche)

Trois objets : **cube imprimé de 50 mm** (étalon), **boîte en carton**, **interphone Wi-Fi** (objet
cible de la tranche 3). Pour chacun, dans `docs/MESURES-TRANCHE-2.md` : cote physique (pied à
coulisse), boîte englobante, mesure point à point, après calibrage. Objectif indicatif : ≤ 2 mm sur
une mesure point à point après calibrage du cube.

---

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
