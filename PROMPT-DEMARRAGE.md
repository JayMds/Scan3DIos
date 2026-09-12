# Prompts à coller dans Claude Code

## Session 1 — Valider les fondations

```
Lis CLAUDE.md et tous les fichiers de docs/.
Puis vérifie le kit de démarrage :
1. Lance `make test-core` et `make build-check`.
2. Si quelque chose échoue, explique la cause en termes simples, propose
   le correctif, et attends mon accord avant de l'appliquer.
3. Une fois tout au vert, fais-moi une visite guidée du dépôt : pour chaque
   fichier Swift, une phrase sur son rôle et les notions Swift qu'il
   illustre (en t'appuyant sur docs/SWIFT-POUR-TS.md).
Ne commence pas la tranche 1.
```

## Session 2 — Préparer la tranche 1 (mode plan)

Active le mode plan (Maj+Tab) avant d'envoyer :

```
On attaque la tranche 1 (docs/TRANCHE-1.md).
Avant tout code :
1. Présente-moi les options pour chacune des décisions de la section 6,
   avec avantages, inconvénients et ta recommandation.
2. Découpe la tranche en 4 à 6 étapes livrables et testables sur iPhone.
3. Pour chaque étape : fichiers créés, risques, points sécurité et
   accessibilité, et scénario de test manuel.
Vérifie les signatures des API Object Capture dans la documentation Apple
actuelle et signale toute incertitude.
```

## Session 3 et suivantes — Une étape à la fois

```
Implémente l'étape N du plan de la tranche 1.
Termine par : tests au vert, explication fichier par fichier, et le
scénario de test à faire sur mon iPhone.
```
