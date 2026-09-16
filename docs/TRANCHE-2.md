# Tranche 2 — Précision

Objectif : savoir ce que valent les cotes d'un scan, et les corriger quand
il le faut. Retrouver ses scans, mesurer précisément un détail du modèle,
recaler l'échelle sur une cote connue, et **documenter l'écart réel sur
3 objets de référence**.

Point de départ (tranche 1, boîte en carton) : app 189,2 × 163,0 × 56,8 mm
contre 184 × 160 × 50 mm à la règle. Écarts additifs de +3 à +7 mm ; le
dessous de la boîte n'a jamais été photographié et a été bouché par
l'algorithme.

## 1. Parcours utilisateur (UX d'abord)

| # | Écran | Ce que voit l'utilisateur | Ce qu'il fait |
|---|-------|---------------------------|---------------|
| 1 | Bibliothèque (accueil) | Liste des scans : nom, date, cotes, badge « Calibré » ; bouton « Nouveau scan » ; si la liste est vide : « Prêt à scanner » | Ouvre un scan, en lance un, en supprime un (glisser) |
| 2 | Parcours de scan | Inchangé (tranche 1) ; se termine sur le détail du nouveau scan | — |
| 3 | Détail du scan | Nom modifiable, cotes en mm, badge de calibrage, actions : Mesurer, Voir en AR, Exporter en STL, Supprimer | Choisit une action |
| 4 | Visionneuse / mesure | Modèle 3D texturé qu'on fait tourner ; distance A–B affichée en grand | Touche deux points, efface, « Calibrer avec cette mesure » |
| 5 | Calibrage | La mesure A–B du modèle, un champ « Cote réelle (mm) » ou le choix « Carte bancaire », l'aperçu du facteur et des nouvelles cotes | Applique, annule ou réinitialise |
| 6 | Hauteur (conditionnel, étape 4) | Réglage « Retirer X mm en bas », plan visible dans la visionneuse | Ajuste, applique |

Principes UX :

- **Retrouver plutôt que refaire** : un scan terminé ne se perd plus en
  fermant l'écran.
- **Mesurer ce qui compte** : la boîte englobante donne l'encombrement ; la
  mesure point à point donne la cote utile (épaisseur d'un bord, entraxe de
  deux trous de fixation).
- **Calibrer en connaissance de cause** : toujours un aperçu avant / après,
  toujours réversible, et un badge rappelle que les cotes sont corrigées.
- **Destructif = confirmé** : supprimer un scan efface son modèle, une
  confirmation est demandée.
- **Honnêteté sur la précision** : les cotes restent affichées au dixième
  (l'unité des slicers), mais la précision attendue (quelques mm) est
  rappelée là où l'on mesure.

## 2. Spécification technique

### Bibliothèque (décision E1)

```
Application Support/Scans/<UUID>/
  modele.usdz
  scan.json     schemaVersion, id, name, createdAt, triangleCount,
                dimensions (brutes), calibration?, cutHeightMM? (étape 4)
```

- **Pas de SwiftData** : un `scan.json` par dossier, lu et validé par
  `Scan3DCore`. Supprimer le dossier supprime le scan, sans base à
  resynchroniser ; la protection `.complete` et l'exclusion de sauvegarde
  du dossier `Scans/` s'appliquent d'office.
- Au lancement, chaque dossier est classé :
  - **complet** (modèle + `scan.json` valide) → affiché ;
  - **modèle sans fiche** (scans de la tranche 1) → fiche recréée après
    mesure ;
  - **incomplet** (pas de modèle : capture ou reconstruction interrompue)
    → **purgé**, photos comprises.
- `scan.json` : 64 Ko au plus, écriture atomique, décodage validé.
- Nom : 1 à 80 caractères après nettoyage ; jamais utilisé dans un chemin
  (le dossier reste l'UUID).

### Détail du scan

`ScanFlowModel` se limite désormais à la préparation, à la capture et à la
reconstruction. Un `DetailScanModel` reprend la mesure du modèle, le
maillage en mémoire, l'export STL, puis la mesure point à point et le
calibrage. L'écran d'aperçu de la tranche 1 devient l'écran de détail.

### Visionneuse et mesure point à point (décision E3)

- `RealityView` (iOS 18) : modèle chargé par `Entity(contentsOf:)` puis
  **recalé sur la boîte englobante du maillage** (RealityKit applique
  `metersPerUnit`, Model I/O l'ignore) ; le repère de la scène est donc celui du
  maillage.
- Caméra en orbite autour du centre de l'objet, pilotée par `OrbitCamera`
  (`Scan3DCore`) : la même pose sert au rendu et au calcul du rayon.
- Toucher → rayon → intersection avec le `Mesh` dans `Scan3DCore` (algorithme de
  Möller-Trumbore) : le point mesuré vient de la même géométrie que les cotes,
  le calibrage et l'export.
- Deux marqueurs A et B, un segment, la distance en millimètres en
  surimpression SwiftUI.

### Calibrage (décision E2)

- Facteur = cote réelle ÷ cote mesurée sur le modèle, borné à ±20 %
  (`ScaleCalibration`).
- Référence : une cote saisie (pied à coulisse) ou la carte bancaire
  (largeur 85,60 mm ou hauteur 53,98 mm).
- Stocké **par scan** dans `scan.json` ; appliqué aux cotes, aux mesures et
  à l'export STL ; réinitialisable.

### Hauteur (décision E4)

Diagnostic fait le 16/09/2026 : la même boîte, scannée sans puis avec passe
« Retourner », mesure 46,0 mm puis **≈ 50 mm** en hauteur, pour 50 mm à la
règle. L'écart venait donc d'une face jamais photographiée, pas d'un défaut à
rattraper par le code : **pas de plan de coupe**. À la place, la checklist de
préparation explique qu'il faut retourner l'objet, et qu'un objet uni doit
d'abord recevoir des repères visuels (sinon les deux passes se recollent mal
et laissent des voiles le long des arêtes).

## 3. Sécurité (voir aussi `SECURITY.md`)

- `scan.json` est une **entrée non fiable** (fichier corrompu, ancienne
  version, et en tranche 4 fichier reçu d'un autre appareil) : taille
  bornée, `schemaVersion`, chaque champ validé au décodage.
- Les dossiers incomplets sont purgés au lancement : une capture interrompue
  ne laisse plus de photos du logement sur l'iPhone.
- Le nom saisi n'entre jamais dans un chemin de fichier.
- La cote saisie pour le calibrage est analysée strictement ; aucune saisie
  ne peut provoquer d'arrêt ni un facteur hors de ±20 %.
- Aucune nouvelle permission ; aucune donnée ne quitte l'appareil en dehors
  de l'export STL existant.

## 4. Accessibilité

- Bibliothèque : chaque ligne lue en phrase (nom, date, cotes en
  centimètres, « calibré ») ; actions de glissement exposées à VoiceOver et
  bouton « Supprimer » dans le détail.
- Visionneuse : `accessibilityDirectTouch` avec activation, annonces
  (« Point A posé », « Distance : 18,4 centimètres »), résultat toujours
  écrit. Limite assumée : poser un point précis reste un geste visuel.
- Calibrage : champ étiqueté avec son unité, erreurs annoncées, aperçu lu en
  phrase.
- Tous les écrans vérifiés avec la plus grande taille de texte.

## 5. Scénario de test manuel (iPhone réel)

1. Installer la nouvelle version : les scans de la tranche 1 apparaissent
   avec leurs cotes.
2. Renommer un scan, relancer l'app : le nom est conservé. Supprimer un
   scan : confirmation, puis il disparaît.
3. Nouveau scan : en fin de reconstruction, le détail s'ouvre ; le scan est
   en tête de la bibliothèque.
4. Mesurer deux coins d'une arête de la boîte ; comparer à la règle.
5. Calibrer sur 184 mm : cotes et export recalculés ; réinitialiser.
6. Tuer l'app pendant une capture, la relancer : Console « dossier
   incomplet purgé ».
7. VoiceOver et plus grande taille de texte sur la bibliothèque, le détail
   et le calibrage.

## 6. Protocole de mesure (validation de la tranche)

- Objets : **cube imprimé de 50 mm** (étalon), **boîte en carton**,
  **interphone Wi-Fi** (objet cible de la tranche 3).
- Conditions : même éclairage, mode orbite, avec une passe « Retourner ».
- Pour chaque objet et chaque cote : pied à coulisse, boîte englobante,
  mesure point à point, valeur après calibrage.
- Résultats dans `MESURES-TRANCHE-2.md`. Objectif indicatif : écart ≤ 2 mm
  sur une mesure point à point après calibrage du cube.

## 7. Décisions validées par Jinkuro (15/09/2026)

Options étudiées et plan d'étapes : `TRANCHE-2-PLAN.md`.

- [x] E1 Stockage : **`scan.json` par dossier** (SwiftData écarté).
- [x] E2 Calibrage : **par scan**.
- [x] E3 Visionneuse et mesure : **`RealityView` + intersection calculée
      dans `Scan3DCore`**.
- [x] E4 Hauteur : **diagnostic d'abord** — fait le 16/09/2026, conclusion :
      pas de plan de coupe, un conseil dans la checklist (le dessous doit être
      photographié).
