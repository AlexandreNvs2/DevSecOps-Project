# DevSecOps-Project

Challenge final DevSecOps : intégrer et déployer de manière sécurisée une application Python (Flask) dans une pipeline CI/CD, en appliquant les principes DevSecOps.

## Sommaire

1. [Contenu du dépôt](#contenu-du-dépôt)
2. [Gestion sécurisée du versioning](#gestion-sécurisée-du-versioning)
3. [Sécurisation du code source](#sécurisation-du-code-source)
4. [Image Docker et pipeline CI](#image-docker-et-pipeline-ci)
5. Déploiement sécurisé sur AWS *(à venir)*
6. Stockage sécurisé des mots de passe *(à venir)*
7. Architecture et cycle de vie sécurisé *(à venir)*

## Contenu du dépôt

- `app/app/main.py` : application Flask (vérification d'un mot de passe dans les listes SecLists).
- `app/app/data/` : listes SecLists embarquées (500 et 10 000 mots de passe les plus courants).
- `app/app/gunicorn.conf.py` : configuration du serveur de production Gunicorn.
- `app/app/requirements.txt` : dépendances Python, versions figées.
- `Dockerfile` : construction de l'image Docker (multi-étapes, durcie).
- `.dockerignore` : liste blanche des fichiers envoyés au build Docker.
- `tests/container/smoke_test.sh` : tests de fonctionnement et de sécurité du conteneur.
- `.github/workflows/ci.yml` : pipeline CI GitHub Actions.
- `.github/dependabot.yml` : mises à jour automatiques des dépendances, de l'image de base et des actions.

## Gestion sécurisée du versioning

### Plateforme

Le dépôt est hébergé sur **GitHub** et la CI/CD utilisera **GitHub Actions**. Les activités du cours utilisaient GitLab CI ; les outils de sécurité étudiés (Flake8, Bandit, Semgrep, Trivy, Hadolint, Dockle, ZAP, Checkov, TruffleHog) s'exécutent de la même façon dans GitHub Actions.

### Signature des commits

Tous les commits sont signés avec une clé SSH **ed25519**, déclarée sur GitHub comme clé de signature (*Signing Key*). GitHub les affiche comme **Verified**, ce qui garantit que l'auteur affiché est bien celui qui a produit le commit.

- ed25519 plutôt que RSA 2048 : clé plus courte, plus rapide, et niveau de sécurité équivalent ou supérieur.
- Un fichier `allowed_signers` permet aussi de vérifier les signatures en local (`git log --show-signature`).
- Les deux premiers commits (import de l'application de départ) sont antérieurs à cette configuration et ne sont pas signés. Ils n'ont pas été réécrits : modifier un historique déjà publié est une mauvaise pratique.

### Protection de la branche `main`

Un *ruleset* GitHub (`protect-main`) s'applique à la branche par défaut, **sans aucune exception** (liste de contournement vide, y compris pour le propriétaire du dépôt).

| Règle | Effet |
|---|---|
| Restrict deletions | `main` ne peut pas être supprimée |
| Block force pushes | l'historique de `main` ne peut pas être réécrit |
| Require signed commits | tout commit non signé est refusé |
| Require a pull request before merging | aucun push direct : toute modification passe par une pull request |
| Require conversation resolution | une PR ne peut pas être fusionnée tant qu'une discussion reste ouverte |
| Méthodes de fusion : merge et squash | le *rebase merge* est désactivé, car GitHub ne peut pas signer les commits rebasés |
| Require status checks to pass | une PR ne peut être fusionnée que si les 4 jobs de la pipeline réussissent |
| Require branches to be up to date | la PR doit être testée sur la dernière version de `main` avant la fusion |

**Nombre d'approbations requis : 0.** Le projet est réalisé seul et GitHub interdit d'approuver sa propre pull request ; exiger une approbation bloquerait toute fusion. Dans une équipe, ce nombre serait fixé à au moins 1.

**Vérifications obligatoires** (*required status checks*), ajoutées une fois la pipeline au vert sur la PR #2 :

| Check obligatoire | Outil |
|---|---|
| `Lint (Flake8)` | qualité du code |
| `SAST (Bandit)` | analyse statique de sécurité |
| `SAST (Semgrep)` | analyse statique de sécurité |
| `SCA (pip-audit)` | vulnérabilités des dépendances |

Ces checks sont rattachés à **GitHub Actions** : un autre outil ou un statut posé à la main ne peut pas les satisfaire. La sécurité devient une **condition bloquante** de la livraison : aucune modification n'arrive sur `main` si un scan échoue, et la règle s'applique aussi au propriétaire du dépôt.

**Méthode de fusion utilisée : merge commit.** Elle conserve chaque commit de la branche dans l'historique de `main`, ce qui garde valides les références de commits citées dans ce README (un *squash* les regrouperait en un seul).

### Workflow de branches

```
main (protégée)
 ├── docs/...   documentation
 ├── fix/...    corrections de sécurité
 ├── ci/...     pipeline CI/CD
 └── feat/...   nouvelles fonctionnalités
```

1. Créer une branche depuis `main` (`git switch -c fix/...`).
2. Faire des commits signés, en suivant la convention de nommage ci-dessous.
3. Pousser la branche et ouvrir une pull request vers `main` (en brouillon tant que le travail est en cours).
4. Fusionner une fois la pipeline au vert et les discussions résolues.

### Convention des messages de commit

Format : `[TYPE]-> description courte`

| Type | Usage | Exemple |
|---|---|---|
| `[FILE]` | ajout ou import de fichiers | `[FILE]-> Import app.py` |
| `[CONF]` | configuration (CI, Git, outils) | `[CONF]-> ci.yml, scan lint, SAST, SCA` |
| `[FIX]` | correction de bug ou de vulnérabilité | `[FIX]-> Flask 3.1.3 (PYSEC-2023-62)` |
| `[DOCS]` | documentation | `[DOCS]-> README, section versioning` |
| `[STYLE]` | formatage sans changement de comportement | `[STYLE]-> conformité Flake8` |
| `[TEST]` | ajout ou modification de tests | `[TEST]-> tests de la route /password` |

Pour une correction de vulnérabilité, le message cite l'identifiant concerné (CWE, PYSEC, règle Bandit ou Semgrep) et, si une issue existe, la référence en seconde ligne (`Closes #N`).

Les deux commits de documentation du début (`docs: ...`) sont antérieurs à l'adoption de cette convention.

## Sécurisation du code source

### Démarche

1. La pipeline CI a été mise en place **avant** toute correction : sa première exécution sur le code d'origine (PR #2, run CI #1) a échoué sur les 4 analyses et sert de constat initial.
2. Chaque vulnérabilité est corrigée dans un commit dédié, sur la branche `fix/audit-code`. À chaque push, la pipeline se relance et montre l'effet de la correction.
3. Les points que les outils ne voient pas ont été relevés par une relecture manuelle du code.

### Analyses automatiques (pipeline CI)

Fichier : `.github/workflows/ci.yml`. La pipeline s'exécute à chaque pull request vers `main` et à chaque push sur `main`.

| Job | Outil | Type d'analyse | Ce qu'il vérifie |
|---|---|---|---|
| Lint (Flake8) | Flake8 | qualité | style et erreurs de syntaxe (PEP 8) |
| SAST (Bandit) | Bandit | SAST | failles de sécurité connues dans le code Python |
| SAST (Semgrep) | Semgrep (`p/python`, `p/flask`) | SAST | règles de sécurité Python et spécifiques à Flask |
| SCA (pip-audit) | pip-audit | SCA | vulnérabilités connues (CVE, PYSEC) dans les dépendances |

Choix de configuration :

- `permissions: contents: read` : le jeton de la pipeline ne peut que lire le dépôt (moindre privilège).
- `concurrency` avec `cancel-in-progress` : un nouveau push annule l'exécution en cours sur la même branche ; seul le résultat du dernier commit compte.
- Jobs indépendants et parallèles : un échec est immédiatement attribuable à un outil.
- Semgrep tourne dans son image Docker officielle (il ne fonctionne pas nativement sous Windows).
- En complément, **Dependabot** surveille en continu les dépendances du dépôt et ouvre des alertes dans l'onglet *Security*.

### Constat initial

| # | Vulnérabilité | Détectée par | Identifiant | Gravité |
|---|---|---|---|---|
| 1 | Flask 2.2.2 vulnérable | pip-audit, Dependabot | PYSEC-2023-62, PYSEC-2026-2151 | haute |
| 2 | Requêtes HTTP sans timeout | Bandit | B113, CWE-400 | moyenne |
| 3 | Téléchargement des listes à chaque requête (déni de service, dépendance à un site externe) | relecture | CWE-400 | moyenne |
| 4 | Vérification par sous-chaîne : `"a"` déclaré « mauvais mot de passe » | relecture | logique | moyenne |
| 5 | Écoute sur toutes les interfaces, serveur de développement Flask | Bandit, Semgrep | B104, CWE-605 | moyenne |
| 6 | Champ mot de passe en clair (`type="text"`) | relecture | CWE-549 | faible |
| 7 | Formulaire envoyé vers une URL fixe en HTTP | relecture | CWE-319 | faible |
| 8 | Aucune protection CSRF sur le formulaire | relecture | CWE-352 | moyenne |
| 9 | Aucune validation de l'entrée (vide, longueur) | relecture | CWE-20 | faible |
| 10 | Dépendance `requests` utilisée mais non déclarée | relecture | — | faible |
| 11 | 74 écarts de style (indentation, espaces, longueur de ligne) | Flake8 | PEP 8 | — |

### Corrections

| # | Correction | Commit |
|---|---|---|
| 1 | Flask mis à jour en **3.1.3** (version corrigeant les deux vulnérabilités), version figée avec `==`. Le job SCA passe au vert. | `[FIX]-> Flask 3.1.3 (PYSEC-2023-62, PYSEC-2026-2151)` |
| 2, 3, 4, 10 | Listes SecLists **embarquées** dans `app/app/data/` et chargées une seule fois au démarrage dans un `frozenset`, avec une **comparaison exacte**. Plus aucun appel réseau, donc plus de `requests` (dépendance retirée). | `6e86286` `[FIX]-> Listes SecLists embarqués, comparaison exacte` |
| 6, 7, 9 | Formulaire : champ `type="password"`, URL d'envoi générée par `url_for` (relative), `required` et `maxlength`. Validation **côté serveur** : mot de passe vide, absent ou de plus de 128 caractères refusé avec un code `400`. | `3cfa81c` `[FIX]-> formulaire et validation des entrées` |
| 5 | Serveur de production **Gunicorn** (`gunicorn.conf.py`), écoute par défaut sur `127.0.0.1` ; le serveur de développement Flask (`app.run`) est limité à `127.0.0.1`. Bandit et Semgrep ne signalent plus rien. | `28d7853` `[FIX]-> Gunicorn, fin de l'écoute sur 0.0.0.0` |
| 8 | Protection **CSRF** avec Flask-WTF (`CSRFProtect`), jeton caché dans le formulaire, **clé secrète** fournie par l'environnement (obligatoire), cookie de session `Secure`, `HttpOnly`, `SameSite=Lax`. | `676c90e` `[FIX]-> protection CSRF, clé secrète, cookie de session` |
| 11 | Code reformaté selon PEP 8 (indentation de 4 espaces, espaces parasites, lignes vides, longueur de ligne). Aucun changement de comportement. Flake8 ne signale plus rien. | `[STYLE]-> conformité Flake8 (PEP 8)` |

Détails de la correction des listes :

- Les fichiers proviennent d'un **commit figé** de SecLists (`913b327317496d062bcc7cace524aaad8a693be2`) et non de la branche `master`, qui peut changer à tout moment.
- Empreintes SHA-256 vérifiées au téléchargement :

  | Fichier | SHA-256 |
  |---|---|
  | `500-worst-passwords.txt` | `91ae15ff637c9187aa102dc180952840523a5eed024392c5d038e0305e658608` |
  | `10k-most-common.txt` | `68782d6a4a19a4768d5f15dd66bd534e7a33055cc755411e33f16d18c50fdcce` |

- Vérifié : `password` est détecté (liste des 500), `1124` est détecté (liste des 10 000), `a` n'est plus un faux positif.

Détails de la correction du formulaire :

- **Champ masqué** (`type="password"`) : la saisie n'est plus visible à l'écran ni proposée par l'auto-complétion en clair.
- **URL relative** (`url_for('password')`, rendu `/password`) : l'ancien `http://localhost:8080/password` ne fonctionnait qu'en local et forçait le HTTP. L'URL relative suit le protocole de la page, donc HTTPS une fois déployé.
- **Validation côté serveur** : `required` et `maxlength` dans le HTML ne sont qu'un confort, contournable avec `curl`. La vraie vérification est faite dans la route Flask. La limite de 128 caractères évite aussi de traiter des entrées démesurées.
- Vérifié : vide → `400`, champ absent → `400`, 200 caractères → `400`, 128 caractères → `200`, `password` → détecté.

Détails de la correction du serveur (point 5) :

- **Le problème** : `app.run(host='0.0.0.0')` lançait le serveur de développement de Flask, qui n'est pas conçu pour la production (un seul processus, pas de limites, pas de gestion des requêtes bloquées), sur toutes les interfaces réseau de la machine.
- **Gunicorn** (version figée `27.0.0`, sans vulnérabilité connue selon pip-audit) sert l'application en production : `gunicorn main:app`, lancé depuis `app/app/`, lit automatiquement `gunicorn.conf.py`.
- **Adresse d'écoute sûre par défaut** : `127.0.0.1:8080`. Elle n'est ouverte (`0.0.0.0:8080`) que par la variable d'environnement `GUNICORN_BIND`, qui sera définie **uniquement dans l'image Docker**. Un conteneur doit écouter sur toutes ses interfaces pour être joignable ; l'exposition réelle est alors contrôlée par le réseau (security group, load balancer), pas par l'application. Ce choix est explicite et documenté plutôt que masqué par un `# nosec`.
- **Configuration de durcissement** :

  | Paramètre | Valeur | Rôle |
  |---|---|---|
  | `workers` | 2 (variable `GUNICORN_WORKERS`) | plusieurs processus : un worker bloqué ne rend pas le service indisponible |
  | `timeout` | 30 s | une requête bloquée est interrompue et son worker relancé |
  | `limit_request_line` | 4094 octets | ligne de requête limitée |
  | `limit_request_fields` | 50 | nombre d'en-têtes limité |
  | `limit_request_field_size` | 8190 octets | taille d'un en-tête limitée |
  | `accesslog`, `errorlog` | sortie standard | journaux récupérés par Docker puis par AWS |

- Gunicorn ne fonctionne pas sous Windows : il sera testé dans le conteneur Docker, lors de l'étape de la pipeline qui valide l'image.

Détails de la correction CSRF (point 8) :

- **Le risque** : sans protection, un site malveillant peut faire envoyer le formulaire par le navigateur d'un visiteur à son insu (*Cross-Site Request Forgery*).
- **Jeton CSRF** : Flask-WTF (version figée `1.3.0`, sans vulnérabilité connue selon pip-audit) ajoute à chaque formulaire un jeton aléatoire, signé et lié à la session. Toute requête `POST` sans jeton valide est refusée avec un code `400`. Un autre site ne peut pas lire ce jeton, donc ne peut pas forger la requête.
- **Clé secrète** (`SECRET_KEY`) : elle signe les jetons et le cookie de session. Elle n'est **jamais écrite dans le code ni dans le dépôt** : elle est lue dans l'environnement et sera fournie en production par un gestionnaire de secrets AWS. Si elle est absente, l'application **refuse de démarrer** (*fail fast*) plutôt que de tourner avec une clé faible ou prévisible.
- **Cookie de session durci** :

  | Attribut | Effet |
  |---|---|
  | `HttpOnly` | illisible par JavaScript, ce qui limite le vol de session en cas de faille XSS |
  | `SameSite=Lax` | non envoyé par les requêtes `POST` venant d'autres sites (seconde barrière contre le CSRF) |
  | `Secure` | envoyé uniquement en HTTPS ; désactivable en local avec `SESSION_COOKIE_SECURE=false` |

- Vérifié : sans `SECRET_KEY` → démarrage refusé ; `POST` sans jeton → `400` ; jeton falsifié → `400` ; jeton valide → réponse normale ; cookie émis avec `Secure; HttpOnly; SameSite=Lax`.

Lancer l'application en local (développement, HTTP) :

```bash
cd app/app
SECRET_KEY=$(python -c "import secrets; print(secrets.token_hex(32))") SESSION_COOKIE_SECURE=false python main.py
```

Détails de la correction du style (point 11) :

- Les 74 remarques Flake8 d'origine venaient surtout d'une indentation à 2 espaces, d'espaces en fin de ligne et de lignes vides manquantes. Une partie a disparu au fil des corrections précédentes, le code réécrit étant déjà conforme ; les 24 restantes ont été corrigées dans un commit à part.
- Ce reformatage est volontairement **isolé** des corrections de sécurité : les diffs de sécurité restent lisibles, et ce commit ne change aucun comportement (vérifié : mêmes réponses sur `/`, `password`, `1124`, `a` et mot de passe vide).
- La longueur de ligne par défaut de PEP 8 (79 caractères) est conservée ; les longs messages sont découpés en chaînes concaténées.

### Bilan de l'audit du code

| Job de la pipeline | Constat initial (run CI #1) | Après corrections |
|---|---|---|
| Lint (Flake8) | ❌ 74 remarques | ✅ 0 |
| SAST (Bandit) | ❌ 3 problèmes (B113 ×2, B104) | ✅ 0 |
| SAST (Semgrep) | ❌ 1 problème (`avoid_app_run_with_bad_host`) | ✅ 0 |
| SCA (pip-audit) | ❌ Flask 2.2.2 vulnérable | ✅ aucune vulnérabilité connue |

Les 11 problèmes relevés (outils et relecture manuelle) sont corrigés.

## Image Docker et pipeline CI

### Le Dockerfile

L'image est construite en **deux étapes** (*multi-stage build*) à partir d'une même image de base :

1. **`builder`** : crée un environnement virtuel `/opt/venv` et y installe les dépendances de `requirements.txt`.
2. **`runtime`** : image finale, qui ne reçoit que l'environnement virtuel et le code de l'application.

| Mesure | Détail | Pourquoi |
|---|---|---|
| Image de base minimale | `python:3.13.18-slim-trixie` | moins de paquets système, donc moins de vulnérabilités et de surface d'attaque |
| Base figée par **digest** | `@sha256:e48f59cd…` | l'image construite est toujours la même ; une image modifiée sur le registre ne correspondrait plus à l'empreinte |
| Utilisateur dédié **non root** | `app`, uid 10001, sans shell (`nologin`) ni répertoire personnel | un attaquant qui prendrait le contrôle de l'application n'aurait aucun privilège |
| Code en lecture seule | fichiers appartenant à `root`, l'utilisateur `app` ne peut que les lire | l'application ne peut pas modifier son propre code |
| **pip retiré** de l'image finale | désinstallé du système et de l'environnement virtuel | rien ne peut être installé dans le conteneur en production |
| Pas de cache pip | `--no-cache-dir` | image plus petite, pas de fichiers inutiles |
| Secrets absents de l'image | `SECRET_KEY` fournie au lancement uniquement | une image publiée ou volée ne contient aucun secret |
| Serveur de production | `CMD ["gunicorn", "main:app"]`, `GUNICORN_BIND=0.0.0.0:8080` | voir la correction du point 5 ; seul le conteneur ouvre l'écoute |
| `HEALTHCHECK` | requête sur `/` toutes les 30 s | Docker, puis AWS, détectent un conteneur qui ne répond plus |
| `.dockerignore` en liste blanche | seul `app/app/` est envoyé au build | `.git`, `.venv`, la configuration CI ou un éventuel fichier de secrets ne peuvent pas entrer dans l'image par erreur |
| Métadonnées OCI | `LABEL org.opencontainers.image.*` | traçabilité de l'image vers le dépôt source |

### Les jobs Docker de la pipeline

```
Lint Dockerfile (Hadolint)

Build (image Docker) ──┬── Tests du conteneur
                       ├── Scan image (Trivy)
                       └── Scan image (Dockle)
```

L'image est construite **une seule fois** (`docker build --pull --no-cache`), exportée en fichier (`docker save`) et transmise aux trois jobs suivants comme artefact (conservé 1 jour). Les tests et les scans portent donc exactement sur la même image.

| Job | Outil | Ce qu'il vérifie | Échoue si |
|---|---|---|---|
| Lint Dockerfile | Hadolint `v2.15.1` | bonnes pratiques d'écriture du Dockerfile | une règle Hadolint n'est pas respectée |
| Build | Docker | l'image se construit | erreur de construction |
| Tests du conteneur | `tests/container/smoke_test.sh` | fonctionnement et durcissement réels du conteneur (voir ci-dessous) | un test échoue |
| Scan image (Trivy) | Trivy `0.76.2` | vulnérabilités des paquets système et Python de l'image | vulnérabilité **HIGH** ou **CRITICAL** ayant un correctif |
| Scan image (Dockle) | Dockle `v0.4.15` | conformité au CIS Docker Benchmark | alerte de niveau **WARN** ou plus |

Trivy utilise `--ignore-unfixed` : une vulnérabilité sans correctif publié ne peut pas être corrigée par une mise à jour, la bloquer empêcherait toute livraison sans gain de sécurité. Elle reste visible dans le rapport.

### Tests du conteneur

Le conteneur est lancé **comme en production, durci** : système de fichiers en lecture seule (`--read-only`, seul `/tmp` est inscriptible), aucune capacité Linux (`--cap-drop ALL`), pas d'élévation de privilèges (`no-new-privileges`), et une `SECRET_KEY` aléatoire générée pour le test.

| # | Test | Résultat attendu |
|---|---|---|
| 1 | Démarrage sans `SECRET_KEY` | refusé |
| 2 | Requête sur `/` | Gunicorn répond |
| 3 | `id -u` dans le conteneur | différent de 0 (non root) |
| 4 | `python -m pip` | absent |
| 5 | Écriture dans `/app/main.py` | impossible |
| 6 | `POST /password` sans jeton CSRF | `400` |
| 7 | Formulaire, jeton CSRF et mot de passe `password` | champ masqué, mot de passe détecté |
| 8 | Mot de passe vide avec jeton valide | `400` |

### Sécurité de la chaîne CI elle-même

- **Actions figées par SHA** (`actions/checkout@3d3c42e…  # v7.0.1`) : un tag peut être déplacé vers du code malveillant, une empreinte de commit non. Les versions sont rappelées en commentaire.
- **Outils figés par version** (Flake8, Bandit, pip-audit, Semgrep, Hadolint, Trivy, Dockle) : un même code donne toujours le même résultat de scan.
- **`persist-credentials: false`** : le jeton GitHub n'est pas laissé dans le dépôt cloné, les étapes suivantes ne peuvent pas le réutiliser.
- **Dependabot** (`.github/dependabot.yml`) propose chaque semaine les mises à jour des dépendances Python, de l'image de base et des actions. Chaque mise à jour arrive en pull request et doit passer les checks obligatoires.
