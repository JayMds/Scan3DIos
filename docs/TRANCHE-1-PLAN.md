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
| 1 | Liste officielle des formats Model I/O non relue (page rendue en JS). Import USDZ par `MDLAsset` très probable (SceneKit, Quick Look) mais non re-vérifié. | Étape 4 : `MDLAsset.canImportFileExtension("usdz")` au runtime + spike de 10 min sur iPhone ; repli RealityKit `MeshResource.contents`. **Levée le 14/09/2026 sur Mac** : import USDZ confirmé ; Model I/O ignore `metersPerUnit` et `upAxis`, n'applique pas les transformations parentes aux sommets, et le pas des sommets varie (12 ou 32 octets). Validation finale : test à la règle sur iPhone. |
| 2 | Texte de E174.1 confirmé via des sources tierces citant Apple. | Xcode / App Store Connect valident le manifeste à l'upload. |
| 3 | Valeur par défaut de `Configuration.isOverCaptureEnabled` non documentée. | Fixée explicitement à `false`. |
| 4 | Comportement réel de la reconstruction quand l'iPhone se verrouille (données protégées + app suspendue). | Scénario n° 5 de `TRANCHE-1.md` §5, à l'étape 3 : décide de la protection définitive. **Levée le 14/09/2026 : reprise automatique, `.complete` confirmé.** |
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

### Étape 2 — Capture guidée (écrans 3, 4, 5) ✅ (13/09/2026)

Objectif : détecter, ajuster la boîte, capturer une ou plusieurs passes,
retourner l'objet, terminer → phase `reconstruction` (placeholder). Tout le
code RealityKit sous `#if !targetEnvironment(simulator)`, avec des doublures
de même interface pour le simulateur.

Core :
- `Capture/CaptureHint.swift` — `enum CaptureHint` (miroir des 9 `Feedback`),
  ordre de déclaration = ordre d'urgence (`priority`), `blocksCapture`,
  `mostUrgent(in:)`. Tests : `CaptureHintTests.swift` (5 tests).

App :
- `Features/Capture/CaptureController.swift` — `@MainActor @Observable`,
  unique propriétaire de l'`ObjectCaptureSession` : `demarrer()` (config
  `checkpointDirectory` = dossier vide, `isOverCaptureEnabled = false`),
  commandes (`startDetecting`, `resetDetection`, `startCapturing`,
  `beginNewScanPass`, `beginNewScanPassAfterFlip`, `finish`), `annuler()`
  (cancel + attente ≤ 2 s que la session finisse d'écrire), deux `Task` sur
  `stateUpdates` et `userCompletedScanPassUpdates` → événements
  `captureCommencee / passeTerminee / terminee / echec` ; libère la session
  (`= nil`) à `.completed`, `.failed`, annulation. Conversion
  `Feedback → CaptureHint` avec `@unknown default`.
- `Features/Capture/CaptureView.swift` — `ObjectCaptureView(session:)` +
  bandeau du conseil courant (rouge s'il bloque), commandes selon
  `session.state` (`.ready` Continuer ; `.detecting` Recommencer / Commencer
  la capture ; `.capturing` compteur `n / max` + « Terminer sans finir le
  tour » dès 20 photos), `.sensoryFeedback(.warning)` + annonce VoiceOver à
  chaque nouveau conseil.
- `Features/Capture/FinDePasseView.swift` — `ObjectCapturePointCloudView` +
  nouvelle passe / retourner (masqué si `.objectNotFlippable`) / terminer.
- `Features/Capture/CaptureSimulateur.swift` — doublures simulateur.
- `Features/Capture/CaptureHint+Texte.swift` — textes FR des 9 conseils.
- `Features/Capture/VeilleEcran.swift` — `isIdleTimerDisabled`, activé de la
  détection à la fin de capture, coupé sur tous les chemins de sortie et à
  l'`onDisappear` du conteneur.
- `Features/Scan/ScanFlowModel.swift` — crée le contrôleur après le dossier,
  traduit ses événements en transitions (`captureCommencee` seulement depuis
  `.detection` ; les passes suivantes transitent elles-mêmes car la session
  reste en `.capturing`), mesure `Images/` à la fin (`bilanCapture`).
- `Features/Scan/ScanFlowView.swift` — titre par phase, `CaptureView` pour
  `.detection` / `.capture`, `FinDePasseView`, `ReconstructionPlaceholderView`,
  `EchecView` (Fermer = supprimer le dossier).
- `Features/Scan/ScanStore.swift` — `tailleImages(_:)` (fichiers + octets ;
  `fileSize` n'est pas une API à raison requise).
- Supprimé : `DetectionPlaceholderView.swift`.

Piège rencontré : `ObjectCaptureSession` / `ObjectCaptureView` viennent du
**cross-import overlay** RealityKit × SwiftUI — le type n'existe que dans un
fichier qui importe les deux modules (ajouté aux pièges de `CLAUDE.md`).

Risques restants : l'état exact après `cancel()` n'est pas documenté (on
attend `.completed` / `.failed` au plus 2 s) ; le simulateur n'est pas
compilé par `make build-check` (destination iOS générique) — à vérifier une
fois dans Xcode.
Sécurité : aucune image ne quitte `Scans/<UUID>/Images` ; taille du dossier
journalisée en octets, jamais de chemin ; session libérée à chaque sortie.
Accessibilité : conseils = bandeau + haptique + annonce VoiceOver ; compteur
avec `accessibilityLabel` en phrase ; nuage de points étiqueté ; boutons
`.controlSize(.large)`.

Test iPhone : boîte mate sur table claire → Nouveau scan → Commencer →
« Détection » : viseur, Continuer → boîte englobante, l'ajuster, Commencer la
capture → « Capture » : compteur qui monte, haptique + bandeau en s'approchant
trop (VoiceOver : « Trop près : reculez un peu ») → tour complet → « Passe
terminée » : nuage de points, Retourner l'objet → deuxième passe → Terminer et
reconstruire → « Capture terminée : N photos, X Mo » (noter ces chiffres pour
l'incertitude 6) → Console : « Capture terminée : N fichiers, X octets » →
Annuler → confirmation → Accueil, « Scan <UUID> supprimé ». Puis : Annuler en
pleine capture → confirmation → l'écran se remet en veille après le délai
réglé.

### Étape 2 bis — Mode plateau tournant ❌ retiré (13-14/09/2026, hors plan initial)

> Livré le 13/09 (commit `fd9ad3c`), en échec au test terrain le 14/09, puis
> **retiré du code** sur décision de Jinkuro (option F : report en
> tranche 4). La description ci-dessous est conservée comme historique.

Demande de Jinkuro après le test de l'étape 2 : tourner autour de l'objet
est peu pratique, il possède un plateau rotatif **manuel**. Options
présentées : A) mode plateau dans la session actuelle, B) capture maison
AVFoundation + LiDAR (comme l'exemple Apple de 2021), C) import de photos
(rejeté : pas de profondeur donc pas d'échelle). **Retenu : A**, B en repli
si la reconstruction déçoit.

Principe : même `ObjectCaptureSession` (viseur, boîte englobante, photos
avec profondeur = échelle réelle) mais `isAutoCaptureEnabled = false`,
photos déclenchées par `requestImageCapture()`, et **pas de checkpoint**
(les poses ARKit d'un iPhone immobile sont identiques). Un objet qui tourne
devant une caméra fixe équivaut à une caméra qui orbite, à condition d'un
fond uni (fixe) et d'une lumière diffuse. **Cas non documenté par Apple** :
la validation se fait par la qualité des reconstructions à l'étape 3.

Core :
- `Capture/CaptureMode.swift` — `orbit` / `turntable`, `usesAutomaticCapture`,
  `usesCheckpoint`, objectif 36 photos par tour (10°), minimum 12 pour
  « Tour terminé », `turntableTurnProgress(shotsThisTurn:)`. Tests :
  `CaptureModeTests.swift` (4 tests).

App :
- `Features/Scan/PreparationView.swift` — sélecteur segmenté du mode
  (préférence `@AppStorage("modeCapture")`), conseils spécifiques au plateau
  (iPhone sur support, fond uni derrière le plateau).
- `Features/Capture/CaptureMode+Texte.swift` — titres et explications.
- `Features/Capture/CaptureController.swift` — `mode` ; `checkpointDirectory`
  seulement si `usesCheckpoint` ; `isAutoCaptureEnabled` ; `photoPossible`
  (`canRequestImageCapture`) ; `prendrePhoto()`.
- `Features/Capture/CaptureView.swift` — en `.capturing`, commandes selon le
  mode : plateau = barre « n / 36 photos ce tour », bouton **Photo**,
  « Tour terminé » (dès 12 photos), annonce VoiceOver du compteur.
- `Features/Capture/FinDePasseView.swift` — libellés adaptés (« Nouveau
  tour à une autre hauteur »).
- `Features/Scan/ScanFlowModel.swift` — `mode`, `demarrer(mode:)`,
  `prendrePhoto()`, `terminerTour()` (c'est l'utilisateur qui déclare le
  tour fini, RealityKit ne le saura jamais), `photosCeTour` (compteur
  cumulé − compteur au début du tour).

**Conséquence pour l'étape 3** : `PhotogrammetrySession.Configuration`
reçoit `checkpointDirectory` seulement si `mode.usesCheckpoint`.

**Résultat du test terrain (14/09/2026) : échec.** Nuage de points
incohérent en fin de tour, reconstruction en échec. Incertitudes 8 et 9
confirmées : l'option A ne fonctionne pas.

Explication la plus probable : `ObjectCaptureSession` enregistre avec les
photos un nuage de points LiDAR placé dans le repère du monde (ARKit).
L'iPhone étant fixe et l'objet tournant, les points de l'objet s'étalent en
traînée (ce que montre l'aperçu), et la reconstruction s'appuie sur ces
données. Le mode plateau **documenté par Apple** (« Capturing photographs
for RealityKit Object Capture ») repose au contraire sur des photos simples
— avec profondeur pour l'échelle réelle — devant un fond uni, sans données
ARKit ; la même page indique que la création d'objets accepte les images de
« n'importe quel appareil photo » sur iOS 17+ et macOS 12+.

Options présentées le 14/09/2026 : B1) prototype de capture maison
(AVFoundation + profondeur LiDAR) puis finition, B2) capture maison complète
d'emblée, F) report au compagnon Mac, G) abandon. **Retenu : F.** Le code de
l'option A est retiré (`CaptureMode`, sélecteur de mode, bouton Photo,
branches du contrôleur) : il reposait sur une approche réfutée, et la
tranche 4 utilisera une autre capture. `ROADMAP.md` (tranche 4) et
`CLAUDE.md` (pièges) consignent la leçon.

Incertitudes ajoutées : (8) qualité de reconstruction en mode plateau ;
(9) `ObjectCapturePointCloudView` avec une caméra fixe peut afficher un
nuage incohérent — à masquer en mode plateau si c'est le cas ; (10) la
boîte englobante peut décrocher quand l'objet tourne (ARKit voit un objet
mobile dans une scène fixe).

Test iPhone : Préparation → « Plateau tournant » (les conseils changent) →
Commencer → poser l'iPhone sur un support, cadrer le plateau → Continuer →
boîte serrée sur le plateau → Commencer la capture → titre Capture : barre
« 0 / 36 photos ce tour », bouton Photo → tourner ~10°, Photo, répéter (le
compteur monte, VoiceOver annonce « n photos ») → « Tour terminé » actif à
partir de 12 → Passe terminée → « Nouveau tour à une autre hauteur » :
surélever l'iPhone, refaire un tour → Terminer et reconstruire → bilan
« N photos, X Mo ». Vérifier : la boîte reste sur l'objet pendant la
rotation ; le bouton Photo se réactive après chaque photo.

### Étape 3 — Reconstruction sur l'iPhone ✅ (14/09/2026)

Objectif : `Images/` → `modele.usdz` avec progression réelle, annulation,
reprise, nettoyage (D1). Traite les deux modes de capture.

Vérifié dans l'interface du SDK (RealityFoundation, iOS 26.5) :
`PhotogrammetrySession.Output` et `.Result` sont `Sendable` ;
`Outputs.next()` est `async throws` ; `ProgressInfo` expose
`estimatedRemainingTime: TimeInterval?` et `processingStage: ProcessingStage?`
(`preProcessing`, `imageAlignment`, `pointCloudGeneration`, `meshGeneration`,
`textureMapping`, `optimization`).

Core :
- `Reconstruction/ReconstructionProgress.swift` — fraction bornée (NaN → 0),
  pourcentage « 42 % » (espace insécable), temps restant arrondi à la minute
  **supérieure** (`RemainingTime` : moins d'une minute / minutes / heures),
  textes courts et parlés, phrase VoiceOver. Tests :
  `ReconstructionProgressTests.swift` (5 tests, dont 2 paramétrés).

App :
- `Features/Reconstruction/Reconstructor.swift` — `@MainActor @Observable`,
  unique propriétaire de la `PhotogrammetrySession` :
  `lancer(images:checkpoint:modele:)` (requête `.modelFile(url:)` au
  détail `.reduced` par défaut ; le checkpoint est devenu obligatoire au
  retrait du mode plateau), boucle
  `for try await` sur `outputs` → événements `progression / info / terminee /
  echec / annulee`, journalisation des photos invalides ou sautées, du
  sous-échantillonnage et du raccord incomplet ; messages français pour
  `PhotogrammetrySession.Error` ; `annuler()` = `cancel()` + attente ≤ 3 s
  de `!isProcessing`. Doublure simulateur dans le même fichier (`#else`).
- `Features/Reconstruction/ReconstructionView.swift` — titre, bilan des
  photos, barre + pourcentage, étape en cours, temps restant, consigne
  « Gardez l'app ouverte » ; `accessibilityValue` en phrase.
- `Features/Scan/ScanFlowModel.swift` — enchaîne capture → reconstruction
  (veille toujours désactivée), `reprendreReconstruction()` (supprime un
  modèle partiel puis relance avec le même checkpoint), D1 après succès
  (`nettoyerApresReconstruction`), `annulationEnCours` qui ignore les
  événements tardifs, confirmation d'annulation aussi quand une reprise est
  possible, `scanTermine`.
- `Features/Scan/ScanFlowView.swift` — `ReconstructionView`,
  `ApercuPlaceholderView`, `EchecView` avec « Reprendre » ; en fin de scan la
  barre affiche **« Fermer » (garde le modèle)** au lieu d'« Annuler »
  (supprimait tout).
- `Features/Scan/EchecView.swift` — « Reprendre la reconstruction » +
  « Abandonner » si reprise possible, sinon « Fermer ».
- `Features/Scan/ApercuPlaceholderView.swift` — écran 7 provisoire
  (remplace `ReconstructionPlaceholderView`).
- `Features/Scan/ScanStore.swift` — `nettoyerApresReconstruction`,
  `supprimerFichier`, `tailleFichier`.
- `App/Journal.swift` — `Logger.reconstruction`.

Risques restants : incertitude 4 (verrouillage) — **à trancher par le
test (2) ci-dessous** ; incertitude 8 (qualité en mode plateau) ; les
modèles terminés s'accumulent dans `Scans/` (~10 Mo chacun) sans moyen de
les supprimer avant la bibliothèque de la tranche 2 (désinstaller l'app les
efface).
Sécurité : D1 appliquée (photos et checkpoint supprimés après succès,
conservés en cas d'échec pour la reprise) ; D2 inchangée en attendant le
test ; erreurs et chemins en `.private`, compteurs en `.public`.
Accessibilité : barre de progression lue « 42 pour cent, environ 2 minutes
restantes » ; icône décorative masquée ; boutons `.controlSize(.large)`.

Test iPhone : (1) scan en orbite → reconstruction : bilan des photos, barre
qui avance, étape qui change, temps restant → « Modèle prêt (X Mo) » →
Fermer ; Console : « Modèle écrit : N octets », « photos et checkpoint
supprimés ». (2) **Verrouiller l'iPhone au milieu**, attendre 30 s,
déverrouiller : noter si la reconstruction reprend seule, ou échoue et
« Reprendre » aboutit (message d'erreur exact dans la console Xcode).
(3) Annuler pendant la reconstruction → confirmation → Accueil, « Scan
<UUID> supprimé ». (4) Même scan en mode plateau → le modèle est-il
cohérent ? (qualité jugée à l'étape 4 ; ici, simple réussite ou échec).

Résultats (14/09/2026) : (1) reconstruction aboutie en mode orbite ;
(2) **reprise automatique après verrouillage** → D2 confirmée ;
(4) **mode plateau en échec** → voir étape 2 bis.

### Étape 4 — Aperçu et dimensions ✅ (14/09/2026, en attente du test iPhone)

Objectif : écran Aperçu avec L × l × h en mm comme information principale,
et visualisation 3D (D3).

Levée de risque avant de coder (essai sur Mac, fichiers USD aux cotes
connues) : `MDLAsset` importe USDZ/USDA/USDC ; il **ignore `metersPerUnit`
et `upAxis`** (valeurs brutes) ; les transformations des nœuds parents se
composent avec `MDLTransform.globalTransform(with:atTime:)` ; le maillage
arrive triangulé ; le **pas entre sommets varie** (12 octets pour un USD,
32 pour un cube généré en mémoire). L'initialiseur avec erreur n'est pas
importé en `throws` (paramètre `error: &erreur`).

Core (`Sources/Scan3DCore/Mesh/`) :
- `Mesh.swift` — `struct Mesh: Equatable, Sendable` (`positions` en mètres,
  `indices`, `boundingBox` calculée une fois), validation (vide, indices non
  multiples de 3, indice hors bornes, coordonnée non finie) et **plafond de
  2 millions de triangles** (déni de service mémoire, préparé pour les
  imports de la tranche 3). `MeshError`, `BoundingBox`.
- `MeshLoader.swift` — `import ModelIO` (hors API publique) :
  `load(contentsOf:)` vérifie format et lisibilité, fusionne tous les
  `MDLMesh` en appliquant leur transformation globale, lit positions et
  indices **bornés par `bufferSize` / `length`**, refuse la géométrie non
  triangulaire, arrêt précoce au plafond.
- `Dimensions.swift` — `Dimensions` (longueur ≥ largeur à l'horizontale,
  hauteur selon Y, via `Units`), `isPlausible` (plus grande cote entre 1 mm
  et 5 m, sinon erreur d'unité probable) ; `DimensionsFormatter` :
  « 124,0 mm », « 124,0 × 85,6 × 40,2 mm », phrase VoiceOver en centimètres
  avec accord du pluriel.
- Tests : `MeshTests.swift` (6 tests de validation + 6 de lecture : cube
  0,05 m → 50 mm, transformation parente ×2, fusion de deux maillages,
  aller-retour par un vrai fichier `.usda`, fichier absent, format inconnu),
  `DimensionsTests.swift` (5 tests).

App :
- `Features/Apercu/ApercuView.swift` — `List` : cotes compactes en gros,
  lignes Longueur / Largeur / Hauteur, avertissement si non plausibles,
  pied de page (triangles, taille, « boîte englobante, contrôlez au pied à
  coulisse ») ; « Voir en 3D » → `.quickLookPreview` (**`import QuickLook`**
  requis) ; « Terminer » ; annonce VoiceOver des dimensions dès qu'elles sont
  prêtes.
- `Features/Scan/ScanFlowModel.swift` — `MesureModele` (`enCours`,
  `reussie`, `echec`), `mesurerModele` dans un `Task.detached` à la fin de
  la reconstruction, dimensions journalisées en public.
- `Features/Scan/ScanFlowView.swift` — `.preview(let modele)` → `ApercuView`.
- Supprimé : `ApercuPlaceholderView.swift`.
- « Exporter » n'apparaît pas encore : il arrive avec l'étape 5 (pas de
  bouton inactif dans l'interface).

Risques restants : unités réelles du fichier Object Capture (supposées en
mètres, **validées seulement par le test à la règle**) ; boîte englobante
alignée sur les axes du modèle — si l'objet est tourné autour de la
verticale dans le fichier, longueur et largeur sont surestimées (repli : un
rectangle d'aire minimale dans `Scan3DCore`).
Sécurité : lecture bornée des tampons, plafond de triangles, validation des
indices ; aucune donnée nouvelle ne quitte l'appareil.
Accessibilité : phrase complète pour les cotes compactes, valeur en
centimètres sur chaque ligne, annonce à l'arrivée, Quick Look accessible
nativement, boutons `.controlSize(.large)`.

Test iPhone : (1) boîte en carton : mesurer ses trois cotes à la règle et
les noter → scanner autour → reconstruction → écran Aperçu : « Mesure du
modèle… » puis les cotes ; comparer à la règle (écart attendu de quelques
mm ; noter les deux séries) ; Console : « Dimensions … mm, N triangles,
plausibles : true ». (2) « Voir en 3D » : faire tourner le modèle, puis
passer en mode AR (« AR » en haut) et poser le modèle à côté de la vraie
boîte : même taille. (3) VoiceOver activé : à l'arrivée sur l'écran,
entendre « Modèle prêt : … centimètres de long… ». (4) Plus grande taille de
texte (Réglages → Accessibilité) : les cotes restent lisibles, rien n'est
tronqué.

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
