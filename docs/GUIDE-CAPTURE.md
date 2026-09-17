# Guide de capture — réussir un scan

Ce document ne parle pas de code : il rassemble la **pratique** du scan, celle
qui décide de la qualité du modèle avant qu'une seule ligne ne s'exécute. Tout
ce qui est affirmé ici a été mesuré sur le terrain (voir §7) ; les pièges
techniques correspondants sont listés dans `CLAUDE.md`.

## 1. En bref

1. Objet **mat**, avec des **repères visuels** collés (adhésif de couleur,
   marqueur) sur au moins trois faces **et le dessous**.
2. Fond **uni et contrasté**, table dégagée, tour complet possible sans obstacle.
3. Lumière **diffuse, de plusieurs côtés**. Ni soleil direct, ni flash.
4. iPhone : batterie > 50 %, 2 Go libres, appareil pas déjà chaud.
5. **Passe 1** à ~15-20° au-dessus de l'horizon, tour complet, lentement.
6. **Passe 2** à ~45°, **sans toucher à l'objet**.
7. **Passe 3** objet **retourné sur le dessus**, même endroit, même lumière.
8. Terminer et reconstruire.

## 2. Préparer l'objet et la scène

**L'objet.** Les surfaces brillantes, noires ou transparentes trompent la
caméra : un voile de talc ou un spray matifiant temporaire règle le problème.
Les surfaces **unies** sont l'autre difficulté, moins évidente : la
photogrammétrie relie les images en reconnaissant des motifs ; sans motifs,
elle n'a rien à corréler. Trois ou quatre repères collés (ou tracés au
marqueur) suffisent. Sur le dessous aussi : c'est lui qui portera l'alignement
de la passe retournée. L'épaisseur d'un adhésif est négligeable devant la
précision attendue.

**La scène.** Fond uni qui contraste avec l'objet — table claire pour un objet
sombre, et l'inverse. Pas de motifs, pas de reflets, pas de verre. L'objet au
centre, assez loin du bord pour que tu puisses en faire le tour.

**La lumière.** Diffuse et venue de plusieurs directions. Les ombres dures
« collent » à l'objet : elles se retrouvent dans la texture et déplacent les
contours d'une image à l'autre. Une lumière franche sert aussi à autre chose :
elle raccourcit le temps d'obturation, donc supprime le flou de bougé.

**L'iPhone.** Un scan complet plus sa reconstruction consomment beaucoup :
batterie au-dessus de 50 %, 2 Go d'espace libre (l'app vérifie), et un appareil
qui n'est pas déjà brûlant — la chaleur ralentit la reconstruction.

## 3. La première passe : tourner autour

**C'est toi qui bouges, jamais l'objet.** Le plateau tournant est incompatible
avec `ObjectCaptureSession` (§7).

**Marcher est le mode prévu**, à trois conditions :

- **Lentement.** La capture est automatique : trop vite, deux photos
  consécutives ne se recouvrent plus assez pour être reliées. Le message
  « Plus lentement » est le seul à ne jamais ignorer. Compte une bonne minute
  par tour, avec une brève pause tous les 15 à 20° — une vingtaine d'arrêts.
- **À distance constante.** En marchant, on décrit une ellipse sans s'en
  apercevoir. L'app le signale (« Trop près », « Trop loin »), mais chaque
  correction coûte des photos, et leur nombre est plafonné.
- **Sans se faire de l'ombre.** Ton corps passe entre la lumière et l'objet
  pendant que tu tournes. Si tu vois l'objet s'assombrir à ton passage,
  éloigne-toi ou change la source.

Technique : petits pas, coudes au corps, **regarde l'écran plutôt que
l'objet**, et évite de pointer vers une fenêtre en pleine course (l'exposition
change et l'objet devient une silhouette).

## 4. Les passes suivantes

**Une hauteur par passe.** L'indicateur circulaire suit la couverture
angulaire **à la hauteur où tu te trouves**. Monter à mi-parcours laisse deux
bandes à moitié couvertes au lieu d'une complète : des vues sous 30° d'un côté,
sous 60° de l'autre, et rien de complet nulle part. Une variation douce à
l'intérieur d'un tour est sans conséquence ; les montées-descentes franches
gaspillent des photos.

| Passe | Hauteur | Ce qu'elle apporte |
|-------|---------|--------------------|
| 1 | ~15-20° au-dessus de l'horizon | flancs et arêtes verticales vus presque de profil — le plus précieux pour mesurer |
| 2 | ~45° | la liaison entre flancs et dessus |
| 3 | ~70°, en plongée | le dessus, et le fond des cavités |

**Le point de départ d'une nouvelle passe est libre.** Le recollage ne suit pas
l'ordre des photos : la reconstruction voit **toutes** les images d'un coup et
les aligne en reconnaissant des motifs communs.

**Passe « à une autre hauteur » : sans risque.** L'objet n'a pas bougé, il n'y
a donc rien à réaligner. Autant en profiter.

**Passe retournée : elle se paie.** L'objet a bougé ; l'algorithme doit
reconnaître des surfaces vues avant **et** après. Les faces latérales sont
visibles dans les deux passes : ce sont elles qui portent l'alignement. Unies,
elles ne portent rien, et le deuxième tour se recolle avec un décalage qui
laisse des **voiles plats le long des arêtes** (§7). D'où les repères.

Deux règles pour cette passe :
- retourner l'objet **sur le dessus** (le fond en l'air), au même endroit, avec
  la même lumière et le même fond — l'algorithme compare des apparences ;
- ne **jamais** toucher l'objet pendant une passe ; seulement entre deux. Si tu
  le bouscules, mieux vaut refaire la passe.

Si l'app affiche « Objet difficile à retourner », elle a déjà jugé l'objet trop
peu texturé : ajoute des repères, ou reste sur des passes à d'autres hauteurs
en acceptant que le dessous soit inventé.

## 5. Les messages de l'app, et ce qu'ils veulent dire

| Message | Traduction |
|---------|------------|
| « Trop sombre : allumez la lumière » | la capture est **à l'arrêt**, rien ne s'enregistre |
| « Cadrez l'objet dans l'écran » | idem, à l'arrêt |
| « Objet non détecté » | ajuste la boîte à la main, sans la coller au ras de l'objet |
| « Plus lentement » | les photos partent, mais elles seront floues |
| « Lumière faible » | la capture continue, la précision baisse |
| « Trop près » / « Trop loin » | la distance a dérivé pendant la marche |
| « Maximum de photos atteint » | les suivantes sont ignorées : pas d'allers-retours inutiles |
| « Objet difficile à retourner » | pas assez de motifs pour recoller deux passes |

## 6. Spécial mesure

Pour une pièce ajustée (la campagne de la tranche 2, les supports de la
tranche 3), ce sont les **arêtes** qui comptent, et la reconstruction les
arrondit :

- la passe **basse** (15-20°) est la plus utile : elle voit les faces
  verticales presque de profil, ce qui définit les arêtes ;
- multiplier les vues autour d'une arête réduit l'arrondi ;
- le **dessous** doit être photographié, sinon il est inventé — et la hauteur
  avec (§7) ;
- dans la visionneuse, **zoomer avant de poser chaque point** : sans zoom, la
  dispersion de visée atteint 2 mm ;
- une cote qui doit s'ajuster se prend **point à point**, pas sur la boîte
  englobante (qui donne l'encombrement, extrêmes du maillage compris).

Protocole complet de relevé : `MESURES-TRANCHE-2.md`.

## 7. Faits mesurés

| Date | Constat |
|------|---------|
| 14/09/2026 | **Plateau tournant incompatible** : iPhone fixe, objet qui tourne → nuage de points incohérent, reconstruction en échec, même sans capture automatique. |
| 14/09/2026 | Verrouillage de l'écran pendant la reconstruction : elle **reprend seule** au déverrouillage (protection de fichiers `.complete` confirmée). |
| 15/09/2026 | Boîte en carton, sans passe retournée : app **189,2 × 163,0 × 56,8 mm** contre **184 × 160 × 50 mm** à la règle. |
| 16/09/2026 | Même boîte, hauteur mesurée point à point : **46,0 mm** sans retournement, **≈ 50 mm** avec. Le dessous non photographié était comblé par l'algorithme. |
| 16/09/2026 | Passe retournée sur carton **uni** : voiles plats le long des arêtes et échancrure sur un flanc (recollage décalé). |
| 16/09/2026 | Dispersion de visée **sans zoom** : 1,9 mm sur trois mesures de la même hauteur. |
| 16/09/2026 | Écart de la mesure point à point : **additif** (−6,1 mm sur 184, −4,0 mm sur 50), donc pas rattrapable par un facteur d'échelle seul. |

## Voir aussi

- `CLAUDE.md` — les pièges techniques correspondants (API, unités, plateau).
- `TRANCHE-2.md` — spec de la tranche en cours ; la checklist de préparation de
  l'app reprend les points 1 à 4 de ce guide.
- `MESURES-TRANCHE-2.md` — protocole de relevé et résultats de la campagne.
