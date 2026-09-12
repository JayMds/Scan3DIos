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

### `Scan3D/Features/Scan/CameraRefuseeView.swift` et `DetectionPlaceholderView.swift`

**Rôle** : écran de refus caméra (lien Réglages) ; écran de détection
provisoire (affiche l'identifiant court du scan).

- `ContentUnavailableView` avec `actions:` ; `if let` sur une URL optionnelle
  (§2) ; `Link`.

## Les fichiers non-Swift

- `project.yml` — source de vérité du `.xcodeproj` (jamais éditer ce
  dernier). `TARGETED_DEVICE_FAMILY: "1"` = iPhone seulement ;
  `UIRequiredDeviceCapabilities: [arkit]` filtre les appareils sans ARKit
  (mais pas sans LiDAR — d'où l'écran « non compatible »).
- `Makefile` — les 4 commandes du projet ; `build-check` régénère toujours le
  projet avant de compiler.
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
