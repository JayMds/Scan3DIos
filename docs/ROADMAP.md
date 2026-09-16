# Feuille de route

Chaque tranche livre une app utilisable de bout en bout, testée sur iPhone.
On ne commence pas la tranche N+1 tant que la tranche N n'est pas validée.

## Tranche 0 — Fondations (ce kit) ✅

- Projet XcodeGen, paquet `Scan3DCore`, tests Swift Testing, Makefile.
- **Validé quand** : `make test-core` et `make build-check` passent, l'app
  s'installe sur l'iPhone et affiche « Prêt à scanner ».

## Tranche 1 — Scanner, voir, exporter ✅ validée le 15/09/2026

- Capture guidée (`ObjectCaptureSession`), reconstruction sur l'iPhone,
  aperçu 3D, export STL en millimètres via la feuille de partage.
- Spec détaillée : `TRANCHE-1.md`.
- **Validé quand** : un objet du quotidien (tasse, boîte) est scanné,
  exporté, ouvert dans Bambu Studio avec des dimensions cohérentes.
- Bilan et points ouverts : `BILAN-TRANCHE-1.md`.

## Tranche 2 — Précision

- Calibrage par carte bancaire et par cote saisie au pied à coulisse
  (`ScaleCalibration`, déjà amorcé dans `Scan3DCore`).
- Outil de mesure point à point sur le modèle.
- Bibliothèque locale des scans (`scan.json` par dossier).
- Point de départ mesuré (15/09/2026, boîte en carton, reconstruction
  iPhone) : app 189,2 × 163,0 × 56,8 mm contre 184 × 160 × 50 mm à la règle.
  Écarts additifs (+3 à +7 mm), la hauteur étant la plus touchée : le
  dessous, jamais photographié, a été bouché par l'algorithme. Le calibrage
  par facteur ne suffira pas.
- Diagnostic de la hauteur (16/09/2026) : avec une passe « Retourner », la
  hauteur mesurée passe de 46,0 à ≈ 50 mm pour 50 mm à la règle → pas de plan
  de coupe, mais un conseil dans la checklist de préparation.
- Spec : `TRANCHE-2.md` ; plan : `TRANCHE-2-PLAN.md` (décisions E1-E4 du
  15/09/2026) ; résultats : `MESURES-TRANCHE-2.md`.
- **Validé quand** : l'écart mesuré entre modèle et objet réel est documenté
  sur 3 objets de référence.

## Tranche 3 — Générer un support

- Premier générateur paramétrique : support mural (cavité ajustée au
  modèle + jeu réglable + trous de fixation).
- Booléens de maillages avec Manifold (interop C++).
- Export 3MF (ZIP + XML) prêt pour Bambu Studio.
- Pièce test « éprouvette de tolérance » pour régler le jeu.
- **Validé quand** : le support de l'interphone Wi-Fi est imprimé et monté.

## Tranche 4 — Compagnon Mac

- App macOS partageant `Scan3DCore` : reconstruction haute précision.
- Transfert iPhone → Mac en réseau local (Bonjour + Network), appairage
  authentifié, aucun serveur.
- **Mode plateau tournant** (reporté de la tranche 1 le 14/09/2026) : iPhone
  fixe sur support, objet sur plateau manuel, photos simples avec
  profondeur LiDAR (AVFoundation, **pas** `ObjectCaptureSession`) devant un
  fond uni, reconstruction sur Mac. Voir `TRANCHE-1-PLAN.md`, étape 2 bis,
  pour l'échec de la première approche et ses causes.
- **Validé quand** : un même objet reconstruit sur Mac est mesurablement
  plus précis que sur iPhone.

## Plus tard (non planifié)

- Grands objets / mobilier (mode zone d'Object Capture, RoomPlan).
- Support iPad Pro LiDAR.
- Autres gabarits : étui, adaptateur, cale, cache.
- Publication App Store (icône, captures, fiche, confidentialité).
