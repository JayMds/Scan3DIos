# Bilan — Tranche 1 « Scanner, voir, exporter »

**Validée le 15/09/2026.** Critère de la feuille de route atteint : une boîte
en carton scannée sur iPhone, exportée en STL et ouverte dans Bambu Studio
avec des dimensions cohérentes.

## En bref

- **Parcours complet sur l'iPhone** : accueil → préparation → capture guidée
  (plusieurs passes, retournement de l'objet) → reconstruction (progression
  réelle, reprise après échec) → aperçu (cotes en mm, 3D et AR à l'échelle)
  → export STL par la feuille de partage.
- **Aucun backend** : tout reste sur l'appareil ; seul le STL sort, sur
  action explicite.
- **Chiffres** : 5 étapes livrées (+ 1 essayée puis retirée), 11 commits,
  48 tests en 12 suites dans `Scan3DCore` (716 lignes de logique, 540 de
  tests), 21 fichiers dans l'app (1 770 lignes). Compilation iPhone **et
  simulateur** sans avertissement en Swift 6 strict.

## Livraisons

| Étape | Contenu | Commit |
|-------|---------|--------|
| 0 | Visite guidée, plan, décisions D1-D4 | `e305143` |
| 1 | Parcours, checklist, permission caméra, stockage protégé | `cc0093a` |
| 2 | Capture guidée (`ObjectCaptureSession`), conseils haptiques et VoiceOver | `1ce5f28` |
| 2 bis | Mode plateau tournant — **retiré** après échec terrain | `fd9ad3c` → `224cec0` |
| 3 | Reconstruction sur iPhone, reprise, suppression des photos | `5e4a776` |
| 4 | Lecture du maillage, dimensions en mm, Quick Look | `9572e37` |
| 5 | Export STL binaire en mm, feuille de partage | `8354722` |

## Décisions

| Décision | Choix | Statut |
|----------|-------|--------|
| D1 Photos après reconstruction | Supprimées après succès, gardées si échec | Appliquée |
| D2 Protection des fichiers | `.complete` + « Reprendre » | **Confirmée sur le terrain** : la reconstruction reprend seule après verrouillage |
| D3 Aperçu 3D | Quick Look | Appliquée |
| D4 Lecture du maillage | Model I/O dans `Scan3DCore` | Appliquée — chaîne mesure + export testée sur Mac |
| Plateau tournant | Option F : reporté au compagnon Mac | Code retiré, leçon dans `CLAUDE.md` et `ROADMAP.md` |

## Mesures terrain

| Vérification | Résultat |
|--------------|----------|
| Échelle du modèle | Correcte (mètres) : pas d'erreur ×10 ni ×1000 |
| Boîte en carton, app / règle | 189,2 × 163,0 × 56,8 mm / 184 × 160 × 50 mm → écarts **additifs** de +3,0 à +6,8 mm |
| Bambu Studio | STL ouvert à la bonne taille |
| Verrouillage pendant la reconstruction | Reprise automatique |
| Mode plateau (`ObjectCaptureSession`, iPhone fixe) | Échec : nuage de points incohérent, reconstruction impossible |

## Ce que la tranche a appris

Consigné dans les pièges de `CLAUDE.md`, pour ne plus le redécouvrir :

- `ObjectCaptureSession` et ses vues n'existent que si le fichier importe
  **RealityKit et SwiftUI** (cross-import overlay).
- Le plateau tournant est incompatible avec `ObjectCaptureSession` (nuage de
  points LiDAR placé dans le repère de la pièce).
- iOS ne reconstruit qu'en `.reduced` ; `checkpointDirectory` doit être vide.
- Model I/O ignore `metersPerUnit` et `upAxis`, ne compose pas les
  transformations parentes, et le pas entre sommets varie.
- `.quickLookPreview` exige `import QuickLook` ; `ShareLink` ne signale pas
  la fermeture de la feuille de partage.
- Méthode : un **essai rapide sur Mac** avant de coder (fichiers USD aux
  cotes connues) a évité de construire l'étape 4 sur une hypothèse d'unité ;
  une **relecture avant commit** a trouvé une perte de données silencieuse à
  l'étape 3 (« Annuler » supprimait le modèle terminé).

## Écarts par rapport à la spec

- Machine à états : l'échec est aussi possible depuis la détection, et
  « Reprendre » ramène d'un échec à la reconstruction.
- Fin de scan : le bouton de barre devient « Fermer » et **garde** le modèle
  (au lieu d'« Annuler », qui supprimait tout).
- Export : feuille UIKit plutôt que `ShareLink`, pour pouvoir supprimer le
  fichier après partage.
- Vérification GPS des photos : sans objet en tranche 1 (aucune photo ne
  quitte l'appareil) ; à traiter en tranche 4.

## Points ouverts

| # | Point | Impact | Où le traiter |
|---|-------|--------|---------------|
| 1 | Hauteur surestimée de 6,8 mm (reste de table sous l'objet suspecté ; contrôle visuel dans Quick Look non encore fait) | Un support conçu d'après le scan aurait une cavité trop profonde | Tranche 2, en premier |
| 2 | Les modèles s'accumulent dans `Scans/` (~10 Mo chacun) sans moyen de les supprimer | Stockage ; données conservées sans contrôle de l'utilisateur | Tranche 2 : bibliothèque SwiftData |
| 3 | Seuil d'espace disque (2 Gio) jamais recalé : le poids réel des photos (« N photos, X Mo ») n'a pas été relevé | Refus de scan trop prudent, ou pas assez | Noter le bilan affiché au prochain scan |
| 4 | Tests manuels **non rapportés** : annulation pendant la reconstruction, annonces VoiceOver (capture, dimensions, partage), plus grande taille de texte, mode AR à l'échelle, présence de Bambu Handy, second iPhone | Accessibilité et robustesse non validées sur appareil | Session de vérification avant la tranche 2 |
| 5 | `ScanFlowModel` (359 lignes) coordonne capture, reconstruction, mesure et export | Lisibilité, risque de régression en tranche 2 | Découpage léger au début de la tranche 2 |
| 6 | Pas de tests automatisés côté app (toute la logique testée est dans `Scan3DCore`) | Régressions d'interface vues tard | Acceptable aujourd'hui ; à reconsidérer avant l'App Store |
| 7 | Dimensions sur la boîte englobante alignée aux axes du modèle | Surestimation si l'objet est tourné dans le fichier (les mesures actuelles ne l'indiquent pas) | Rectangle d'aire minimale si un cas le montre |
| 8 | Mode plateau tournant | — | Tranche 4 |

## Pistes pour la tranche 2 « Précision »

La feuille de route prévoit : calibrage (carte bancaire, cote au pied à
coulisse), mesure point à point, bibliothèque SwiftData ; validée quand
l'écart modèle / objet réel est documenté sur 3 objets de référence.

Ce que les mesures changent :

- Les écarts sont **additifs**, pas proportionnels : un facteur de
  calibrage seul corrigera peu. Il faudra aussi traiter la **base** du
  modèle (point ouvert 1).
- Pour les 3 objets de référence, une pièce **imprimée** aux cotes connues
  (cube de 50 mm, par exemple) est idéale : dimensions exactes, surfaces
  mates, et l'imprimante est déjà là.

Ordre suggéré, à arbitrer en mode plan au début de la tranche :

1. Diagnostic de la hauteur (2 minutes dans Quick Look) et protocole de
   mesure sur les 3 objets de référence, pour une base chiffrée.
2. Bibliothèque SwiftData : lister, rouvrir, supprimer les scans (résout le
   point ouvert 2 ; décision de stockage à valider).
3. Mesure point à point sur le modèle (`RealityView`).
4. Calibrage (`ScaleCalibration` existe déjà) et traitement de la base.
