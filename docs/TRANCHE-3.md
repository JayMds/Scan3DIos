# Tranche 3 — Générer un support

Objectif : transformer un scan en **pièce imprimable ajustée**. Premier
générateur paramétrique — un support mural —, validé quand celui de
l'interphone Wi-Fi est **imprimé et monté**.

Point de départ (tranche 2) : l'écart du scan est **additif**, les surfaces
rentrent de 2 à 3 mm et les arêtes s'arrondissent. La silhouette extraite d'un
maillage est donc plus petite que l'objet réel : c'est le **jeu** qui doit
absorber cet écart, pas la géométrie. Et un scan porte des artefacts (voiles,
miettes de table) qui n'ont rien à faire dans une cavité.

## 1. Parcours utilisateur (UX d'abord)

| # | Écran | Ce que voit l'utilisateur | Ce qu'il fait |
|---|-------|---------------------------|---------------|
| 1 | Détail du scan | Une action de plus : « Créer un support » | L'ouvre |
| 2 | Face contre le mur | Le modèle en 3D et six choix (dessous, dessus, avant, arrière, gauche, droite), la silhouette correspondante en aperçu | Choisit la face qui s'appuie au mur |
| 3 | Paramètres | Épaisseur de plaque, marge, profondeur de poche, **jeu**, trous de fixation ; aperçu 3D du support avec l'objet en transparence ; résumé en toutes lettres | Ajuste, surtout le jeu |
| 4 | Export | « Exporter une tranche d'essai » et « Exporter le support » | Exporte en STL |
| 5 | Impression | — | Imprime la tranche, essaie, corrige le jeu, imprime la pièce, monte |

Principes UX :

- **Essayer avant d'imprimer.** La tranche d'essai — les 15 premiers
  millimètres de la pièce — coûte un quart d'heure au lieu de trois heures.
  C'est le cœur du parcours, pas une option cachée.
- **Un seul réglage compte vraiment : le jeu.** Tout le reste a des valeurs par
  défaut raisonnables, et l'écran dit pourquoi le jeu doit être généreux ici.
- **Montrer ce qu'on va imprimer** : l'aperçu superpose le support et l'objet.
- **Rien n'est irréversible** : les paramètres vivent dans `scan.json`,
  régénérer est instantané.

## 2. Spécification technique

### Mesure de face à face (piste retenue de la tranche 2)

Au lieu de deux points visés à la main, on ajuste un **plan** sur le voisinage
de chaque toucher (normales pondérées par l'aire, puis test du résidu). Trois
mesures bien définies, choisies par la géométrie, jamais par un sélecteur de
mode :

| Ce qu'on a touché | Ce qu'on mesure |
|-------------------|-----------------|
| deux faces parallèles | **épaisseur** entre les deux plans — la mesure du pied à coulisse |
| une face et un point | distance du **point au plan** |
| deux points | distance, comme aujourd'hui |

Attendu : l'arrondi des arêtes sort de l'équation, et la dispersion de visée
(1,9 mm mesurée en tranche 2) tombe au dixième.

### Silhouette de l'objet (décision G2)

De `Mesh` + direction du mur + jeu vers un polygone, en passant par une
**grille 2D** :

1. projection des triangles sur le plan du mur, **rastérisation** (pas 0,1 mm) ;
2. conservation de la **plus grande composante connexe** — les fragments
   détachés du scan disparaissent ici, gratuitement ;
3. **transformée de distance**, puis **marching squares** sur l'isoligne `jeu` ;
4. simplification du contour.

C'est l'étape 3 qui justifie le détour par une grille : dilater un contour
**concave** par déplacement de sommets créerait des auto-intersections à
résoudre ; par la distance, le problème n'existe pas, et une entaille plus
étroite que deux fois le jeu se referme d'elle-même — exactement ce qu'il faut,
sinon l'objet n'entrerait pas.

### Solides (décision G1)

Construction directe du maillage, sans booléen général ni dépendance tierce :
triangulation par oreilles avec ponts (contours à trous), coutures, cylindres.
Invariant vérifié par test sur **toute** pièce générée : maillage **étanche**,
normales vers l'extérieur, volume positif.

### Le support mural

```
   vue de face                        coupe
 ┌──────────────────────┐        ┌────────────┐  ┐
 │  ○                ○  │        │  ╔══════╗  │  │ épaisseur e
 │   ╭──────────────╮   │        │  ║      ║  │  │
 │   │    poche     │   │        │  ║      ║  │  ┘
 │   ╰──────────────╯   │        └──╨──────╨──┘
 └──────────────────────┘           profondeur p
   marge m       trous Ø d, entraxe
```

Paramètres : épaisseur de plaque, marge autour de la poche, profondeur de
poche, **jeu**, diamètre et entraxe des trous, hauteur de la tranche d'essai.

### Export

STL d'abord (l'écrivain existe et a été validé dans Bambu Studio en tranche 1),
3MF en dernière étape — Foundation n'ayant aucune API ZIP, le conteneur OPC est
à écrire nous-mêmes.

## 3. Sécurité

- Aucune donnée nouvelle, aucune permission nouvelle, rien qui sorte de
  l'appareil en dehors de l'export explicite.
- Les paramètres du support sont enregistrés dans `scan.json`, donc soumis au
  même décodage validé que le reste (entrée non fiable, `SECURITY.md`).
- Les cotes saisies passent par `MillimeterInput` et sont bornées : aucune
  valeur ne peut produire une pièce absurde ni un calcul qui s'emballe.
- Le STL produit est de la géométrie pure, écrit dans le dossier temporaire
  protégé et supprimé à la fermeture de la feuille de partage, comme en
  tranche 1.
- Plafond de calcul explicite sur la grille de silhouette (pas et étendue
  bornés) : un maillage aberrant ne doit pas pouvoir réserver 1 Go.

## 4. Accessibilité

- Chaque paramètre est un champ étiqueté **avec son unité** ; les erreurs de
  saisie sont annoncées.
- L'aperçu 3D est doublé d'un **résumé en toutes lettres** (« plaque 120 × 90 ×
  4 mm, poche de 12 mm de profondeur, jeu 1,0 mm, deux trous de 4,5 mm espacés
  de 80 mm ») : la pièce reste compréhensible sans voir l'image.
- Le choix de la face contre le mur est une liste nommée, pas un geste 3D.
- Annonces aux moments clés : support régénéré, fichier exporté.

## 5. Scénario de test manuel (iPhone réel)

1. Ouvrir le scan de l'interphone → « Créer un support » → choisir la face
   arrière : la silhouette s'affiche, sans fragment parasite.
2. Laisser les valeurs par défaut, vérifier l'aperçu : la poche épouse le
   contour, les trous sont hors de la poche.
3. Exporter la **tranche d'essai** → imprimer → essayer l'emboîtement.
4. Corriger le jeu, réexporter, réimprimer la tranche si nécessaire.
5. Exporter le support entier → imprimer → **monter au mur avec l'interphone**.
6. VoiceOver sur l'écran de paramètres ; plus grande taille de texte.

## 6. Critère de validation

Le support de l'interphone Wi-Fi est imprimé, l'objet s'y emboîte, et la pièce
est montée au mur. Réglages retenus et écarts consignés dans
`MESURES-TRANCHE-3.md`.

## 7. Décisions validées par Jinkuro (18/09/2026)

Options étudiées et plan d'étapes : `TRANCHE-3-PLAN.md`.

- [x] G1 Moteur géométrique : **construction directe en Swift** (Manifold,
      Apache-2.0, écarté tant qu'aucun booléen général n'est nécessaire).
- [x] G2 Cavité : **silhouette fidèle**, concavités comprises.
- [x] G3 Export : **STL d'abord**, 3MF en dernière étape.
- [x] G4 Mesure de face à face : **étape 1** de la tranche.
