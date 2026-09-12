# Tranche 1 — Plan d'implémentation

Complète `TRANCHE-1.md` (la spec). Ce document est la référence des sessions
« Implémente l'étape N du plan de la tranche 1 ». Établi le 12/09/2026 après
vérification des API dans la documentation Apple (Xcode 26.6, SDK iOS 26.5,
cible iOS 18).

## A. API vérifiées dans la documentation Apple

### `ObjectCaptureSession` (RealityKit, iOS 17+)

- `@MainActor class ObjectCaptureSession : Observable, Identifiable` — donc
  utilisable comme propriété d'un modèle `@Observable`, SwiftUI se rafraîchit
  tout seul.
- `init()`, `static var isSupported: Bool`.
- `func start(imagesDirectory: URL, configuration: Configuration)`.
- `func startDetecting() -> Bool`, `func startCapturing()`, `func finish()`,
  `func cancel()`, `func resetDetection() -> Bool`, `func pause()`,
  `func resume()`, `func beginNewScanPass()`,
  `func beginNewScanPassAfterFlip()`, `func requestImageCapture()`.
- Propriétés observables + flux `AsyncSequence` associés : `state` /
  `stateUpdates`, `feedback: Set<Feedback>` / `feedbackUpdates`,
  `userCompletedScanPass` / `…Updates`, `numberOfShotsTaken`,
  `maximumNumberOfInputImages`, `cameraTracking`, `isPaused`,
  `shouldPlayHaptics`, `isAutoCaptureEnabled`, `canRequestImageCapture`.
- `CaptureState` : `.initializing → .ready → .detecting → .capturing →
  .finishing → .completed`, et `.failed(any Error)`. `.completed` = « la
  session peut être détruite et le dossier d'images utilisé pour la
  reconstruction ».
- `Feedback` (9 cas) : `environmentLowLight`, `environmentTooDark`,
  `movingTooFast`, `objectNotDetected`, `objectNotFlippable`,
  `objectTooClose`, `objectTooFar`, `outOfFieldOfView`, `overCapturing`.
- `Tracking` : `.normal`, `.limited(reason:)`, `.notAvailable` (l'overlay de
  coaching ARKit est affiché par `ObjectCaptureView` lui-même).
- `Configuration` : `init()`, `checkpointDirectory: URL?`,
  `isOverCaptureEnabled: Bool`. **Piège documenté** : `checkpointDirectory`
  doit pointer vers un dossier **vide et inscriptible**, sinon la session
  passe en `.failed` → un dossier `Checkpoint/` neuf par scan.
- `ObjectCaptureView(session:)`, `ObjectCaptureView(session:cameraFeedOverlay:)`,
  `.hideObjectReticle(_:)`. `ObjectCapturePointCloudView(session:)` : aperçu
  du nuage de points avec gestes de rotation intégrés, à afficher en fin de
  passe.

### `PhotogrammetrySession` (iOS 17+, macOS 12+)

- `convenience init(input: URL, configuration: Configuration) throws`,
  `static var isSupported: Bool`.
- `var outputs: Outputs` (`AsyncSequence`) →
  `for try await output in session.outputs`.
- `func process(requests: [Request]) throws`, `func cancel()`,
  `var isProcessing: Bool`.
- `Configuration` : `init()`, `init(checkpointDirectory:)`,
  `checkpointDirectory: URL?`, `featureSensitivity`, `sampleOrdering`,
  `isObjectMaskingEnabled`, `ignoreBoundingBox` (`meshPrimitive` et
  `customDetailSpecification` : macOS seulement).
- `Request.modelFile(url: URL, detail: Detail = .reduced, geometry: Geometry? = nil)`
  — URL en `.usdz` → fichier USDZ ; URL de dossier → OBJ + textures. Autres
  requêtes : `.bounds`, `.modelEntity`, `.pointCloud`, `.poses`.
- **`Detail` sur iOS : uniquement `.reduced`** (< 50 k triangles, textures
  2048²). Citation : « On iOS, only one detail level – `.reduced` – is
  currently supported ». `.preview`, `.medium`, `.full`, `.raw`, `.custom`
  sont macOS → aucun choix de qualité dans l'UI de la tranche 1 ; la haute
  précision est le rôle du compagnon Mac (tranche 4).
- `Output` : `inputComplete`, `processingComplete`, `processingCancelled`,
  `requestProgress(Request, fractionComplete: Double)`,
  `requestProgressInfo(Request, ProgressInfo)` (temps restant estimé),
  `requestComplete(Request, Result)`, `requestError(Request, any Error)`,
  `invalidSample(id:reason:)`, `skippedSample(id:)`, `automaticDownsampling`,
  `stitchingIncomplete`.
- `Result.modelFile(URL)`, `.bounds(BoundingBox)`, `.modelEntity`,
  `.pointCloud`, `.poses`.
- `Error` : `insufficientStorage(requiredBytes: Int64)`, `invalidImages(URL)`,
  `invalidOutput(URL)` — conforme `LocalizedError`.

### Autres API

- SwiftUI `.quickLookPreview(_ item: Binding<URL?>)` (iOS 14+) : visionneuse
  USDZ native, mode AR.
- `RealityView` : iOS 18+ (`RealityViewCameraContent` sur iOS). Non utilisé en
  tranche 1.
- Model I/O : `MDLAsset(url:)`, `canImportFileExtension(_:)`,
  `canExportFileExtension(_:)`, `export(to:) throws`, `boundingBox`,
  `childObjects(of:)` ;
  `MDLMesh.vertexAttributeData(forAttributeNamed:as:) -> MDLVertexAttributeData?` ;
  `MDLSubmesh.indexBuffer(asIndexType:)`, `indexCount`, `geometryType` ;
  `MDLMesh(boxWithExtent:segments:inwardNormals:geometryType:allocator:)`
  (cube de test fabriqué en mémoire — pas de fixture `.usdz`, ignorée par git).
- RealityKit `MeshResource.contents` → `models[].parts[]` avec `positions` /
  `triangleIndices` (iOS 15+) — repli pour lire le maillage.
- `FileProtectionType` : `.complete` (illisible dès verrouillage),
  `.completeUnlessOpen` (un fichier déjà ouvert reste lisible, chiffré une fois
  fermé), `.completeUntilFirstUserAuthentication` (défaut iOS : lisible après
  le premier déverrouillage depuis le démarrage).
- Manifeste de confidentialité, catégorie
  `NSPrivacyAccessedAPICategoryDiskSpace`, raison **E174.1** : « vérifier s'il
  y a assez d'espace disque pour écrire des fichiers, ou si l'espace est bas
  pour supprimer des fichiers ; l'app doit se comporter différemment de façon
  observable par l'utilisateur ». C'est notre cas (refus de démarrer un scan
  si l'espace manque).

### Incertitudes et comment on les lève

| # | Incertitude | Mitigation |
|---|-------------|------------|
| 1 | Liste officielle des formats Model I/O non relue (page rendue en JS). Import USDZ par `MDLAsset` très probable (SceneKit, Quick Look) mais non re-vérifié. | Étape 4 : `MDLAsset.canImportFileExtension("usdz")` au runtime + spike de 10 min sur iPhone ; repli RealityKit `MeshResource.contents`. |
| 2 | Texte de E174.1 confirmé via des sources tierces citant Apple. | Xcode / App Store Connect valident le manifeste à l'upload. |
| 3 | Valeur par défaut de `Configuration.isOverCaptureEnabled` non documentée. | Fixée explicitement à `false`. |
| 4 | Comportement réel de la reconstruction quand l'iPhone se verrouille (données protégées + app suspendue). | Scénario n° 5 de `TRANCHE-1.md` §5, à l'étape 3 : décide de la protection définitive. |
| 5 | Notes WWDC23 : session dans un `@StateObject` (bêta 2023) ; doc actuelle : `Observable`. | Suivre la doc : propriété d'une classe `@Observable`. Si l'UI ne se rafraîchit pas, consommer `stateUpdates`. |
| 6 | Espace disque requis avant un scan : aucune valeur Apple. | Constante 2 Go dans `Scan3DCore`, ajustée après mesure de `Images/` (loggée à l'étape 2). |
| 7 | Swift 6 strict : `PhotogrammetrySession` n'est pas `Sendable`, `Output` embarque `any Error`. | Créer **et** consommer la session dans le même contexte (`@MainActor`) ; le calcul lourd tourne dans les threads internes de RealityKit. |

## B. Décisions (validées par Jinkuro le 12/09/2026)

| Décision | Choix | Effet sur le plan |
|----------|-------|-------------------|
| D1 Photos | **Supprimer `Images/` + `Checkpoint/` après succès**, garder en cas d'échec | Étape 3 : nettoyage dans `ScanStore` ; tranche 4 : opt-in « conserver pour le Mac » |
| D2 Protection | **`.complete`** + « Reprendre » depuis le checkpoint | Étape 1 : attribut posé à la création ; étape 3 : le test n° 5 décide d'une bascule vers `.completeUnlessOpen` |
| D3 Aperçu | **Quick Look**, dimensions d'abord | Étape 4 : pas de `RealityView` (viendra avec la mesure, tranche 2) |
| D4 Maillage | **Model I/O dans `Scan3DCore`** + `STLWriter` maison | Étapes 4–5 : chaîne complète testée sur Mac ; repli RealityKit |

### Alternatives étudiées

**D1 — photos après reconstruction**

| Option | Avantages | Inconvénients |
|--------|-----------|---------------|
| **a. Supprimer après succès, garder si échec** (retenu) | Minimisation des données personnelles (photos de l'intérieur) ; pas de gestion d'espace en tranche 1 ; le `.usdz` (~10 Mo) suffit à la bibliothèque (tranche 2). | Pas de re-reconstruction sur Mac (tranche 4) sans rescanner. |
| b. Tout garder | Tranche 4 immédiate. | 0,5 à 2 Go par scan ; surface sensible maximale ; UI de nettoyage obligatoire. |
| c. Garder + purge automatique | Souple. | Plus d'UI et de logique pour un besoin (Mac) qui n'existe pas encore. |

En tranche 4 : préférence **opt-in** « conserver les photos pour le Mac »
(`UserDefaults`, c'est une préférence).

**D2 — protection des fichiers `Scans/<UUID>/`**

| Option | Avantages | Inconvénients |
|--------|-----------|---------------|
| **a. `.complete` + « Reprendre »** (retenu) | Protection maximale. L'app est suspendue au verrouillage (pas de tâche de fond) : seul risque, une lecture en cours à cet instant → `requestError` → Reprendre depuis le checkpoint. | Un verrouillage manuel pendant la reconstruction peut coûter une reprise de quelques secondes. À confirmer par le test n° 5. |
| b. `.completeUnlessOpen` | Les fichiers déjà ouverts restent lisibles. | La reconstruction ouvre les images progressivement : celles pas encore ouvertes deviennent illisibles → échec probable quand même. |
| c. `.completeUntilFirstUserAuthentication` | Zéro friction. | Photos lisibles sur un iPhone volé verrouillé (déjà déverrouillé depuis le démarrage) avec un outil forensique. |

Règle de bascule : si le test n° 5 montre des échecs fréquents avec a, passer
à b et documenter dans `SECURITY.md`. Dans tous les cas :
`isExcludedFromBackup = true`.

**D3 — aperçu 3D**

| Option | Avantages | Inconvénients |
|--------|-----------|---------------|
| **a. Quick Look** (retenu) | Zéro code de rendu ; gestes et VoiceOver gérés par Apple ; mode AR à l'échelle réelle. | Modal plein écran ; `RealityView` sera nécessaire en tranche 2 (mesure). |
| b. `RealityView` intégré | Écran unique, base pour la mesure. | Rotation/zoom et accessibilité à coder ; API de contrôle caméra non vérifiée. |
| c. Les deux | Le meilleur des deux. | Hors budget tranche 1. |

**D4 — lecture du maillage (dimensions + STL)**

| Option | Avantages | Inconvénients |
|--------|-----------|---------------|
| **a. Model I/O dans `Scan3DCore` + `STLWriter` maison** (retenu) | Chaîne entière testable sur Mac avec un cube généré en mémoire (le test « 0,05 m → 50 mm » est unitaire) ; réutilisable par l'app Mac. | `import ModelIO` dans Core (framework Apple, pas une dépendance tierce) ; incertitude 1. |
| b. RealityKit dans l'app + `STLWriter` dans Core | Lecture garantie (même framework que la reconstruction). | Extraction non testable sur Mac ; test ×1000 partiel. |
| c. `MDLAsset.export(to: .stl)` | Le moins de code. | Transforms aplatis/ignorés à l'export (retours de forum) ; pas de contrôle du format ; test ×1000 impossible en unitaire. |

## C. Étapes

Convention : « Core » = `Packages/Scan3DCore/Sources/Scan3DCore/`, « App » =
`Scan3D/`. Chaque étape se termine par `make test-core` + `make build-check`,
l'explication fichier par fichier, le scénario iPhone, puis un commit `feat:`.

### Étape 0 — Documentation et décisions ✅ (12/09/2026)

`VISITE-GUIDEE.md`, ce plan, section 6 de `TRANCHE-1.md` cochée, décision D2
dans `SECURITY.md`, `git init` + commit du kit.

### Étape 1 — Squelette du parcours, préparation, permission caméra, stockage ✅ (13/09/2026)

Objectif : Accueil → Préparation → (permission) → écran Détection *vide* ; le
dossier de scan est créé avec la bonne protection ; refus de permission géré.

Convention respectée : identifiants **anglais** dans `Scan3DCore` (comme
`ScaleCalibration`), **français** dans l'app (comme `AccueilView`).

Core (`Sources/Scan3DCore/Scan/`) :
- `ScanPhase.swift` — `enum ScanPhase: Equatable, Sendable` (`preparation`,
  `detection`, `capture`, `passComplete`, `reconstruction(progress: Double)`,
  `preview(model: URL)`, `failed(message: String)`), `canTransition(to:)`,
  `transition(to:) throws(ScanPhaseError)`, `cancellationNeedsConfirmation`.
  L'échec est accepté depuis la détection aussi (la session peut échouer
  avant la première photo) ; `failed → reconstruction` = « Reprendre ».
- `ScanLayout.swift` — URL d'un scan (`root`, `imagesDirectory`,
  `checkpointDirectory`, `modelFile`) à partir d'une racine et d'un `UUID`.
- `DiskSpacePolicy.swift` — `requiredFreeBytes` (2 Gio, incertitude 6),
  `isSufficient(available:)`, `missingBytes(available:)`.
- Tests : `ScanPhaseTests.swift` (parcours nominal, 11 sauts interdits,
  sources d'échec, reprise, confirmation d'annulation),
  `ScanStorageTests.swift` (arborescence, types d'URL, isolation, seuil).

App :
- `App/Journal.swift` — `Logger.scan`, `Logger.stockage`.
- `Features/Scan/ScanFlowModel.swift` — `@MainActor @Observable final class`,
  source de vérité de la phase ; `demarrer()` valide la transition avant
  tout effet de bord, puis permission → espace → dossier ; `annuler()`.
- `Features/Scan/ScanFlowView.swift` — `switch` exhaustif sur la phase,
  Annuler (confirmation si `cancellationNeedsConfirmation`), alerte d'erreur,
  rafraîchissement de l'autorisation au retour au premier plan.
- `Features/Scan/PreparationView.swift` — checklist à 3 conseils + astuce
  spray matifiant + « Commencer le scan ».
- `Features/Scan/CameraAuthorization.swift` — statut en 3 valeurs, demande
  au premier scan, `@unknown default`.
- `Features/Scan/CameraRefuseeView.swift` — explication + lien Réglages.
- `Features/Scan/ScanStore.swift` — `actor` : crée
  `Application Support/Scans/<UUID>/{Images,Checkpoint}` avec
  `.protectionKey = .complete`, `isExcludedFromBackup`, mesure
  `volumeAvailableCapacityForImportantUsage`, supprime ; journalise la
  protection réellement posée.
- `Features/Scan/DetectionPlaceholderView.swift` — écran 3 provisoire.
- `Features/Accueil/AccueilView.swift` — bouton « Nouveau scan » →
  `fullScreenCover(ScanFlowView)`.
- `Resources/PrivacyInfo.xcprivacy` — `NSPrivacyAccessedAPICategoryDiskSpace`
  / `E174.1`.

Sécurité : permission demandée au premier scan, jamais au lancement ; E174.1 ;
protection `.complete` + exclusion iCloud ; journaux : UUID public, chemins et
descriptions d'erreur privés.
Accessibilité : lignes de checklist avec `accessibilityValue` / `Hint`,
boutons `.controlSize(.large)`, textes système (Dynamic Type).

Test iPhone : Nouveau scan → checklist → prompt caméra → **refuser** → écran
« Caméra non autorisée » avec lien Réglages, sans plantage → autoriser dans
Réglages (iOS relance l'app : c'est normal) → Nouveau scan → Commencer →
écran Détection avec l'identifiant court → Console : « Scan <UUID> créé,
protection NSFileProtectionComplete » → Annuler → Accueil, Console :
« Scan <UUID> supprimé ». Simulateur : « Appareil non compatible » inchangé.

### Étape 2 — Capture guidée (écrans 3, 4, 5)

Objectif : détecter, ajuster la boîte, capturer une ou plusieurs passes,
retourner l'objet, terminer → phase `reconstruction` (placeholder). Tout le
code RealityKit sous `#if !targetEnvironment(simulator)`.

Core :
- `Capture/CaptureHint.swift` — `enum CaptureHint` (miroir neutre des 9
  `Feedback`) + texte FR + **priorité** quand plusieurs conseils sont actifs
  (ex. `environmentTooDark` > `objectTooClose` > `movingTooFast`). Tests :
  priorité, couverture des 9 cas.

App :
- `Features/Capture/CaptureController.swift` — possède
  l'`ObjectCaptureSession`, `start(...)` avec `Configuration`
  (`checkpointDirectory` = dossier vide, `isOverCaptureEnabled = false`),
  consomme `stateUpdates`, `feedbackUpdates`, `userCompletedScanPassUpdates`
  dans des `Task` ; mappe `Feedback → CaptureHint` ; libère la session
  (`= nil`) à `.completed`, `.failed`, annulation.
- `Features/Capture/CaptureView.swift` — `ObjectCaptureView(session:)` +
  overlay : conseil courant, compteur
  `numberOfShotsTaken / maximumNumberOfInputImages`, Continuer / Terminer.
- `Features/Capture/FinDePasseView.swift` —
  `ObjectCapturePointCloudView(session:)` + trois choix : nouvelle passe
  (`beginNewScanPass`), retourner (`beginNewScanPassAfterFlip`, masqué si
  `feedback` contient `.objectNotFlippable`), terminer (`finish`).
- `Features/Capture/CaptureFeedbackAnnouncer.swift` — haptique
  (`UINotificationFeedbackGenerator`) + `AccessibilityNotification.Announcement`
  pour chaque nouveau conseil ; `shouldPlayHaptics` de la session laissé actif.
- `ScanFlowModel` : `isIdleTimerDisabled = true` à l'entrée en capture, remis
  à `false` dans **tous** les chemins (`defer`) ; annulation pendant la
  capture → `confirmationDialog`.

Risques : une seule session à la fois (mémoire) → le contrôleur est l'unique
propriétaire ; `checkpointDirectory` non vide → `.failed` ; Swift 6 et les
`Task` de consommation (tout reste `@MainActor`).
Sécurité : aucune image ne quitte `Scans/<UUID>/Images` ; log de la taille du
dossier (octets, pas de chemin) pour calibrer l'incertitude 6.
Accessibilité : conseils annoncés à VoiceOver + haptique, jamais visuel seul ;
boutons de fin de passe ≥ 44 pt, libellés explicites.

Test iPhone : boîte mate sur table claire → détection, ajuster la boîte →
capture d'une passe (haptique ; VoiceOver activé : « Trop près », etc.) → fin
de passe : nuage de points, « Retourner » → deuxième passe → Terminer → phase
reconstruction (placeholder). Annuler en pleine capture → confirmation →
dossier supprimé, veille réactivée.

### Étape 3 — Reconstruction sur l'iPhone

Objectif : `Images/` → `modele.usdz` avec progression réelle, annulation,
reprise, nettoyage (D1).

Core :
- `Reconstruction/ReconstructionProgress.swift` — formatage pur : fraction →
  « 42 % », temps restant → « environ 2 min » ; tests.

App :
- `Features/Reconstruction/Reconstructor.swift` — `@MainActor` :
  `PhotogrammetrySession(input: Images, configuration: .init(checkpointDirectory: Checkpoint))`,
  `process(requests: [.modelFile(url: modele.usdz)])` (`.reduced` implicite),
  `for try await output in session.outputs` → `requestProgress` /
  `requestProgressInfo` → phase `.reconstruction(progression:)`,
  `requestComplete(.modelFile)` → `.apercu`, `requestError` /
  `PhotogrammetrySession.Error` → `.echec(message)` localisé ; `cancel()`.
- `Features/Reconstruction/ReconstructionView.swift` — barre + % + temps
  estimé + « gardez l'app ouverte » + Annuler ; état d'échec avec
  « Reprendre » (même checkpoint) et « Abandonner ».
- `ScanStore` : suppression de `Images/` et `Checkpoint/` après succès
  (D1), conservation en cas d'échec.

Risques : incertitude 4 (verrouillage) — **l'étape qui tranche D2** ;
mémoire (session de capture déjà libérée).
Sécurité : D2 réévaluée ; suppression des photos ; `insufficientStorage`
affiché avec la taille manquante.
Accessibilité : progression exposée via `accessibilityValue`
(« 42 pour cent »), annonce à la fin.

Test iPhone : (1) reconstruction complète, progression qui avance, arrivée
sur Aperçu ; (2) **verrouiller l'iPhone au milieu** → déverrouiller → noter :
reprise transparente, ou échec + « Reprendre » fonctionne ; (3) Annuler →
Accueil, dossier supprimé ; (4) Réglages → Général → Stockage iPhone : l'app
ne grossit pas après un scan réussi.

### Étape 4 — Aperçu et dimensions

Objectif : écran Aperçu avec L × l × h en mm comme information principale,
et visualisation 3D (D3).

Core :
- `Mesh/Mesh.swift` — `struct Mesh: Sendable` (`positions: [SIMD3<Float>]`,
  `indices: [UInt32]`), validation (indices dans les bornes, multiple de 3).
- `Mesh/MeshLoader.swift` — `import ModelIO` : `MDLAsset(url:)` →
  `childObjects(of: MDLMesh.self)` →
  `vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition, as: .float3)`
  + `submesh.indexBuffer(asIndexType: .uInt32)` → `Mesh` (D4) ; transforms
  parents composés.
- `Mesh/Dimensions.swift` — boîte englobante en mètres → `Dimensions` en mm
  via `Units` ; `DimensionsFormatter` : « 124,0 × 85,5 × 40,2 mm » et phrase
  VoiceOver « 12,4 centimètres de large, … » (`MeasurementFormatter`).
- Tests : cube `MDLMesh(boxWithExtent: [0.05, 0.05, 0.05])` → 50,0 mm sur
  les trois axes ; mesh invalide refusé ; formatage FR.

App :
- `Features/Apercu/ApercuView.swift` — dimensions en gros (Dynamic Type),
  « Voir en 3D » → `.quickLookPreview($url)` (D3), « Exporter » (étape 5),
  « Terminer ».

Risques : incertitude 1 (import USDZ par Model I/O) → spike en début
d'étape, repli D4-b.
Sécurité : aucune donnée nouvelle.
Accessibilité : dimensions avec `accessibilityLabel` en phrase ; Quick Look
accessible nativement.

Test iPhone : mesurer la boîte à la règle ; écart de quelques mm attendu ;
ouvrir la 3D, passer en AR : l'objet virtuel a la taille du vrai.

### Étape 5 — Export STL en millimètres

Objectif : `Scan3D-<date>.stl` partagé via la feuille iOS, ouvert dans Bambu
Studio à la bonne taille.

Core :
- `Export/STLWriter.swift` — STL **binaire** (en-tête 80 octets, `UInt32`
  nombre de triangles, 50 octets/triangle, little-endian), normales
  calculées, mise à l'échelle par `Units`. Tests : cube 0,05 m → sommets à
  ±25 mm, taille du fichier = 84 + 50 × n, relecture des 12 triangles ; mesh
  vide refusé.
- `Export/ExportFilename.swift` — nom de fichier daté.

App :
- `Features/Export/STLExporter.swift` — dossier temporaire dédié,
  `ShareLink(item:)` (ou `UIActivityViewController` si `ShareLink` ne propose
  pas Bambu Handy), suppression du fichier temporaire après partage.

Risques : STL sans unités — la convention « mm » des slicers fait foi, d'où
le test ×1000.
Sécurité : le STL ne contient que de la géométrie (pas d'EXIF, pas de photo) ;
seule donnée qui quitte l'appareil, sur action explicite.
Accessibilité : `ShareLink` natif.

Test iPhone : exporter → AirDrop vers le Mac → Bambu Studio : dimensions
cohérentes avec l'écran Aperçu ; envoyer vers Bambu Handy / Fichiers ;
vérifier que le fichier temporaire a disparu (log du seul nom de fichier).

## D. Vérification globale de la tranche

1. `make test-core` et `make build-check` verts à chaque étape.
2. Scénario complet de `TRANCHE-1.md` §5 après l'étape 5, sur les deux
   iPhones (14 Pro Max, 17 Pro Max).
3. Revue sécurité par fonctionnalité (`SECURITY.md`) consignée dans le
   message de fin de chaque étape.
4. Critère ROADMAP : un objet du quotidien scanné, exporté, ouvert dans Bambu
   Studio avec des dimensions cohérentes.
