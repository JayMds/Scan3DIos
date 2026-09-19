# Visite guidée du dépôt

État au 12/09/2026 (fin de tranche 0). Pour chaque fichier : son rôle en une
phrase, puis les notions Swift qu'il illustre. Les `§` renvoient aux sections
de `SWIFT-POUR-TS.md`. Relire ce document après chaque tranche : il doit
rester le plan du dépôt.

## Vérification du kit (tranche 0)

| Vérification | Résultat |
|---|---|
| Outillage | XcodeGen 2.46.0 · Xcode 26.6 · Swift 6.3.3 · SDK iOS 26.5 |
| `make test-core` | 5 tests, 2 suites, 0 échec |
| `make build-check` | code de sortie 0, aucun avertissement |

Validation finale de la tranche 0 = l'app installée sur l'iPhone affiche
« Prêt à scanner » (scénario en fin de document).

## Les fichiers Swift

### `Packages/Scan3DCore/Package.swift`

**Rôle** : le `package.json` + `tsconfig.json` du paquet de logique pure —
nom, plateformes (iOS 18 / macOS 15), un produit `library`, deux cibles
(code + tests).

- `// swift-tools-version: 6.0` en première ligne = version du gestionnaire
  de paquets **et** mode langage Swift 6 (concurrence stricte, §9). Ce n'est
  pas un simple commentaire : SwiftPM le lit.
- `Package(...)` est une simple valeur `let` : le manifeste est du Swift
  exécuté, pas du JSON.

### `Packages/Scan3DCore/Sources/Scan3DCore/Units.swift`

**Rôle** : la conversion mètres ↔ millimètres, centralisée pour que l'oubli
« pièce 1000× trop petite » soit impossible ailleurs.

- `enum Units` **sans aucun `case`** : idiome Swift pour un *namespace*.
  Impossible d'instancier, on n'appelle que des `static`. En TS :
  `const Units = { ... } as const` ou un module.
- `static let` / `static func` (§10 pour le `public` : l'app est hors du
  paquet, tout ce qu'elle voit doit être `public`).
- Corps d'une ligne sans `return` : retour implicite, comme une arrow
  function TS sans accolades.
- Étiquettes d'arguments (§7) : `Units.millimeters(fromMeters: 0.12)` se lit
  comme une phrase.

### `Packages/Scan3DCore/Sources/Scan3DCore/ReferenceObject.swift`

**Rôle** : catalogue des objets de référence aux dimensions connues (pour
l'instant : carte bancaire ISO ID-1), pour le calibrage de la tranche 2.

- `enum ReferenceObject: String` = enum **à valeur brute** : chaque cas a une
  `String` associée automatiquement (`"creditCard"`), comme
  `enum X { creditCard = "creditCard" }` en TS.
- Conformances en chaîne : `Sendable` (§9, circule entre threads),
  `CaseIterable` (donne `ReferenceObject.allCases` ≈ `Object.values(...)`),
  `Identifiable` (exigé par SwiftUI pour les listes — la prop `key` de React).
- Propriétés calculées `var widthMM: Double { ... }` = accesseur `get` TS. Le
  `switch` est utilisé comme **expression** (`case .creditCard: 85.60`, sans
  `return`) et doit couvrir tous les cas (§4) : ajouter un objet sans
  renseigner ses cotes ne compile pas.

### `Packages/Scan3DCore/Sources/Scan3DCore/ScaleCalibration.swift`

**Rôle** : calcule un facteur d'échelle à partir d'une cote mesurée vs
réelle, en refusant toute saisie invalide ou aberrante. Le fichier le plus
dense en notions : à relire en premier.

- `struct` (§3) : valeur copiée, immuable (`let factor`) → pas d'effet de
  bord.
- `enum CalibrationError: Error` avec valeur associée
  `implausibleFactor(Double)` (§4) : l'erreur transporte la donnée utile pour
  le message UI.
- **Erreurs typées** `throws(CalibrationError)` (§6, Swift 6) : l'appelant
  sait exactement quel type d'erreur attraper. D'où `throw .invalidMeasurement`
  sans préfixe : le type est déjà connu.
- `guard ... else { throw }` (§2) en tête de fonction : cas d'échec d'abord,
  chemin nominal ensuite, zéro imbrication.
- `ClosedRange` `0.8...1.2` et `.contains(candidate)` ; `Self.plausibleRange`
  = accès à une constante statique depuis une instance (`Self` majuscule =
  « mon type »).
- Commentaires `///` = JSDoc : Xcode les affiche au survol.

### `Packages/Scan3DCore/Tests/Scan3DCoreTests/ScaleCalibrationTests.swift`

**Rôle** : les tests Swift Testing de tout `Scan3DCore` — nominal, entrées
invalides, facteur aberrant, conversion d'unités, cotes de la carte.

- `import Testing` + `@Suite` / `@Test` / `#expect` : Vitest-like. Le `#`
  signale une **macro** (code généré à la compilation, comme un plugin Babel
  typé).
- `@testable import` : autorise le test à voir les membres `internal` (§10)
  du module.
- **Tests paramétrés** `arguments: [0.0, -12.0, .infinity, .nan]` =
  `test.each` : un test, quatre cas, chacun rapporté séparément.
- `#expect(throws: CalibrationError.invalidMeasurement) { ... }` vérifie une
  erreur **précise** (grâce à `Equatable` sur l'enum) ;
  `#expect(throws: CalibrationError.self)` vérifie seulement le type.
- `func recaleLaCote() throws` : un test peut lui-même être `throws` ; une
  erreur inattendue = échec du test, sans `try/catch` manuel.
- « Jamais `==` sur des `Double` calculés » — vrai aussi en JS (`0.1 + 0.2`).

### `Scan3D/App/Scan3DApp.swift`

**Rôle** : point d'entrée de l'app, l'équivalent du `App.tsx` /
`_layout.tsx` racine d'un projet Expo.

- `@main` : « c'est ici que l'exécution démarre » (un seul par app).
- `struct Scan3DApp: App` (§5 : `App` est un `protocol`) avec
  `body: some Scene` — même forme qu'une vue, mais au niveau « fenêtre ».
- `WindowGroup { AccueilView() }` : le conteneur racine qui héberge la
  première vue.

### `Scan3D/Features/Accueil/AccueilView.swift`

**Rôle** : écran d'accueil : « Prêt à scanner » + bouton « Nouveau scan » si
`ObjectCaptureSession.isSupported`, sinon « Appareil non compatible ».

- `struct AccueilView: View` + `var body: some View` (§8) : le composant
  fonction. `some View` = « je renvoie *une* vue, peu importe laquelle »
  (type opaque, sans équivalent TS direct).
- `NavigationStack` ≈ un Stack navigator expo-router ;
  `.navigationTitle(...)` = option `title` de l'écran. Modificateurs chaînés
  (§8, l'ordre compte).
- `Group { if ... else ... }` : `if` **directement dans la vue** (pas de
  ternaire JSX) ; `Group` permet d'appliquer un modificateur commun aux deux
  branches.
- `ContentUnavailableView` : composant système iOS 17+ (icône + titre +
  description), accessible d'office pour VoiceOver.
- `private var appareilCompatible: Bool { ... }` : propriété calculée privée
  (§10) qui isole la dépendance matériel.
- `#if targetEnvironment(simulator)` : condition **à la compilation** — le
  code de l'autre branche n'existe pas dans le binaire. Plus fort que
  `Platform.OS` (runtime) ; c'est ce que `CLAUDE.md` exige pour tout le code
  Object Capture.
- `#Preview { AccueilView() }` ≈ une story Storybook, rendue dans le canvas
  Xcode.
- `.fullScreenCover(isPresented: $nouveauScan)` piloté par un `@State`
  booléen : la présentation modale plein écran ≈ un `router.push` vers un
  écran sans retour par glissement (tranche 1, étape 1).

## Tranche 1 — étape 1 : parcours, préparation, permission, stockage

Ajoutés le 13/09/2026. Convention : identifiants **anglais** dans
`Scan3DCore`, **français** dans l'app.

### `Packages/Scan3DCore/Sources/Scan3DCore/Scan/ScanPhase.swift`

**Rôle** : la machine à états du parcours ; l'UI ne change de phase que via
`transition(to:)`, qui refuse les sauts interdits.

- `enum` à valeurs associées (§4) : `reconstruction(progress:)`,
  `preview(model:)`, `failed(message:)`.
- `switch (self, target)` sur un **tuple**, plusieurs motifs par `case`, un
  `default` : la table des transitions se lit comme une liste.
- `throws(ScanPhaseError)` (§6) + `guard` (§2) — même recette que
  `ScaleCalibration`.
- Propriété calculée `cancellationNeedsConfirmation` avec `switch` exhaustif.

### `Packages/Scan3DCore/Sources/Scan3DCore/Scan/ScanLayout.swift`

**Rôle** : les URL d'un scan à partir d'une racine et d'un UUID — zéro accès
disque, donc testable sur Mac.

- `struct` (§3) `Identifiable` ; `static let` pour les noms de dossiers,
  constantes partagées avec l'app.
- `URL.appending(path:directoryHint:)` : dire à Foundation si c'est un dossier
  évite les bugs de « / » final.
- Argument avec valeur par défaut `id: UUID = UUID()` (≈ paramètre par défaut
  TS).

### `Packages/Scan3DCore/Sources/Scan3DCore/Scan/DiskSpacePolicy.swift`

**Rôle** : seuil d'espace libre (2 Gio) et calcul du manque pour le message.

- Enum-namespace comme `Units` ; `Int64` pour des octets ; `max(0, …)`.

### `Packages/Scan3DCore/Tests/Scan3DCoreTests/ScanPhaseTests.swift` et `ScanStorageTests.swift`

**Rôle** : 10 tests — parcours nominal, sauts interdits, sources d'échec,
reprise, confirmation d'annulation, arborescence, seuil disque.

- Tableaux de **tuples** en `arguments:` (`[(ScanPhase, ScanPhase)]`),
  destructurés dans les paramètres du test : `test.each` à plusieurs colonnes.
- `static let` dans une suite pour partager des fixtures, référencées
  qualifiées (`ScanPhaseTests.sautsInterdits`) dans l'attribut.
- `pathComponents` plutôt que comparer des chaînes d'URL.

### `Scan3D/App/Journal.swift`

**Rôle** : les `Logger` de l'app par domaine (`scan`, `stockage`).

- `extension Logger` avec `static let` : ajouter des membres à un type d'Apple
  (§5). `??` identique à TS.

### `Scan3D/Features/Scan/ScanStore.swift`

**Rôle** : crée et supprime `Application Support/Scans/<UUID>/`, protégé
`.complete` et exclu d'iCloud ; mesure l'espace disque (raison E174.1).

- **`actor`** (§9) : une classe dont les méthodes s'exécutent en série, hors du
  fil principal, appelée avec `await`. C'est la brique de Swift 6 pour l'état
  partagé sans course de données.
- `URLResourceValues` : struct à muter puis `setResourceValues`, d'où
  `var url = url` — copie locale (§3).
- `try?` : convertit une erreur en `nil` (acceptable pour un journal, jamais
  pour de la logique).
- `switch` avec **motifs de cast** `case let type as FileProtectionType`.

### `Scan3D/Features/Scan/CameraAuthorization.swift`

**Rôle** : statut caméra en trois valeurs, demande au premier scan.

- Enum imbriqué `Statut` ; `switch` sur une enum d'Apple avec
  `@unknown default` (garde-fou si un futur iOS ajoute un cas).
- `static func demander() async` : `await` sur une API Apple.

### `Scan3D/Features/Scan/ScanFlowModel.swift`

**Rôle** : le store du parcours (phase, autorisation, dossier, erreur), seul
autorisé à changer la phase.

- `@MainActor @Observable final class` (§8, §9) ; `private(set) var` =
  lecture publique, écriture privée.
- `defer { }` : exécuté à la sortie de la fonction quel que soit le chemin
  (≈ `finally`).
- `do { } catch let e as ScanPhaseError { } catch { }` : attraper une erreur
  typée, puis le reste (§6).
- `LocalizedError` + `errorDescription` : l'erreur porte son propre message
  utilisateur.

### `Scan3D/Features/Scan/ScanFlowView.swift`

**Rôle** : conteneur du parcours — `switch` sur la phase → sous-vue, Annuler
avec confirmation, alerte d'erreur.

- `@State` pour posséder le modèle (§8), `@Environment(\.dismiss)` et
  `(\.scenePhase)`.
- `@ViewBuilder` sur une propriété calculée contenant `if` / `switch`.
- `Binding(get:set:)` construit à la main : pont entre un optionnel et un
  booléen.
- `Task { await … }` depuis un bouton.

### `Scan3D/Features/Scan/PreparationView.swift`

**Rôle** : la checklist (écran 2) et le bouton « Commencer le scan ».

- `List` / `Section` / `ForEach` sur une enum `CaseIterable & Identifiable`
  imbriquée dans la vue.
- `.safeAreaInset(edge: .bottom)` pour un bouton ancré ; `Set<Conseil>` pour
  les cases cochées.
- Accessibilité : `accessibilityValue`, `accessibilityHint`.

### `Scan3D/Features/Scan/CameraRefuseeView.swift`

**Rôle** : écran de refus caméra (lien Réglages). (Le
`DetectionPlaceholderView` de l'étape 1 a été remplacé par `CaptureView` à
l'étape 2.)

- `ContentUnavailableView` avec `actions:` ; `if let` sur une URL optionnelle
  (§2) ; `Link`.

## Tranche 1 — étape 2 : capture guidée

Ajoutés le 13/09/2026.

### `Packages/Scan3DCore/Sources/Scan3DCore/Capture/CaptureHint.swift`

**Rôle** : les 9 conseils de capture, miroir neutre des `Feedback` de
RealityKit, avec leur priorité d'annonce.

- L'**ordre de déclaration** d'une enum `CaseIterable` sert de priorité :
  `allCases.firstIndex(of:)`.
- `Set<CaptureHint>` + `min(by:)` pour choisir le plus urgent.
- Tests `CaptureHintTests.swift` : vérifient aussi que les priorités sont
  uniques et consécutives (0…8).

### `Scan3D/Features/Capture/CaptureController.swift`

**Rôle** : possède l'unique `ObjectCaptureSession`, la démarre, la commande,
la libère, et traduit ses états en événements pour le modèle.

- `#if !targetEnvironment(simulator)` autour du fichier entier.
- **Cross-import overlay** : `import RealityKit` **et** `import SwiftUI`
  obligatoires pour voir `ObjectCaptureSession`.
- `for await etat in session.stateUpdates` (§9) dans un
  `Task { [weak self] in … }` : consommer un flux d'événements, comme un
  `for await` sur un `AsyncIterable` TS ; `[weak self]` évite que la tâche
  retienne le contrôleur en vie.
- `for await … where complete` : filtre directement dans la boucle.
- `@unknown default` sur les enums de RealityKit (le framework peut ajouter
  des cas).
- `init?(_:)` : initialiseur **échouable** (renvoie `nil`), utilisé avec
  `compactMap`.
- `try? await Task.sleep(for: .milliseconds(250))` : attente non bloquante.

### `Scan3D/Features/Capture/CaptureView.swift`

**Rôle** : écrans 3 et 4 — `ObjectCaptureView` en fond, bandeau de conseil,
commandes selon `session.state`.

- `ZStack(alignment: .bottom)` + `.ignoresSafeArea()` seulement sur la
  caméra, pour que les boutons restent au-dessus de l'indicateur d'accueil.
- `switch` dans une fonction `@ViewBuilder` sur l'état de la session.
- `.sensoryFeedback(.warning, trigger:condition:)` : haptique déclarative
  (iOS 17).
- `AccessibilityNotification.Announcement(…).post()` : annonce VoiceOver.
- `static let` sur une vue pour une constante de réglage.

### `Scan3D/Features/Capture/FinDePasseView.swift`

**Rôle** : écran 5 — nuage de points capturé + trois choix.

- `ObjectCapturePointCloudView(session:)` ; `if / else` dans la vue pour
  masquer « Retourner » quand RealityKit le déconseille.

### `Scan3D/Features/Capture/CaptureSimulateur.swift`

**Rôle** : doublures (`CaptureController`, `CaptureView`, `FinDePasseView`)
sous `#if targetEnvironment(simulator)`, même interface que les vrais types.

- Deux déclarations du même type dans deux fichiers, jamais compilées
  ensemble : c'est le `#if` qui garantit l'unicité.

### `Scan3D/Features/Capture/CaptureHint+Texte.swift` et `VeilleEcran.swift`

- `extension` d'un type de Core pour y ajouter de l'UI (les textes) sans
  polluer Core ; `@MainActor enum` avec `static func` pour
  `isIdleTimerDisabled`.

### `Scan3D/Features/Scan/EchecView.swift`

- Vue « feuille » avec closure en paramètre (`let fermer: () -> Void`)
  ≈ prop callback. (Le `ReconstructionPlaceholderView` provisoire de cette
  étape a été remplacé par `ReconstructionView` à l'étape 3.)

### Modifiés à l'étape 2

- `ScanFlowModel.swift` — événements du contrôleur → transitions, mesure des
  photos (`bilanCapture`).
- `ScanFlowView.swift` — titre par phase, nouvelles sous-vues, `onDisappear`.
- `ScanStore.swift` — `tailleImages` : `FileManager.enumerator` et
  `for case let url as URL` (boucle avec motif de cast).

## Tranche 1 — étape 3 : reconstruction

Ajoutés le 14/09/2026.

### `Packages/Scan3DCore/Sources/Scan3DCore/Reconstruction/ReconstructionProgress.swift`

**Rôle** : transforme fraction et secondes restantes en textes (« 42 % »,
« environ 2 min », phrase VoiceOver).

- Enum imbriquée `RemainingTime` avec valeurs associées, dont une étiquetée
  `hours(Int, minutes: Int)`.
- `rounded(.up)` : arrondi vers le haut ; `\u{00A0}` : espace insécable.
- **Piège rencontré** : un `switch` dont un cas déclare une variable
  (`let heures = …`) cesse d'être une *expression* ; tous les cas doivent
  alors écrire `return`.
- Test paramétré avec des optionnels :
  `[(Double?, RemainingTime?)]` et un `as` pour guider l'inférence de type.

### `Scan3D/Features/Reconstruction/Reconstructor.swift`

**Rôle** : possède la `PhotogrammetrySession`, la lance, la surveille,
l'annule, et traduit ses sorties en événements.

- `for try await sortie in session.outputs` : flux asynchrone qui peut
  lever une erreur (≈ `for await` dans un `try/catch`).
- `if case .modelFile(let url) = resultat` : extraire une valeur associée
  sans `switch` complet.
- `erreur as? PhotogrammetrySession.Error` : cast conditionnel (≈ `instanceof`
  qui renvoie un optionnel).
- `info.processingStage.map(Self.texte)` : `map` sur un **optionnel** (appelé
  seulement s'il y a une valeur).
- `#if … #else … #endif` dans un seul fichier : vrai type et doublure
  simulateur côte à côte.

### `Scan3D/Features/Reconstruction/ReconstructionView.swift`

**Rôle** : écran 6 — barre, pourcentage, étape, temps restant.

- `ProgressView(value:label:currentValueLabel:)` ; `let` locaux dans `body`
  pour calculer une fois.
- `.accessibilityValue` pour la phrase, `.accessibilityHidden(true)` pour ne
  pas lire deux fois la même information.

### `Scan3D/Features/Scan/EchecView.swift` (modifié à l'étape 3)

- Paramètre optionnel de type fonction avec valeur par défaut
  `var reprendre: (() -> Void)? = nil` ≈ prop callback facultative.
  (L'`ApercuPlaceholderView` provisoire de l'étape 3 a été remplacé par
  `ApercuView` à l'étape 4.)

### Modifiés à l'étape 3

- `ScanFlowModel.swift` — `reprendreReconstruction() async`, drapeau
  `annulationEnCours` + `defer` pour le remettre à faux, propriété calculée
  `scanTermine` avec `if case … { true } else { false }` en expression.
- `ScanFlowView.swift` — bouton de barre conditionnel (« Fermer » / « Annuler »).
- `ScanStore.swift` — boucle `for … where` pour ne supprimer que les
  dossiers présents.

## Tranche 1 — étape 4 : aperçu et dimensions

Ajoutés le 14/09/2026.

### `Packages/Scan3DCore/Sources/Scan3DCore/Mesh/Mesh.swift`

**Rôle** : le maillage triangulaire validé une fois pour toutes (positions
en mètres, indices, boîte englobante), avec un plafond de triangles.

- `SIMD3<Float>` : vecteur 3D natif, avec `pointwiseMin` / `pointwiseMax`
  (≈ `Math.min` composante par composante).
- `init(...) throws(MeshError)` : **initialiseur qui peut échouer en levant
  une erreur** — impossible d'obtenir un `Mesh` invalide.
- Paramètre par défaut qui référence une constante du type
  (`maximumTriangleCount: Int = Mesh.maximumTriangleCount`) : les tests
  passent un petit plafond sans fabriquer des millions de triangles.
- `allSatisfy` ≈ `Array.prototype.every`.

### `Packages/Scan3DCore/Sources/Scan3DCore/Mesh/MeshLoader.swift`

**Rôle** : lit un fichier 3D avec Model I/O et le fusionne en un `Mesh`,
transformations comprises, avec lecture bornée des tampons.

- **Pointeurs bruts** : `dataStart.loadUnaligned(fromByteOffset:as:)` lit
  un `Float` à un décalage donné (≈ `DataView.getFloat32` en JS).
- `withExtendedLifetime(objet) { … }` : garantit que l'objet qui « mappe »
  le tampon vit pendant la lecture (sans lui, le compilateur pourrait le
  libérer avant la fin — un piège sans équivalent en JS).
- `inout` : paramètre modifié en place (`dans positions: inout [...]`,
  appelé avec `&positions`).
- Closure à erreur typée : `{ () throws(MeshError) in … }`.
- `UInt32(exactly:)` : conversion qui renvoie `nil` au lieu de déborder.
- `NSErrorPointer` : `var erreur: NSError?` passé en `&erreur`, héritage
  d'Objective-C quand une API n'est pas importée en `throws`.
- `static func` **interne** (sans `public`) + `@testable import` : les
  tests y accèdent, l'app non.

### `Packages/Scan3DCore/Sources/Scan3DCore/Mesh/Dimensions.swift`

**Rôle** : cotes en mm (longueur ≥ largeur, hauteur selon Y), plausibilité,
et textes pour l'écran et VoiceOver.

- Deux initialiseurs, dont un qui **délègue** à l'autre (`self.init(...)`).
- `max(a, b, c)` variadique ; `ClosedRange.contains`.
- `FormatStyle` : `valeur.formatted(.number.precision(.fractionLength(1)).grouping(.never).locale(locale))`
  ≈ `Intl.NumberFormat` avec options chaînées.

### `MeshTests.swift` et `DimensionsTests.swift`

- Fabrication d'assets Model I/O en mémoire (`MDLMesh(boxWithExtent:...)`,
  `MDLObject`, `MDLTransform(matrix:)`) : les tests d'unités ne dépendent
  d'aucun fichier ni d'aucun iPhone.
- `defer { try? FileManager.default.removeItem(at:) }` pour nettoyer le
  fichier temporaire de l'aller-retour USD.

### `Scan3D/Features/Apercu/ApercuView.swift`

**Rôle** : écran 7 — cotes en mm, avertissement si l'échelle paraît fausse,
« Voir en 3D » (Quick Look) et « Terminer ».

- `switch` sur un enum dans une `List` (états `enCours` / `reussie` /
  `echec`) ≈ rendu conditionnel sur un état de requête (`isLoading` /
  `data` / `error`).
- `LabeledContent` : ligne « libellé — valeur » adaptée à Dynamic Type et
  VoiceOver.
- `.quickLookPreview($url)` piloté par un `@State` optionnel ;
  `import QuickLook` obligatoire.
- `.onChange(of:initial: true)` : réagit aussi à la valeur présente au
  premier affichage (≈ `useEffect` avec la valeur initiale).

### Modifiés à l'étape 4

- `ScanFlowModel.swift` — enum imbriqué `MesureModele`, lecture dans
  `Task.detached(priority: .userInitiated) { … }.value` : travail lourd hors
  du fil principal, résultat `Sendable` rapporté sur le `@MainActor`.
- `ScanFlowView.swift` — `case .preview(let modele)` : extraction de la
  valeur associée directement dans le `switch`.

## Tranche 1 — étape 5 : export STL

Ajoutés le 15/09/2026.

### `Packages/Scan3DCore/Sources/Scan3DCore/Export/STLWriter.swift`

**Rôle** : transforme un `Mesh` en fichier STL binaire en millimètres
(en-tête, nombre de triangles, normale + 3 sommets + attribut par triangle).

- `Data(capacity:)` + `append` ≈ un `ArrayBuffer` qu'on remplit.
- `withUnsafeBytes(of: valeur.littleEndian)` : les octets bruts d'un nombre,
  dans l'ordre imposé par le format (≈ `DataView.setUint32(…, true)`).
- `Float.bitPattern` : les 32 bits d'un flottant, sans conversion.
- `stride(from:to:by:)` ≈ `for (let i = 0; i < n; i += 3)`.
- `cross` / `length` de `simd` : produit vectoriel et norme.
- `static let header: Data = { … }()` : constante calculée une seule fois
  par une closure immédiatement exécutée (≈ IIFE).

### `Packages/Scan3DCore/Sources/Scan3DCore/Export/ExportFilename.swift`

**Rôle** : nom de fichier daté « Scan3D-2026-09-15-14h32.stl ».

- `Calendar(identifier: .gregorian)` + `timeZone` injectable : le test fixe
  le fuseau pour un résultat déterministe (≈ figer `Date` dans Vitest).

### `STLWriterTests.swift`

- Relecteur STL minimal écrit dans le test (`STLRelu`) : on vérifie les
  octets produits, pas seulement l'absence d'erreur.
- `#require` : comme `#expect`, mais arrête le test si la condition échoue
  (≈ `expect(...)` suivi d'un `return`).
- Tuples nommés dans un tableau : `(normale: …, sommets: …, attribut: …)`.

### `Scan3D/Features/Export/STLExporter.swift`

**Rôle** : écrit le STL dans `tmp/Export/`, protégé, et le supprime sur
demande.

- Troisième `actor` de l'app (après `ScanStore`) : les écritures disque ne
  bloquent jamais l'interface.
- `Data.write(to:options: [.atomic, .completeFileProtection])` : écriture
  atomique et classe de protection posée en une ligne.
- `URL.temporaryDirectory` : dossier temporaire de l'app (jamais sauvegardé
  dans iCloud, vidé par le système).

### `Scan3D/Features/Export/FeuilleDePartage.swift`

**Rôle** : ouvre la feuille de partage iOS et prévient à sa fermeture.

- **Pont UIKit** : `UIActivityViewController` présenté à la main depuis
  l'écran visible (`connectedScenes` → `keyWindow` → `rootViewController` →
  `presentedViewController`), faute d'équivalent SwiftUI avec rappel.
- Closure `@escaping @MainActor` : le rappel s'exécute sur le fil de
  l'interface ; `Task { @MainActor in … }` pour y revenir depuis un rappel
  UIKit non isolé.
- `if let popover = …` : l'optionnel n'existe que sur iPad.

### Modifiés à l'étape 5

- `ApercuView.swift` — bouton d'export avec `Group { if … ProgressView …
  else Label … }`, alerte liée par `Binding(get:set:)`, fonction `async`
  privée appelée depuis `Task { await exporter() }`.
- `ScanFlowModel.swift` — `private(set) var maillage: Mesh?`, export avec
  `defer` pour relâcher l'indicateur quel que soit le chemin.
- `Journal.swift` — catégorie `export`.

## Tranche 2 — étape 1 : bibliothèque des scans

Ajoutés le 15/09/2026. `ApercuView.swift` (tranche 1) devient
`DetailScanView.swift` ; `ScanFlowModel` perd la mesure et l'export.

### `Packages/Scan3DCore/Sources/Scan3DCore/Library/ScanRecord.swift`

**Rôle** : la fiche d'un scan (`scan.json`) — nom, date, cotes brutes,
nombre de triangles, calibrage — et sa validation au décodage.

- `Codable` écrit à la main (`init(from:)`, `encode(to:)`) ≈ un schéma zod
  appliqué au `JSON.parse` : chaque champ est vérifié, un fichier piégé est
  refusé au lieu de produire un objet incohérent.
- `CodingKeys` : enum qui fixe le nom des clés JSON.
- `public private(set) var name` : lisible partout, modifiable seulement par
  `rename(to:)`, qui valide (≈ un setter privé).
- `mutating func` : méthode qui modifie une `struct` (§3) ; il faut une
  copie `var` pour l'appeler.
- `unicodeScalars` et `properties.generalCategory` : le texte vu comme des
  points de code Unicode, pour retirer les caractères de contrôle ;
  `String.count` compte, lui, les caractères visibles (un émoji = 1).
- Décodage en deux temps (`VersionSeule`, puis la fiche) : on lit la version
  avant de supposer la structure.

### `Packages/Scan3DCore/Sources/Scan3DCore/Library/ScanLibrary.swift`

**Rôle** : classe les dossiers de `Scans/` (complet, sans fiche, fiche
invalide, illisible, version future, incomplet) et lit / écrit les fiches.

- `enum` avec valeurs associées (`complete(ScanRecord)`,
  `newerRecord(version:)`) : un état = un cas, chacun avec ses données (§4).
- `do throws(ScanRecordError) { … } catch { switch error … }` : le `catch`
  reçoit une erreur typée, le `switch` est vérifié à la compilation.
- `FileHandle.read(upToCount:)` : lecture bornée, la taille annoncée du
  fichier n'est jamais crue.
- Paramètre par défaut sécurisé (`options: [.atomic, .completeFileProtection]`)
  que seuls les tests remplacent.

### `ScanLibraryTests.swift`

- `struct DossierTemporaire: ~Copyable` avec `deinit` : un type **non
  copiable** qui supprime son dossier en fin de test (≈ `afterEach`, mais
  garanti par le compilateur).
- Chaînes brutes `#"…"#` et interpolation `\#(valeur)` : du JSON écrit à la
  main sans échapper les guillemets.
- `@Test(arguments:)` sur des `Data` : un même test pour dix fichiers piégés.

### Modifiés dans `Scan3DCore`

- `Dimensions.swift`, `ScaleCalibration.swift` — conformes à `Codable`,
  décodage revalidé (cote négative, facteur hors ±20 % → refus).
  `ScaleCalibration` garde désormais les deux cotes d'origine.
- `ScanLayout.swift` — `recordFile` (`scan.json`) ; `Hashable`, pour servir
  de valeur de navigation.

### `Scan3D/Features/Bibliotheque/BibliothequeModel.swift`

**Rôle** : la liste des scans et les actions qui la modifient (charger,
renommer, supprimer) ; au premier chargement, purge les captures
interrompues et récupère les scans de la tranche 1.

- `throws(BibliothequeErreur)` sur une méthode `async` : l'écran sait
  exactement quelles erreurs attendre.
- **Réentrance** : après un `await`, l'état a pu changer (la liste a été
  rechargée) ; on recherche l'élément au lieu de réutiliser un index.
- `Dictionary(_:uniquingKeysWith:)` plutôt que `uniqueKeysWithValues`, qui
  arrête l'app sur une clé en double.

### `Scan3D/Features/Bibliotheque/BibliothequeView.swift`

**Rôle** : la liste (nom, cotes, date, « Calibré »), glisser pour
supprimer avec confirmation, « Nouveau scan » ; vide → « Prêt à scanner ».

- `NavigationLink(value:)` : la ligne pousse une **valeur** ; l'écran
  correspondant est déclaré ailleurs (`navigationDestination`).
- `.swipeActions` : actions de glissement, reprises automatiquement dans le
  rotor VoiceOver.
- `confirmationDialog(…, presenting:)` : la feuille reçoit l'élément à
  supprimer.
- `private struct LigneScan` : sous-composant local au fichier.

### `Scan3D/Features/Bibliotheque/ScanRecord+Texte.swift`

**Rôle** : dates affichées (« 15 sept. 2026 à 14:32 ») et phrase VoiceOver
d'une ligne.

- `extension` d'un type de `Scan3DCore` dans l'app : on ajoute des
  propriétés sans toucher au paquet (≈ fonctions utilitaires colocalisées).
- `Date.FormatStyle(date:time:locale:)` : format de date localisé.

### `Scan3D/Features/DetailScan/DetailScanModel.swift`

**Rôle** : lecture du maillage et export STL d'un scan (repris de
`ScanFlowModel`).

- Même structure que les autres modèles `@MainActor @Observable` ; le
  maillage est lu par `ScanStore` (hors du fil de l'interface).

### `Scan3D/Features/DetailScan/DetailScanView.swift`

**Rôle** : cotes, « Voir en 3D », « Exporter en STL », renommer (alerte
avec champ texte), supprimer (confirmation).

- `init` + `_model = State(initialValue:)` : un `@State` qui dépend d'un
  paramètre (≈ `useState(() => …)`).
- `.alert { TextField … }` : saisie dans une alerte ; `.onChange(of:)` borne
  la longueur pendant la frappe.
- `@State ficheFigee` : garde le contenu affiché pendant l'animation de
  retour après une suppression.

### Modifiés à l'étape 1

- `AccueilView.swift` — `NavigationStack(path: $chemin)` : la pile de
  navigation est un tableau d'état ; `.navigationDestination(for:)` ;
  `.fullScreenCover(…, onDismiss:)` pour ouvrir le détail une fois le
  parcours refermé.
- `ScanFlowView.swift` — `init(store:termine:)` et rappel `termine` (≈ une
  prop `onDone`) ; se ferme seul quand `scanEnregistre` change.
- `ScanFlowModel.swift` — `enregistrer()` : fiche puis nettoyage des photos.
- `ScanStore.swift` — `inventaire()`, `purger(_:)`, `lireMaillage(_:)`,
  `creerFiche(pour:nom:date:)`, `ecrireFiche(_:dans:)`.
- `PreparationView.swift` (aperçu Xcode), `FeuilleDePartage.swift`
  (commentaire).

## Tranche 2 — étape 2 : visionneuse et mesure point à point

Ajoutés le 16/09/2026. La caméra, le rayon et l'intersection sont dans
`Scan3DCore` : c'est ce qui rend la mesure testable sur Mac.

### `Packages/Scan3DCore/Sources/Scan3DCore/Measure/Ray.swift`

**Rôle** : une demi-droite (œil + direction) dans le repère du maillage.

- `init?` : un initialiseur qui peut échouer (direction nulle ou non finie).
  ≈ une fonction qui renvoie `null` plutôt que de laisser passer un `NaN`.
- Direction normalisée une fois pour toutes : les distances renvoyées sont
  ensuite directement des mètres.

### `Packages/Scan3DCore/Sources/Scan3DCore/Measure/MeshPicking.swift`

**Rôle** : `Mesh.firstIntersection(with:)` — où le rayon touche la surface,
par l'algorithme de Möller-Trumbore.

- `extension Mesh` : on ajoute une méthode à un type existant, dans un autre
  fichier (≈ étendre un objet sans le modifier).
- `withUnsafeBufferPointer` : parcours du tableau **sans vérification de
  bornes**, légitime ici car `Mesh.init` a déjà validé chaque indice. C'est
  l'exception qui confirme la règle : on ne coupe les contrôles qu'après les
  avoir faits ailleurs.
- `simd_cross`, `simd_dot` : produits vectoriel et scalaire.

### `Packages/Scan3DCore/Sources/Scan3DCore/Measure/OrbitCamera.swift`

**Rôle** : la caméra qui tourne autour de l'objet, et la conversion
« point de l'écran → rayon » (et l'inverse).

- `struct` avec `private(set) var` : la pose se modifie par des méthodes
  (`turn`, `zoom`, `frame`) qui bornent les valeurs, jamais en écrivant
  directement dans les champs.
- `mutating func` sur une valeur (§3), trigonométrie `sin` / `cos` / `tan`.
- Tuple nommé renvoyé par `basis` : `(forward:, right:, up:)`.
- `SIMD2<Float>` pour les points d'écran : le paquet reste indépendant de
  CoreGraphics (donc utilisable tel quel sur Mac en tranche 4).

### `Packages/Scan3DCore/Sources/Scan3DCore/Measure/SegmentMeasurement.swift`

**Rôle** : la distance entre les deux points posés, en mm.

### `MeasureTests.swift`

- Un test **de bout en bout** dans `Scan3DCore` : caméra cadrée sur un cube,
  rayon au centre de l'écran, intersection, puis demi-tour et nouvelle
  mesure → 50,0 mm. Toute la chaîne de mesure est vérifiée sans iPhone.
- Test de performance avec `ContinuousClock.now` et une grille de 51 200
  triangles (6,8 ms, sans optimisation).
- `#require` ne s'imbrique pas : chaque valeur optionnelle se déballe sur sa
  propre ligne (erreur « recursive expansion of macro » sinon).

### `Scan3D/Features/Visionneuse/MesureModel.swift`

**Rôle** : la scène RealityKit (modèle recalé, caméra, lumière, marqueurs) et
l'état de la mesure.

- **Entités RealityKit** : des objets de référence qu'on modifie en place
  (`camera.look(at:from:)`, `marqueurs.children.removeAll()`), à l'opposé
  d'une vue SwiftUI recalculée à chaque rendu.
- `ModelEntity(mesh: .generateSphere(radius:), materials: [UnlitMaterial(…)])`
  — un matériau « non éclairé » garde sa couleur quel que soit l'angle.
- `simd_quatf(from:to:)` pour orienter le trait, avec le cas « exactement à
  l'opposé » traité à part (sinon le quaternion renvoie des `NaN`).
- `switch (pointA, pointB)` sur un **tuple d'optionnels** : les trois cas
  (premier point, second point, nouvelle mesure) en une seule expression.

### `Scan3D/Features/Visionneuse/VisionneuseView.swift`

**Rôle** : la `RealityView`, les gestes et le panneau de résultat.

- `RealityView { contenu in … }` : la fermeture reçoit la scène une fois, à
  l'ouverture ; tout le reste se pilote par les entités.
- Trois gestes composés : `.gesture(toucher)`, puis deux
  `.simultaneousGesture` (tourner, zoomer) pour qu'aucun n'annule les autres.
- Un glissement donne une translation **absolue** depuis son début : on
  mémorise la précédente pour en déduire le déplacement (même chose pour le
  pincement).
- `.accessibilityDirectTouch(options: .requiresActivation)` : VoiceOver garde
  ses gestes tant que l'utilisateur n'a pas activé la zone 3D.

### Modifiés à l'étape 2

- `DetailScanView.swift` — bouton « Mesurer » et `fullScreenCover` vers la
  visionneuse.
- `Journal.swift` — catégorie `mesure`.

## Tranche 2 — étape 3 : calibrage par scan

Ajoutés le 17/09/2026. Le calibrage corrige l'**échelle** d'un scan à partir
d'une cote connue, et se range dans `scan.json` (décision E2).

### `Packages/Scan3DCore/Sources/Scan3DCore/MillimeterInput.swift`

**Rôle** : transformer une cote tapée au clavier en nombre — ou la refuser.

- Une seule règle explicite plutôt que `Double(texte)`, qui accepterait
  « 1e3 », « -0 » ou « inf ». C'est le principe de la validation d'entrée :
  autoriser une forme connue, pas interdire une liste de formes connues.
- `Character.isASCII` : écarte les chiffres d'autres écritures et les
  caractères « numériques » comme ½, que `Double` ne sait pas lire.
- `filter { !$0.isWhitespace }` : les espaces insécables du formatage
  français (« 1 234,5 ») passent sans effort.

### `Packages/Scan3DCore/Sources/Scan3DCore/CalibrationReference.swift`

**Rôle** : les cotes de référence proposées (carte bancaire, deux côtés).

- `enum` à valeurs brutes, `CaseIterable` : la liste se parcourt dans un
  `ForEach` sans jamais écrire les cas à la main dans la vue.

### Modifiés dans `Scan3DCore`

- `Dimensions.scaled(by:)` — cotes corrigées, sans toucher aux brutes.
- `ScanRecord.calibratedDimensions` — ce que l'écran affiche ; la fiche, elle,
  garde les cotes brutes, donc un calibrage s'annule sans rien perdre.
- `SegmentMeasurement.lengthMM(calibratedBy:)` — la mesure suit le calibrage.
- `STLWriter.binaryData(for:scale:)` — le fichier exporté porte les cotes
  affichées ; un facteur nul ou non fini lève `STLError.invalidScale`.

### `Scan3D/Features/Calibrage/CalibrageView.swift`

**Rôle** : la feuille de calibrage — cote de référence, aperçu, application ou
réinitialisation.

- Deux `enum` privés : `Choix` (ce que l'utilisateur sélectionne, avec une
  valeur associée) et `Etat` (ce que l'écran peut proposer : à compléter,
  prêt, problème). L'état est **calculé** à chaque rendu depuis la saisie,
  jamais stocké — pas de risque qu'il se désynchronise (≈ dériver l'état plutôt
  que le dupliquer dans un `useState`).
- `Picker` avec `.tag(...)` sur un enum : la sélection est typée.
- `Text("… corrige une **échelle** …")` : SwiftUI interprète le Markdown des
  chaînes littérales.
- `.strikethrough()` sur les anciennes cotes : l'avant/après se lit d'un coup.
- Bouton « Appliquer » désactivé tant que l'état n'est pas `.pret` : l'erreur
  est impossible plutôt que signalée après coup.

### Modifiés à l'étape 3

- `VisionneuseView.swift` — bouton « Calibrer avec cette mesure » et feuille ;
  la distance affichée est la cote calibrée.
- `MesureModel.swift` — porte le calibrage, expose la distance brute (pour
  calibrer) et la distance calibrée (pour l'afficher).
- `DetailScanView.swift` — cotes calibrées, ligne « Calibré sur … → … »,
  réinitialisation, export à l'échelle.
- `BibliothequeModel.swift` — `calibrer(_:_:)`, écriture de fiche factorisée
  avec le renommage.
- `STLExporter.swift`, `DetailScanModel.swift` — paramètre d'échelle.

### `Packages/Scan3DCore/Sources/Etalon/main.swift`

**Rôle** (tranche 2, étape 5) : écrit `build/etalon-cube-50mm.stl`, le cube de
50 mm qui sert d'étalon à la campagne de mesure.

- Deuxième **cible** du paquet, exécutable celle-ci (`.executableTarget`) :
  l'app iOS ne dépend que de la bibliothèque, l'outil ne tourne que sur Mac.
- Un fichier `main.swift` s'exécute de haut en bas, sans `struct` ni `@main`.
- `CommandLine.arguments` pour le chemin de sortie, `exit(1)` en cas d'échec.
- Le cube est décrit par 8 sommets et 12 triangles, orientés dans le sens
  trigonométrique vu de l'extérieur pour que les normales pointent dehors.

## Tranche 3 — étape 1 : mesure de face à face

Ajoutés le 19/09/2026. On ne vise plus un point, on désigne une **face** : le
plan s'appuie sur des dizaines de triangles, donc la mesure ne dépend plus du
millimètre près où le doigt s'est posé.

### `Packages/Scan3DCore/Sources/Scan3DCore/Measure/TriangleGeometry.swift`

**Rôle** : le point d'un triangle le plus proche d'un point donné.

- Algorithme d'Ericson : on teste les trois sommets, les trois arêtes, puis
  l'intérieur — une suite de `if` dont chaque test élimine une région.
- `enum` sans cas, seulement des fonctions statiques : un espace de noms, pas
  un type que l'on instancie (§4 de `SWIFT-POUR-TS.md`).

### `Packages/Scan3DCore/Sources/Scan3DCore/Measure/PlaneFit.swift`

**Rôle** : ajuster un plan sur la surface autour du point touché — ou refuser.

- La normale est la **somme des produits vectoriels** des triangles retenus.
  Chaque produit vaut deux fois l'aire du triangle : la somme pondère donc par
  l'aire sans qu'on l'écrive. Sa longueur, comparée à la somme des aires, donne
  la « cohérence » — un pli fait s'annuler les normales, et l'arête est écartée.
- Deux surcharges de `fitPlane` : l'une prend un rayon, l'autre en essaie
  plusieurs (surcharge de méthode, §7).
- `guard … else { return nil }` en cascade : chaque condition de refus est
  lisible sur une ligne.

### `Packages/Scan3DCore/Sources/Scan3DCore/Measure/SurfaceMeasurement.swift`

**Rôle** : décider **ce que la mesure veut dire** — épaisseur, point à face, ou
point à point — et le dire.

- `switch` sur un **couple d'enums** avec clauses `where` : les trois
  sémantiques tiennent dans une seule expression, et le compilateur vérifie
  qu'aucun cas ne manque.
- Un type qui en enveloppe un autre : `SurfaceMeasurement` ajoute le sens,
  `SegmentMeasurement` garde la géométrie. Aucun code dupliqué.

### `Scan3D/Features/Visionneuse/SurfaceMeasurement+Texte.swift`

**Rôle** : les libellés (« Épaisseur entre deux faces », « Face A posée »).

- Même partage que `CaptureHint+Texte.swift` : `Scan3DCore` décide de la
  géométrie, l'app décide des mots — et l'accord du participe change selon
  qu'on a posé un point ou une face.

### Modifiés à l'étape 1

- `MesureModel.swift` — des **cibles** (point ou face) au lieu de points ; un
  disque posé à plat pour une face ; la rotation d'un axe vers un autre est
  factorisée entre le disque et le trait.
- `VisionneuseView.swift` — le libellé de la mesure sous la distance.

## Les fichiers non-Swift

- `project.yml` — source de vérité du `.xcodeproj` (jamais éditer ce
  dernier). `TARGETED_DEVICE_FAMILY: "1"` = iPhone seulement ;
  `UIRequiredDeviceCapabilities: [arkit]` filtre les appareils sans ARKit
  (mais pas sans LiDAR — d'où l'écran « non compatible »).
- `Makefile` — les 5 commandes du projet ; `build-check` régénère toujours le
  projet avant de compiler, `etalon` écrit le cube de calibration à imprimer.
- `Scan3D/Resources/PrivacyInfo.xcprivacy` — manifeste App Store ; déclare
  l'API « espace disque » (raison E174.1) depuis la tranche 1.
- `.claude/settings.json` — garde-fous : édition du `.pbxproj` interdite,
  `rm -rf` et `curl` interdits, `xcodebuild` sur demande.
- `.gitignore` — exclut le projet généré, l'`Info.plist` généré, et **tous
  les fichiers de scan** (`.usdz`, `.stl`, `.heic`…) : un scan peut montrer
  l'intérieur d'un logement.

## Scénario de validation manuelle (tranche 0)

1. `make open` → Xcode s'ouvre.
2. Brancher l'iPhone (14 Pro Max ou 17 Pro Max), le sélectionner en haut de
   la fenêtre, ⌘R.
3. Si iOS le demande : Réglages → Confidentialité et sécurité → Mode
   développeur.
4. **Attendu** : titre « Scan3D », icône cube, texte « Prêt à scanner ».
5. Contre-épreuve : lancer sur un simulateur iPhone → « Appareil non
   compatible » (branche `#if` du simulateur).
