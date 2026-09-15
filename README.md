# Scan3D

App iOS de scan 3D d'objets pour concevoir des pièces imprimables.

## Installation (une seule fois)

1. **Xcode** à jour depuis le Mac App Store, puis ouvre-le une fois pour
   accepter la licence et installer les composants iOS.
2. **Outils en ligne de commande** :
   ```bash
   xcode-select --install
   brew install xcodegen
   ```
3. **Team ID** : dans `project.yml`, remplis `DEVELOPMENT_TEAM` avec ton
   identifiant d'équipe (developer.apple.com → Membership, 10 caractères).
4. **Bundle ID** : ajuste `fr.jinkuro.scan3d` si tu veux un autre identifiant.
5. **Git** :
   ```bash
   git init && git add . && git commit -m "chore: kit de démarrage"
   ```

## Vérifier que tout fonctionne

```bash
make test-core     # doit afficher les tests Scan3DCore au vert
make build-check   # doit compiler sans erreur
make open          # ouvre Xcode
```

Dans Xcode : branche ton iPhone, sélectionne-le en haut de la fenêtre,
puis ⌘R. Au premier lancement, active le **Mode développeur** sur l'iPhone
(Réglages → Confidentialité et sécurité → Mode développeur) si iOS le demande.

L'app doit afficher « Prêt à scanner ». Dans le simulateur, elle affiche
volontairement « Appareil non compatible » (pas de LiDAR).

## Démarrer avec Claude Code

```bash
claude
```

Puis colle le contenu de `PROMPT-DEMARRAGE.md`.

## Documentation

- `CLAUDE.md` — règles du projet (lues automatiquement par Claude Code)
- `docs/ROADMAP.md` — les tranches
- `docs/TRANCHE-1.md` — spec de la tranche 1 (validée)
- `docs/TRANCHE-1-PLAN.md` — plan d'implémentation, API vérifiées, résultats des tests
- `docs/BILAN-TRANCHE-1.md` — bilan et points ouverts
- `docs/TRANCHE-2.md` — spec de la tranche en cours (précision)
- `docs/TRANCHE-2-PLAN.md` — plan, API vérifiées, décisions E1-E4
- `docs/MESURES-TRANCHE-2.md` — campagne de mesure sur 3 objets
- `docs/VISITE-GUIDEE.md` — rôle et notions Swift de chaque fichier
- `docs/SECURITY.md` — modèle de menaces
- `docs/SWIFT-POUR-TS.md` — lire du Swift quand on vient de TypeScript
