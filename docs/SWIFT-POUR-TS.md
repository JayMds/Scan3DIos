# Lire du Swift quand on vient de TypeScript

But : pouvoir relire le code livré par Claude, pas l'écrire de zéro.
Les 10 notions ci-dessous couvrent l'essentiel de ce que tu verras.

## 1. Variables et types

```swift
let largeur = 85.60          // const — type Double déduit
var compteur = 0             // let (TS) — modifiable
let nom: String = "Carte"    // annotation explicite, comme en TS
```

## 2. Optionnels : le `undefined` qu'on ne peut pas ignorer

```swift
var modele: URL? = nil       // ≈ URL | undefined

if let modele {              // ≈ if (modele !== undefined)
    ouvrir(modele)           // ici, modele est une URL garantie
}

guard let modele else {      // ≈ if (!modele) return
    return
}
```

`guard` est partout : il traite le cas d'erreur en premier et sort, ce qui
évite l'imbrication. Le `!` (forcer) est interdit dans ce projet.

## 3. `struct` vs `class` — LA différence avec TypeScript

- `struct` est copiée à chaque affectation (comme un nombre).
- `class` est partagée par référence (comme un objet JS).

```swift
var a = ScaleCalibration(...)  // struct
var b = a                      // b est une COPIE indépendante
```

En JS, `const b = a` partage le même objet. En Swift, avec une struct,
modifier `b` ne touche jamais `a`. D'où la préférence pour les structs :
moins d'effets de bord surprises.

## 4. `enum` avec valeurs associées = union discriminée

```swift
enum ScanPhase {
    case capture
    case reconstruction(progression: Double)
    case echec(message: String)
}
```

≈ en TS :
`type ScanPhase = { kind: "capture" } | { kind: "reconstruction", progression: number } | …`

Le `switch` doit couvrir **tous** les cas, sinon le code ne compile pas.
C'est le filet de sécurité que TS n'offre qu'avec des astuces (`never`).

## 5. `protocol` ≈ `interface`

```swift
protocol Exportable {
    func exporter(vers url: URL) throws
}
```

Une `extension` ajoute des méthodes à un type existant, même à un type
d'Apple — un peu comme augmenter un prototype, mais sûr et typé.

## 6. Erreurs : `throws` / `try` / `do-catch`

```swift
do {
    let c = try ScaleCalibration(measuredMM: 84, actualMM: 85.6)
} catch CalibrationError.implausibleFactor(let facteur) {
    // erreur précise, avec sa valeur associée
} catch {
    // toutes les autres erreurs
}
```

Différence clé avec TS : une fonction qui peut échouer **le déclare**
(`throws`), et l'appelant **doit** écrire `try`. Impossible d'oublier une
erreur. `throws(CalibrationError)` précise même le type d'erreur.

## 7. Étiquettes d'arguments

```swift
Units.millimeters(fromMeters: 0.12)
```

Le nom d'argument fait partie de l'appel, comme si chaque fonction TS
prenait un objet `{ fromMeters: 0.12 }`. Ça se lit comme une phrase.

## 8. SwiftUI ≈ React

| React | SwiftUI |
|-------|---------|
| composant fonction | `struct MaVue: View` |
| `return <JSX/>` | `var body: some View { … }` |
| `useState` | `@State private var x` |
| props modifiables par l'enfant | `@Binding var x` |
| Context | `@Environment` |
| store Zustand | `@Observable class` |
| `className` / style | modificateurs chaînés `.padding().font(.title)` |

Les modificateurs s'appliquent **dans l'ordre** : `.padding().background()`
et `.background().padding()` ne donnent pas le même rendu.

## 9. Concurrence : `async`, `Task`, `@MainActor`

- `async` / `await` : identiques à TS.
- `Task { … }` : lance du travail asynchrone (≈ appeler une fonction async
  sans l'attendre).
- `@MainActor` : ce code s'exécute sur le fil de l'interface. Toute mise à
  jour d'UI doit y être. Le compilateur Swift 6 le vérifie pour toi.
- `Sendable` : « ce type peut circuler sans risque entre fils d'exécution ».
  Swift 6 refuse de compiler les accès concurrents dangereux — là où JS n'a
  pas le problème car il est mono-thread.

## 10. Visibilité

`private` (le fichier / le type), `internal` (défaut, le module),
`public` (visible hors du paquet). Dans `Scan3DCore`, tout ce que l'app
utilise doit être `public`.

## 11. `Codable` ≈ `JSON.parse` + un schéma zod

- `struct Fiche: Codable { let nom: String }` : Swift génère la lecture et
  l'écriture JSON à partir des propriétés (≈ `z.object({ nom: z.string() })`
  inféré du type).
- `JSONDecoder().decode(Fiche.self, from: data)` ≈
  `schema.parse(JSON.parse(texte))` : un champ manquant ou du mauvais type
  lève une erreur, jamais un objet à moitié rempli.
- Pour valider davantage (longueur, plage), on écrit `init(from:)` à la
  main ≈ `.refine()` de zod.

## Ta checklist de relecture

- [ ] Je sais dire en une phrase ce que fait le fichier.
- [ ] Aucun `!`, `try!` ni `fatalError` injustifié.
- [ ] Les entrées utilisateur sont validées (`guard`).
- [ ] La logique de calcul est dans `Scan3DCore`, avec un test.
- [ ] Les textes affichés ont un libellé VoiceOver.
