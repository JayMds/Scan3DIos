# Campagne de mesure — Tranche 2

Validation de la tranche : écart entre modèle et objet réel documenté sur
3 objets. Protocole : `TRANCHE-2.md` §6.

## Conditions

| Élément | Valeur |
|---------|--------|
| Date | |
| iPhone | |
| Version de l'app (commit) | |
| Éclairage | |
| Mode et passes | Orbite, avec passe « Retourner » |
| Instrument de référence | Pied à coulisse (résolution : ) |

## Objet 1 — Cube imprimé de 50 mm (étalon)

Imprimante, filament, réglages : 

| Cote | Pied à coulisse | Boîte englobante | Point à point | Après calibrage | Écart final |
|------|-----------------|------------------|---------------|-----------------|-------------|
| Longueur | | | | | |
| Largeur | | | | | |
| Hauteur | | | | | |

Calibrage : référence utilisée , facteur .
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
| Avec retournement | | | | | |

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
  l'arrondi des deux surfaces touchées. À comparer avec un scan **avec**
  passe « Retourner » : c'est le diagnostic qui décidera du plan de coupe.

## Objet 3 — Interphone Wi-Fi

| Cote | Pied à coulisse | Boîte englobante | Point à point | Après calibrage | Écart final |
|------|-----------------|------------------|---------------|-----------------|-------------|
| Longueur | | | | | |
| Largeur | | | | | |
| Épaisseur | | | | | |

Cotes utiles pour le support de la tranche 3 (arrondis, boutons, câble…) :

Observations :

## Synthèse

| Objet | Écart max brut | Écart max après calibrage | Conclusion |
|-------|----------------|---------------------------|------------|
| Cube | | | |
| Boîte | | | |
| Interphone | | | |
