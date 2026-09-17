# Campagne de mesure — Tranche 2

Validation de la tranche : écart entre modèle et objet réel documenté sur
3 objets. Protocole ci-dessous ; décisions et étapes : `TRANCHE-2-PLAN.md`.

## Ce qu'on cherche à savoir

1. **De combien un scan s'écarte-t-il du réel**, sans rien corriger ?
2. **Qu'apporte le calibrage**, et surtout que ne corrige-t-il pas ?
3. **Quelle précision annoncer** à quelqu'un qui dessine une pièce ajustée ?

Le piège à éviter : calibrer sur une cote, puis vérifier **la même** cote. Elle
tombera juste par construction, et on n'aura rien appris. D'où le protocole :
on calibre sur **une** cote et on vérifie sur **les deux autres**.

## Conditions

| Élément | Valeur |
|---------|--------|
| Date | |
| iPhone | |
| Version de l'app (commit) | |
| Éclairage | |
| Mode et passes | Orbite ; passe 1 normale, passe 2 autre hauteur, passe 3 retournée |
| Instrument de référence | Pied à coulisse (résolution : ) |

## Protocole, pour chaque objet

1. **Préparer l'objet.** Coller des repères visuels (adhésif de couleur, traits
   de marqueur) sur au moins trois faces, dont le dessous. Sans eux, la passe
   retournée se recolle mal (constaté le 16/09/2026 : voiles le long des
   arêtes). Nommer les faces au marqueur aide aussi à s'y retrouver.
2. **Mesurer au pied à coulisse** : longueur, largeur, hauteur, plus la cote
   utile s'il y en a une. Ce sont **ces** valeurs qui font référence — pas les
   cotes nominales, même pour une pièce imprimée.
3. **Scanner** : passe normale, puis passe à une autre hauteur (sans toucher à
   l'objet), puis passe retournée. Reconstruire.
4. **Relever, avant tout calibrage** :
   - les trois cotes de la **boîte englobante** (écran de détail) ;
   - les trois cotes en **point à point** (visionneuse), en zoomant avant de
     poser chaque point, et **deux fois chacune** — l'écart entre les deux
     essais donne la précision de visée.
5. **Calibrer sur la longueur** : mesurer la longueur point à point, « Calibrer
   avec cette mesure », saisir la cote au pied à coulisse. Noter le facteur.
6. **Vérifier après calibrage**, sur les cotes **non utilisées** pour calibrer :
   re-mesurer largeur et hauteur en point à point, et relever la nouvelle boîte
   englobante. C'est là que se lit ce que le calibrage apporte vraiment.
7. **Exporter en STL** et ouvrir dans Bambu Studio : les cotes affichées par le
   slicer doivent être celles de l'app (au moins pour le cube).

## Objet 1 — Cube étalon de 50 mm

Fichier à imprimer : `make etalon` → `build/etalon-cube-50mm.stl`, écrit par le
`STLWriter` de l'app elle-même. Si la pièce imprimée mesure 50,0 mm au pied à
coulisse, toute la chaîne maillage → millimètres → STL → slicer est prouvée
d'un coup. Imprimer à 100 %, sans mise à l'échelle. Le retrait du filament fait
souvent perdre 0,1 à 0,3 mm : c'est la cote **mesurée** qui sert de référence.

Un cube uni se scanne mal (pas de motifs) : coller des repères avant le scan,
comme pour les autres objets.

Imprimante, filament, réglages :

| Cote | Pied à coulisse | Boîte englobante | Point à point (essai 1 / 2) | Après calibrage | Écart final |
|------|-----------------|------------------|------------------------------|-----------------|-------------|
| Longueur | | | | (sert au calibrage) | |
| Largeur | | | | | |
| Hauteur | | | | | |

Calibrage : mesuré mm → réel mm, facteur .
Vérification du STL dans Bambu Studio : × × mm.
Observations :

## Objet 2 — Boîte en carton

Point de départ (tranche 1, sans retournement) : app 189,2 × 163,0 ×
56,8 mm, règle 184 × 160 × 50 mm.

Relevés du 16/09/2026 (outil de mesure de l'étape 2, **modèle de la tranche 1,
sans passe « Retourner »**, mesures à la règle) :

| Cote | Règle | Boîte englobante | Point à point | Après calibrage | Écart final |
|------|-------|------------------|---------------|-----------------|-------------|
| Longueur | 184 | 189,2 (+5,2) | 177,9 (−6,1) | | |
| Largeur | 160 | 163,0 (+3,0) | non mesurée | | |
| Hauteur | 50 | 56,8 (+6,8) | 46,0 (−4,0) | | |

Diagnostic de la hauteur (étape 4) :

| Modèle | Hauteur point 1 | Point 2 | Point 3 | Moyenne | Écart à la règle |
|--------|-----------------|---------|---------|---------|------------------|
| Sans retournement | 46,0 | 46,9 | 45,0 | 46,0 | −4,0 |
| Avec retournement | ≈ 50 | ≈ 50 | ≈ 50 | ≈ 50 | ≈ 0 |

Observations (16/09/2026) :

- **Les deux méthodes penchent en sens opposés** et encadrent la vérité :
  177,9 < 184 < 189,2 en longueur, 46,0 < 50 < 56,8 en hauteur. La boîte
  englobante prend les extrêmes du maillage (bourrelets, fond bouché,
  éventuels restes de table) ; la mesure point à point vise des surfaces que
  la reconstruction a arrondies, donc déjà en retrait.
- **L'erreur est additive, pas proportionnelle** : point à point, −6,1 mm sur
  184 (−3,3 %) et −4,0 mm sur 50 (−8,0 %). Un facteur d'échelle unique ne
  peut donc pas corriger les deux (décision E2 confirmée : le calibrage
  corrige l'échelle, pas l'arrondi des arêtes).
- Dispersion de la main sur les 3 hauteurs : 1,9 mm (45,0 à 46,9) — c'est la
  précision de visée à retenir, mesures prises sans zoomer.
- Écart entre les deux méthodes sur la hauteur : **10,8 mm**, soit la
  matière « invisible » ajoutée sous l'objet (fond jamais photographié) plus
  l'arrondi des deux surfaces touchées.
- **Piste pour la longueur et la largeur** : la boîte englobante est alignée
  sur les axes du fichier, pas sur l'objet. Une boîte posée de travers d'un
  seul degré donnerait 186,8 × 163,2 mm au lieu de 184 × 160 — la largeur
  mesurée (163,0) colle presque exactement. Une partie du « trop » n'est donc
  pas de la matière, mais de l'orientation. À confirmer sur le cube, dont les
  faces sont franches (piste d'amélioration : rectangle d'aire minimale).

**Scan avec passe « Retourner » (16/09/2026)** : hauteurs mesurées point à
point **autour de 50 mm** (valeurs exactes non relevées), contre 46,0 sans
retournement, pour 50 mm à la règle. Le dessous photographié suffit donc à
corriger la hauteur : **pas de plan de coupe** (décision E4 tranchée, voir
`TRANCHE-2-PLAN.md`, étape 4).

Revers de la médaille, visible dans la visionneuse et sur le modèle ouvert au
Mac : ce scan retourné porte des **voiles plats le long des arêtes du dessus**
et une échancrure sur un flanc — le deuxième tour s'est recollé avec un léger
décalage. Le carton est uni : trop peu de motifs pour aligner les deux passes.
Ces voiles dépassent de l'objet, donc ils **polluent la boîte englobante** de
ce scan, alors que les mesures point à point sur les zones propres restent
valables. D'où le conseil ajouté à la checklist de préparation : coller
quelques repères (adhésif de couleur, marqueur) avant de retourner un objet
uni, et préférer les passes « autre hauteur », qui ne déplacent pas l'objet.

Reprise complète au protocole ci-dessus (nouveau scan, avec repères) :

| Cote | Pied à coulisse | Boîte englobante | Point à point (essai 1 / 2) | Après calibrage | Écart final |
|------|-----------------|------------------|------------------------------|-----------------|-------------|
| Longueur | 184 | | | (sert au calibrage) | |
| Largeur | 160 | | | | |
| Hauteur | 50 | | | | |

## Objet 3 — Interphone Wi-Fi

| Cote | Pied à coulisse | Boîte englobante | Point à point (essai 1 / 2) | Après calibrage | Écart final |
|------|-----------------|------------------|------------------------------|-----------------|-------------|
| Longueur | | | | (sert au calibrage) | |
| Largeur | | | | | |
| Épaisseur | | | | | |

Cotes utiles pour le support de la tranche 3 (arrondis, boutons, câble…) :

Observations :

## Synthèse

| Objet | Écart max brut | Écart max après calibrage | Précision de visée | Conclusion |
|-------|----------------|---------------------------|--------------------|------------|
| Cube | | | | |
| Boîte | | | | |
| Interphone | | | | |

**Critère de validation de la tranche** : l'écart est documenté sur les trois
objets, et une mesure point à point après calibrage du cube tombe à **2 mm ou
moins** de la valeur au pied à coulisse.

**Ce qu'on en dira à l'utilisateur** (à rédiger une fois les trois lignes
remplies) : la phrase de précision à afficher dans l'app, et la marge à prévoir
dans le générateur de supports de la tranche 3.
