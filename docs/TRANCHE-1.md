# Tranche 1 — Scanner, voir, exporter

Objectif : de l'objet posé sur la table au fichier STL ouvert dans Bambu
Studio, avec des dimensions cohérentes. Pas encore de calibrage fin ni de
génération de support.

## 1. Parcours utilisateur (UX d'abord)

| # | Écran | Ce que voit l'utilisateur | Ce qu'il fait |
|---|-------|---------------------------|---------------|
| 1 | Accueil | Bouton « Nouveau scan », rappel des bonnes conditions | Lance un scan |
| 2 | Préparation | Checklist courte : fond uni et contrasté, lumière diffuse, objet mat | Coche / passe |
| 3 | Détection | Caméra + boîte englobante autour de l'objet | Ajuste la boîte, valide |
| 4 | Capture | Anneau de progression, conseils en direct (« trop près », « plus lentement ») | Tourne autour de l'objet |
| 5 | Fin de passe | Choix : nouvelle passe plus haute / retourner l'objet / terminer | Choisit |
| 6 | Reconstruction | Progression en %, bouton annuler, consigne « gardez l'app ouverte » | Attend |
| 7 | Aperçu | Modèle 3D manipulable + dimensions L × l × h en mm | Inspecte |
| 8 | Export | Feuille de partage iOS (Bambu Handy, Fichiers, AirDrop vers le Mac) | Partage le STL |

Principes UX :

- **Prévenir plutôt que guérir** : l'écran 2 évite la cause n°1 d'échec
  (surfaces noires, brillantes ou transparentes). Mentionner le spray
  matifiant temporaire comme astuce.
- **Toujours une sortie** : chaque écran a « Annuler » ; annuler pendant la
  capture demande confirmation (on perd les photos).
- **Aucune attente muette** : la reconstruction affiche une progression
  réelle, jamais un simple spinner.
- **Les dimensions d'abord** : dans l'aperçu, la cote en mm est l'information
  principale — c'est elle qui intéresse un utilisateur d'imprimante 3D.

## 2. Spécification technique

### Machine à états du parcours

Une seule source de vérité pour l'écran courant, dans un modèle
`@Observable` (analogue : un store Zustand piloté par une machine XState).

```
preparation → detection → capture ⇄ finDePasse → reconstruction → apercu
      ↘ annule (depuis tout état)      ↘ echec(message) (depuis capture/reconstruction)
```

Représentée par un `enum ScanPhase` avec valeurs associées
(ex. `reconstruction(progression: Double)`, `apercu(modele: URL)`).

### Stockage

```
Application Support/Scans/<UUID>/
  Images/        photos de capture (plusieurs centaines de Mo possibles)
  Checkpoint/    état intermédiaire de la reconstruction
  modele.usdz    résultat de PhotogrammetrySession
```

- Vérifier l'espace disque disponible **avant** de démarrer une capture
  (API à raison requise → mettre à jour `PrivacyInfo.xcprivacy`, catégorie
  `NSPrivacyAccessedAPICategoryDiskSpace`, raison E174.1 — confirmée le
  12/09/2026).
- Exclure `Scans/` de la sauvegarde iCloud (`isExcludedFromBackup`) : données
  volumineuses et régénérables.

### Capture et reconstruction

- `ObjectCaptureSession` + `ObjectCaptureView` pour les écrans 3 à 5.
- Désactiver la mise en veille (`isIdleTimerDisabled`) pendant la capture et
  la reconstruction, et la réactiver dans **tous** les chemins de sortie.
- `PhotogrammetrySession` avec requête `.modelFile(url:)`, consommation de
  `session.outputs` (flux `AsyncSequence`, analogue d'un `for await` sur un
  flux d'événements en TypeScript). Niveau de détail : `.reduced`, le
  **seul** disponible sur iOS (doc Apple vérifiée le 12/09/2026) → aucun
  choix de qualité dans l'UI.
- Libérer explicitement la session de capture avant de lancer la
  reconstruction (mémoire).

### Dimensions et export

- Calcul de la boîte englobante et conversion en mm dans `Scan3DCore`
  (logique pure, testée).
- Export STL via Model I/O avec **mise à l'échelle ×1000** (mètres → mm).
  Test obligatoire : un cube de 0,05 m exporté doit mesurer 50 mm.
- Fichier d'export écrit dans un dossier temporaire, nom
  `Scan3D-<date>.stl`, supprimé après partage.

## 3. Sécurité (voir aussi `SECURITY.md`)

- Permission caméra demandée au moment du premier scan, pas au lancement ;
  écran explicite si refusée, avec lien vers Réglages.
- Aucune photo ne quitte l'appareil sans action explicite de l'utilisateur.
- Vérifier que les images de capture ne contiennent pas de coordonnées GPS ;
  si oui, les retirer avant tout partage. Sans objet en tranche 1 : l'app ne
  demande jamais la localisation et seul le STL (géométrie pure, sans
  métadonnées) quitte l'appareil. À traiter en tranche 4 (transfert des
  photos vers le Mac).

## 4. Accessibilité

- Conseils de capture annoncés à VoiceOver et doublés d'un retour haptique.
- Dimensions lues sous forme de phrase (« 12,4 centimètres de large… »).
- Tous les écrans testés avec la plus grande taille de texte.

## 5. Scénario de test manuel (iPhone réel)

1. Poser une boîte en carton mate sur une table claire.
2. Scanner en 2 passes, reconstruire, lire les dimensions affichées.
3. Mesurer la boîte à la règle : écart attendu de l'ordre de quelques mm.
4. Exporter le STL, l'ouvrir dans Bambu Studio : taille cohérente.
5. Refaire en verrouillant l'iPhone pendant la reconstruction : noter le
   comportement.
6. Refuser la permission caméra : l'app doit l'expliquer sans planter.

## 6. Décisions validées par Jinkuro (12/09/2026)

Options étudiées et plan d'étapes : `TRANCHE-1-PLAN.md`.

- [x] Images après reconstruction : **supprimées** (`Images/` + `Checkpoint/`)
      après un succès, conservées en cas d'échec pour réessayer. Une
      préférence opt-in « conserver pour le Mac » arrivera en tranche 4.
- [x] Protection des fichiers de scan : **`.complete`**, avec un bouton
      « Reprendre » qui repart du checkpoint. Le scénario de test n° 5 décide
      d'une bascule vers `.completeUnlessOpen` (voir `SECURITY.md`).
- [x] Aperçu 3D : **Quick Look** (`.quickLookPreview`), les dimensions en mm
      restant l'information principale de l'écran. `RealityView` viendra avec
      l'outil de mesure (tranche 2).
- [x] (architecture) Lecture du maillage : **Model I/O dans `Scan3DCore`** +
      écriture STL binaire maison, testées sur Mac avec un cube généré en
      mémoire. Repli RealityKit si l'import USDZ déçoit.
