# Scan3D — Contexte pour Claude Code

App iOS qui scanne des objets en 3D pour concevoir des pièces imprimables
(ex. scanner un interphone Wi-Fi → générer un support mural ajusté).
Usage perso + publication App Store. Utilisateurs cibles : possèdent une
imprimante 3D et savent s'en servir.

## Répartition des rôles (IMPORTANT)

- **Claude écrit le code.** Jinkuro n'a jamais écrit de Swift : il relit,
  teste sur ses iPhones et valide les choix UX et sécurité.
- Jinkuro connaît bien **TypeScript, React / React Native (Expo), SvelteKit,
  Supabase/PostgreSQL**. Explique le Swift par analogie avec ces outils
  (voir `docs/SWIFT-POUR-TS.md`).
- **Règle de livraison** : chaque fichier créé ou modifié est accompagné, dans
  ta réponse, d'une phrase qui résume son rôle + les concepts Swift nouveaux
  qu'il introduit. Jinkuro doit pouvoir résumer chaque fichier avant d'accepter.
- Commentaires de code **en français**, orientés « pourquoi », pas « quoi ».
- Toute décision touchant la sécurité, les permissions, le réseau ou le
  stockage : **propose et attends validation** avant d'implémenter.
- Jinkuro aime avoir **plusieurs options** présentées quand un choix
  d'architecture se pose.

## Méthode

- **Tranches verticales** : chaque tranche livre une app fonctionnelle de bout
  en bout. Feuille de route : `docs/ROADMAP.md`. Tranche 1 validée le
  15/09/2026 (bilan et points ouverts : `docs/BILAN-TRANCHE-1.md`) ; la
  tranche 2 reste à spécifier.
- Commence chaque tâche non triviale en **mode plan** : liste les fichiers
  touchés et les risques avant de coder.
- Petits commits atomiques, message en français, préfixe conventionnel
  (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`).

## Stack

- Swift 6 (concurrence stricte), SwiftUI, iOS 18 minimum.
- RealityKit : `ObjectCaptureSession` + `ObjectCaptureView` (capture guidée),
  `PhotogrammetrySession` (reconstruction).
- Model I/O (`MDLAsset`) pour les conversions de maillage (USDZ → STL).
- SwiftData pour la bibliothèque locale de scans (tranche 1+).
- Plus tard : Manifold (C++, booléens de maillages) via l'interop C++ de
  Swift ; compagnon macOS pour la reconstruction haute précision.
- **Aucun backend, aucun cloud.** Les données restent sur l'appareil (et le
  Mac de l'utilisateur en tranche 4, via réseau local).
- Tests : **Swift Testing** (`import Testing`, `@Test`, `#expect`), pas XCTest.

## Architecture du dépôt

```
project.yml              Définition du projet (XcodeGen) — SOURCE DE VÉRITÉ
Scan3D/                  Cible app iOS (UI, intégration RealityKit)
  App/                   Point d'entrée
  Features/<Nom>/        Un dossier par fonctionnalité (vue + modèle)
  Resources/             Assets, PrivacyInfo.xcprivacy
Packages/Scan3DCore/     Logique pure, sans UI ni RealityKit, testable sur Mac
docs/                    Roadmap, specs de tranche, sécurité, aide Swift
```

**Règle de séparation** : tout calcul (unités, calibrage, géométrie,
écriture 3MF, validation de fichiers) va dans `Scan3DCore`. Ce paquet sera
partagé avec l'app Mac en tranche 4 et se teste en quelques secondes avec
`swift test`, sans simulateur. La cible app ne contient que l'UI et le code
qui dépend du matériel.

## Commandes

```bash
make generate     # régénère Scan3D.xcodeproj depuis project.yml
make test-core    # tests du paquet Scan3DCore (rapide, sur Mac)
make build-check  # compile l'app pour iOS sans signature (vérif CI-like)
make open         # ouvre le projet dans Xcode (pour installer sur iPhone)
```

Boucle de vérification attendue après chaque modification :
`make test-core` puis `make build-check`. Ne déclare jamais une tâche
terminée si l'une des deux échoue.

## Interdits

- **Ne jamais éditer `*.xcodeproj` / `project.pbxproj` à la main.** Tout passe
  par `project.yml` puis `make generate`. Le `.xcodeproj` est ignoré par git.
- Pas de `!` (force unwrap), pas de `try!`, pas de `fatalError` hors code
  réellement inatteignable (et justifié en commentaire).
- Pas de dépendance tierce sans proposer d'abord les options + licence.
- Pas de `print` pour les logs : utiliser `Logger` (framework `os`), sans
  jamais journaliser de chemins de fichiers utilisateur en clair
  (`privacy: .private`).
- Pas de stockage dans `UserDefaults` pour autre chose que des préférences.

## Pièges connus (à relire avant de toucher au scan)

- **Unités** : RealityKit et Object Capture travaillent en **mètres**. Les
  slicers (Bambu Studio) interprètent STL/3MF en **millimètres**. Toujours
  convertir via `Units.metersToMillimeters` de `Scan3DCore`. Un oubli donne
  une pièce 1000× trop petite.
- **Simulateur** : pas de caméra ni de LiDAR. Tout le code Object Capture est
  isolé derrière `#if !targetEnvironment(simulator)`. Les tests matériels se
  font sur iPhone réel (14 Pro Max et 17 Pro Max disponibles).
- **Compatibilité** : l'App Store ne permet pas d'exiger le LiDAR. Vérifier
  `ObjectCaptureSession.isSupported` et afficher un écran explicite sinon.
- **Une seule session de capture** active à la fois ; la libérer
  explicitement quand on quitte l'écran (mémoire importante).
- **Plateau tournant incompatible avec `ObjectCaptureSession`** (testé le
  14/09/2026) : iPhone fixe + objet qui tourne → nuage de points incohérent,
  reconstruction en échec, même sans checkpoint ni capture automatique. Le
  plateau passe par des photos simples avec profondeur (tranche 4).
- **Cross-import overlay** : `ObjectCaptureSession`, `ObjectCaptureView` et
  `ObjectCapturePointCloudView` n'existent que dans un fichier qui importe
  **RealityKit et SwiftUI** (« cannot find type in scope » sinon).
- **Model I/O** (vérifié le 14/09/2026) : ignore `metersPerUnit` et
  `upAxis` des fichiers USD (valeurs brutes ; RealityKit = mètres, Y
  vertical — échelle confirmée à la règle le 15/09/2026), n'applique pas les transformations parentes aux sommets
  (`MDLTransform.globalTransform`), et le pas entre sommets varie : toujours
  lire `stride`. Toute lecture passe par `MeshLoader` de `Scan3DCore`.
- **`ShareLink` ne signale pas la fermeture** de la feuille de partage :
  pour supprimer un fichier après partage, passer par `FeuilleDePartage`
  (`UIActivityViewController` + `completionWithItemsHandler`).
- **`.quickLookPreview`** vient du framework QuickLook : `import QuickLook`
  obligatoire, SwiftUI seul ne le connaît pas.
- **Reconstruction sur iPhone** : un seul niveau de détail, `.reduced`
  (< 50 k triangles ; vérifié dans la doc Apple le 12/09/2026). `.medium`,
  `.full`, `.raw` sont macOS seulement → rôle du compagnon Mac (tranche 4).
- **Verrouillage de l'écran** : une reconstruction dure plusieurs minutes. La
  protection de fichiers `.complete` rend les fichiers illisibles quand
  l'iPhone se verrouille → voir `docs/SECURITY.md` pour le choix retenu.
- Les API Object Capture évoluent à chaque WWDC : **vérifie les signatures
  dans la documentation Apple** plutôt que de te fier à ta mémoire, et
  signale-le quand tu n'es pas sûr.

## Sécurité et accessibilité

Checklist complète : `docs/SECURITY.md`. Pour chaque fonctionnalité, indique
les vecteurs d'attaque concernés et les mesures prises.

Accessibilité (WCAG / Apple HIG) : Dynamic Type partout, libellés VoiceOver
sur tous les contrôles, zones tactiles ≥ 44 pt, contraste suffisant, et le
guidage du scan ne doit jamais reposer uniquement sur le visuel (haptique +
annonces VoiceOver).

## Définition de « terminé »

1. `make test-core` et `make build-check` passent.
2. Nouveau code de logique couvert par des tests dans `Scan3DCore`.
3. Points sécurité et accessibilité de la fonctionnalité traités.
4. Explication fichier par fichier donnée à Jinkuro.
5. Scénario de test manuel sur iPhone décrit (étapes + résultat attendu).
