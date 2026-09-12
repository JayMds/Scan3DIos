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

**Rôle** : écran provisoire qui affiche « Prêt à scanner » si
`ObjectCaptureSession.isSupported`, sinon « Appareil non compatible ». C'est
lui qui valide la tranche 0 ; la tranche 1 y ajoute « Nouveau scan ».

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

## Les fichiers non-Swift

- `project.yml` — source de vérité du `.xcodeproj` (jamais éditer ce
  dernier). `TARGETED_DEVICE_FAMILY: "1"` = iPhone seulement ;
  `UIRequiredDeviceCapabilities: [arkit]` filtre les appareils sans ARKit
  (mais pas sans LiDAR — d'où l'écran « non compatible »).
- `Makefile` — les 4 commandes du projet ; `build-check` régénère toujours le
  projet avant de compiler.
- `Scan3D/Resources/PrivacyInfo.xcprivacy` — manifeste App Store, vide en
  tranche 0 ; la tranche 1 y déclare l'API « espace disque » (raison E174.1).
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
