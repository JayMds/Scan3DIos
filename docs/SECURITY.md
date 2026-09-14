# Sécurité et confidentialité

Pas de backend : la surface d'attaque est réduite, mais pas nulle. Les
risques viennent de trois endroits : **les données sur l'appareil**, **les
fichiers qui entrent**, et **le réseau local** (tranche 4).

## Pourquoi c'est sensible

Un scan, ce sont des centaines de photos prises chez l'utilisateur :
intérieur du logement, parfois un digicode, une adresse sur un courrier qui
traîne. On traite ces photos comme des données personnelles.

## Modèle de menaces

| Menace | Tranche | Mesure |
|--------|---------|--------|
| Vol de l'iPhone déverrouillé / sauvegarde lue | 1 | Protection de fichiers iOS, exclusion de la sauvegarde iCloud |
| Fuite de géolocalisation via EXIF | 1 | Vérifier et retirer les métadonnées GPS avant tout partage |
| Fuite via les logs | 1 | `Logger` avec `privacy: .private` pour chemins et noms |
| Saisie aberrante (calibrage) | 2 | Validation stricte (`ScaleCalibration`, déjà en place) |
| Fichier 3MF malveillant importé (**zip slip**) | 3 | Refuser tout chemin contenant `..` ou absolu lors de la décompression |
| **Zip bomb** (fichier qui explose à la décompression) | 3 | Plafonner taille totale décompressée et nombre d'entrées |
| XML piégé dans un 3MF (entités externes, XXE) | 3 | Désactiver la résolution d'entités externes du parseur |
| Maillage géant (déni de service mémoire) | 3 | Plafonner le nombre de triangles accepté — **en place** depuis la tranche 1 : `Mesh.maximumTriangleCount` (2 M), lecture bornée des tampons dans `MeshLoader` |
| Appareil tiers sur le Wi-Fi qui intercepte ou injecte des scans | 4 | Appairage par code + TLS, clé épinglée après appairage |
| Chaîne d'approvisionnement (dépendance compromise) | toutes | Versions épinglées, licence vérifiée, dépendances minimales |

## Protection des fichiers : le dilemme

- `.complete` : fichiers chiffrés et illisibles dès que l'iPhone se
  verrouille. Le plus sûr, mais une reconstruction de plusieurs minutes
  échouera si l'utilisateur verrouille son téléphone.
- `.completeUnlessOpen` : un fichier déjà ouvert reste accessible après
  verrouillage, les nouveaux ne peuvent pas être créés. Bon compromis pour
  un traitement long.
- `.completeUntilFirstUserAuthentication` (défaut iOS) : accessible dès le
  premier déverrouillage après démarrage.

**Décision (12/09/2026)** : `.complete` sur `Scans/<UUID>/`, posé à la
création du dossier, plus `isExcludedFromBackup`. Justification : l'app est
suspendue dès que l'écran se verrouille (pas de tâche de fond), donc le seul
risque est une lecture en cours à l'instant du verrouillage → la
reconstruction signale une erreur et propose « Reprendre » (repart du
checkpoint, quelques secondes). Règle de bascule : si le scénario
« verrouillage pendant la reconstruction » (`TRANCHE-1.md` §5, point 5)
échoue trop souvent, passer à `.completeUnlessOpen` et consigner ici le
résultat mesuré.

**Test terrain (14/09/2026, iPhone réel, mode orbite)** : iPhone verrouillé
pendant la reconstruction, 30 s d'attente, déverrouillage → la
reconstruction **reprend seule**, sans erreur ni reprise manuelle.
`.complete` est confirmé ; pas de bascule. Le bouton « Reprendre » reste
utile pour les autres causes d'échec.

## Checklist App Store

- [ ] `NSCameraUsageDescription` claire et honnête (en place).
- [ ] `PrivacyInfo.xcprivacy` à jour à chaque API « à raison requise ».
- [ ] Étiquette de confidentialité App Store : « Aucune donnée collectée ».
- [ ] `NSLocalNetworkUsageDescription` + `NSBonjourServices` (tranche 4).
- [ ] Aucune dépendance qui envoie de la télémétrie.

## Revue de sécurité par fonctionnalité

Pour chaque fonctionnalité livrée, Claude indique :
1. Quelles données entrent et d'où (utilisateur, fichier, réseau, capteur).
2. Où elles sont stockées et avec quelle protection.
3. Les vecteurs d'attaque de ce tableau qui s'appliquent.
4. Les tests qui prouvent la mesure (ex. un test « zip slip » dans
   `Scan3DCore` avec une archive piégée).
