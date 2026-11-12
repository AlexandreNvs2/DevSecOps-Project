# DevSecOps-Project

Challenge final DevSecOps : intégrer et déployer de manière sécurisée une application Python (Flask) dans une pipeline CI/CD, en appliquant les principes DevSecOps.

## Sommaire

1. [Contenu du dépôt](#contenu-du-dépôt)
2. [Gestion sécurisée du versioning](#gestion-sécurisée-du-versioning)
3. [Sécurisation du code source](#sécurisation-du-code-source)
4. [Image Docker et pipeline CI](#image-docker-et-pipeline-ci)
5. [Déploiement sécurisé sur AWS](#déploiement-sécurisé-sur-aws) *(en cours)*
6. [Stockage sécurisé des mots de passe](#stockage-sécurisé-des-mots-de-passe)
7. Architecture et cycle de vie sécurisé *(à venir)*

## Contenu du dépôt

- `app/app/main.py` : application Flask (vérification d'un mot de passe, création de compte, connexion).
- `app/app/security.py` : hachage Argon2id et règles de validation des identifiants et mots de passe.
- `app/app/models.py` : modèle utilisateur et accès à la base de données (SQLAlchemy).
- `app/app/templates/` : pages HTML (Jinja2, échappement automatique).
- `app/app/data/` : listes SecLists embarquées (500 et 10 000 mots de passe les plus courants).
- `app/app/gunicorn.conf.py` : configuration du serveur de production Gunicorn.
- `app/app/requirements.txt` : dépendances Python, versions figées.
- `Dockerfile` : construction de l'image Docker (multi-étapes, durcie).
- `.dockerignore` : liste blanche des fichiers envoyés au build Docker.
- `tests/unit/` : tests unitaires (pytest).
- `tests/container/smoke_test.sh` : tests de fonctionnement et de sécurité du conteneur.
- `infra/bootstrap/` : stockage de l'état Terraform : script de création des buckets S3 (`create-buckets.sh`), Terraform de leur configuration de sécurité (clé KMS, chiffrement, versioning, journaux d'accès) et ses tests.
- `.github/workflows/ci.yml` : pipeline CI GitHub Actions.
- `.github/dependabot.yml` : mises à jour automatiques des dépendances, de l'image de base, des actions et des fournisseurs Terraform.
- `CLAUDE.md` : contexte du projet pour l'assistant IA Claude Code (règles de travail, état d'avancement, contraintes AWS). Il permet de reprendre le travail sur une autre machine et documente de façon transparente l'usage de l'IA : l'assistant a rédigé le code et la documentation en expliquant chaque choix ; les commits, les push, les fusions et la configuration GitHub ont été faits par l'auteur.

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
| Require status checks to pass | une PR ne peut être fusionnée que si les jobs obligatoires de la pipeline réussissent |
| Require branches to be up to date | la PR doit être testée sur la dernière version de `main` avant la fusion |

**Nombre d'approbations requis : 0.** Le projet est réalisé seul et GitHub interdit d'approuver sa propre pull request ; exiger une approbation bloquerait toute fusion. Dans une équipe, ce nombre serait fixé à au moins 1.

**Vérifications obligatoires** (*required status checks*), ajoutées au fur et à mesure que chaque job de la pipeline est au vert :

| Check obligatoire | Rôle | Ajouté après |
|---|---|---|
| `Lint (Flake8)` | qualité du code | PR #2 (audit du code) |
| `SAST (Bandit)` | analyse statique de sécurité | PR #2 |
| `SAST (Semgrep)` | analyse statique de sécurité | PR #2 |
| `SCA (pip-audit)` | vulnérabilités des dépendances | PR #2 |
| `Lint Dockerfile (Hadolint)` | bonnes pratiques du Dockerfile | PR #4 (image Docker) |
| `Build (image Docker)` | construction de l'image | PR #4 |
| `Tests du conteneur` | fonctionnement et durcissement du conteneur | PR #4 |
| `Scan image (Trivy)` | vulnérabilités de l'image | PR #4 |
| `Scan image (Dockle)` | CIS Docker Benchmark | PR #4 |
| `Tests unitaires (pytest)` | logique de l'application, stockage des mots de passe | PR du stockage des mots de passe |
| `IaC Terraform (fmt, validate, test)` | format, validité et tests de l'infrastructure | PR du backend Terraform |
| `IaC (Checkov)` | mauvaises configurations de l'infrastructure | PR du backend Terraform |

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
| Image de base minimale | `python:3.15.0-slim-trixie` | moins de paquets système, donc moins de vulnérabilités et de surface d'attaque |
| Base figée par **digest** | `@sha256:f5b92f2a…` | l'image construite est toujours la même ; une image modifiée sur le registre ne correspondrait plus à l'empreinte |
| Utilisateur dédié **non root** | `app`, uid 10001, sans shell (`nologin`) ni répertoire personnel ; déclaré par identifiant numérique (`USER 10001:10001`) | un attaquant qui prendrait le contrôle de l'application n'aurait aucun privilège ; l'identifiant numérique permet de vérifier « non root » sans lire `/etc/passwd` (Hadolint DL3066) |
| Code en lecture seule | fichiers appartenant à `root`, l'utilisateur `app` ne peut que les lire | l'application ne peut pas modifier son propre code |
| **pip retiré** de l'image finale | désinstallé du système et de l'environnement virtuel | rien ne peut être installé dans le conteneur en production |
| Bits **setuid/setgid retirés** | `find / -xdev -perm /6000 -exec chmod a-s` | aucun binaire (`su`, `passwd`, `mount`…) ne peut s'exécuter avec les droits root |
| Correctifs Debian appliqués | `zlib1g`, `apt` et `libapt-pkg7.0` mis à jour en versions corrigées figées | voir les corrections ci-dessous |
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
| Scan image (Dockle) | Dockle `v0.4.15` | conformité au CIS Docker Benchmark | alerte de niveau **WARN** ou plus (une exception justifiée, voir ci-dessous) |

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
| 6 | Fichiers dans `/var/lib/apt/lists` | aucun (cache apt vide) |
| 7 | Binaires setuid/setgid | aucun |
| 8 | `POST /password` sans jeton CSRF | `400` |
| 9 | Formulaire, jeton CSRF et mot de passe `password` | champ masqué, mot de passe détecté |
| 10 | Mot de passe vide avec jeton valide | `400` |

### Corrections issues de la première exécution

Sur la première exécution de la pipeline (PR `feat/docker`), le build et les tests du conteneur étaient au vert, mais les trois scanners ont bloqué :

| Outil | Constat | Correction |
|---|---|---|
| Hadolint | `DL3066` (info) : `USER app`, utilisateur désigné par son nom | `USER 10001:10001` : l'identifiant numérique permet de vérifier « non root » sans lire `/etc/passwd` |
| Trivy | 2 vulnérabilités **HIGH** dans `zlib1g` `1:1.3.dfsg+really1.3.1-1+b1` (CVE-2026-85091, débordement de tas dans `gz_vacate()` permettant l'exécution de code ; CVE-2026-76844), corrigées dans `…-1+deb13u1`, publiée après l'image de base. Toutes les dépendances Python : 0 vulnérabilité. | Mise à jour ciblée de `zlib1g` vers la version corrigée **figée**, plutôt qu'un `apt-get upgrade` global non reproductible. À retirer quand Dependabot proposera une image de base qui l'inclut. |
| Dockle | `DKL-DI-0005` (FATAL) : cache apt non vidé | **Faux positif**, ignoré explicitement (`--ignore DKL-DI-0005`). La couche signalée est celle de l'image officielle Python, qui vide le cache avec `apt-get dist-clean`, commande que Dockle v0.4.15 ne reconnaît pas. L'absence de cache apt est **prouvée** par le test n° 6 du conteneur. |
| Dockle | `CIS-DI-0008` (info) : 11 binaires setuid/setgid (`su`, `passwd`, `mount`…) | Non bloquant, mais corrigé par défense en profondeur : bits retirés dans l'image, vérifié par le test n° 7. |
| Dockle | `CIS-DI-0005` (info) : Docker Content Trust non activé | Non bloquant, non appliqué : Docker Content Trust (Notary v1) est abandonné. L'intégrité de l'image de base est garantie par son **digest** figé dans le `Dockerfile`. |

Une alerte n'est jamais masquée sans justification : chaque exception est commentée dans `ci.yml`, documentée ici, et couverte par un test qui prouve que le risque est absent.

### Passage à Python 3.15 (PR Dependabot #5)

Dependabot a proposé l'image `python:3.15.0-slim-trixie`. Tous les checks passaient (tests unitaires et tests du conteneur compris), sauf Trivy :

| Outil | Constat | Correction |
|---|---|---|
| Trivy | 2 vulnérabilités **HIGH** : `apt` et `libapt-pkg7.0` `3.0.3` (CVE-2026-109518, exécution de code à distance par réutilisation de liens physiques pendant le téléchargement des paquets), corrigées en `3.0.4`. L'image 3.15.0 a été construite avant ce correctif, alors que l'image 3.13.18 l'incluait déjà. | Même méthode que pour `zlib1g` : mise à jour ciblée vers la version corrigée **figée** (`apt=3.0.4`, `libapt-pkg7.0=3.0.4`). À retirer quand Dependabot proposera une image 3.15 qui l'inclut. |

La PR Dependabot n'a pas été fusionnée telle quelle : la montée de version et le correctif sont regroupés dans la branche `fix/python-3.15`, et la version de Python des jobs CI (lint, tests, SAST, SCA) passe aussi à 3.15 pour analyser le code avec la même version que l'image. La ligne `zlib1g` reste nécessaire : l'image 3.15.0 contient toujours la version vulnérable.

### Sécurité de la chaîne CI elle-même

- **Actions figées par SHA** (`actions/checkout@3d3c42e…  # v7.0.1`) : un tag peut être déplacé vers du code malveillant, une empreinte de commit non. Les versions sont rappelées en commentaire.
- **Outils figés par version** (Flake8, Bandit, pip-audit, Semgrep, Hadolint, Trivy, Dockle) : un même code donne toujours le même résultat de scan.
- **`persist-credentials: false`** : le jeton GitHub n'est pas laissé dans le dépôt cloné, les étapes suivantes ne peuvent pas le réutiliser.
- **Dependabot** (`.github/dependabot.yml`) propose chaque semaine les mises à jour des dépendances Python, de l'image de base et des actions. Chaque mise à jour arrive en pull request et doit passer les checks obligatoires.

## Déploiement sécurisé sur AWS

### Environnement et contraintes

Le déploiement cible un compte **AWS Academy Learner Lab**, région `us-east-1`. Ce bac à sable impose des limites qui orientent plusieurs choix :

| Contrainte du lab | Conséquence | En production |
|---|---|---|
| Identifiants **temporaires** (environ 4 h), renouvelés à chaque session | stockés dans `~/.aws/credentials` en local et dans les secrets GitHub pour la pipeline, à renouveler à chaque session ; jamais écrits dans le dépôt | fédération **OIDC** GitHub → AWS : aucun identifiant stocké, jeton de courte durée par exécution |
| Création de **rôles IAM** et de fournisseur OIDC interdite | utilisation du rôle imposé `LabRole` pour ECS ; pas de réplication S3 inter-régions | un rôle par usage (exécution ECS, tâche, déploiement), chacun limité au strict nécessaire |
| Pas de nom de domaine | HTTPS avec un certificat **auto-signé** importé dans ACM (avertissement du navigateur) | certificat ACM validé par DNS sur un domaine de l'entreprise |
| Une **SCP** (politique de l'organisation AWS Academy) refuse `s3:GetBucketObjectLockConfiguration` | les buckets S3 sont créés par un script AWS CLI ; Terraform applique toute leur configuration de sécurité (voir l'étape 1) | ressource `aws_s3_bucket` gérée entièrement par Terraform |
| Budget limité | un seul NAT Gateway au lieu d'un par zone ; infrastructure détruite en fin de session (`terraform destroy`) | un NAT par zone pour la haute disponibilité |

### Architecture cible

L'infrastructure est entièrement décrite en **Terraform** (*Infrastructure as Code*) : elle est relue en pull request, analysée par Checkov et reproductible.

- **Réseau** : VPC sur 2 zones de disponibilité ; sous-réseaux publics pour l'ALB, privés pour ECS et RDS ; NAT Gateway pour les sorties (ECR, Secrets Manager, CloudWatch).
- **Entrée** : Application Load Balancer en **HTTPS** (HTTP redirigé vers HTTPS), protégé par **AWS WAF** (règles gérées AWS et limitation de débit sur `/login` contre la force brute).
- **Application** : **ECS Fargate**, 2 tâches réparties sur 2 zones ; leur groupe de sécurité n'accepte que le trafic venant de l'ALB.
- **Base de données** : **RDS PostgreSQL** chiffré, privé, n'acceptant que les tâches ECS. Mot de passe généré et stocké par AWS dans Secrets Manager (`manage_master_user_password`), jamais connu de Terraform.
- **Secrets** : **Secrets Manager** pour `SECRET_KEY` et le mot de passe de la base, injectés dans les conteneurs au démarrage (jamais dans l'image ni dans le dépôt).
- **Images** : **ECR** avec scan à l'envoi et tags immuables (une image publiée ne peut pas être remplacée).
- **Journaux** : **CloudWatch Logs** pour les conteneurs.

Le schéma d'architecture complet sera ajouté une fois l'infrastructure déployée.

### Plan de réalisation

Le déploiement est découpé en trois pull requests, chacune analysée par la pipeline :

| Étape | Branche | Contenu | Critère |
|---|---|---|---|
| 1 | `feat/terraform-backend` | stockage sécurisé de l'état Terraform, jobs Terraform et Checkov dans la CI | prérequis |
| 2 | `feat/aws-infra` | réseau, ALB et WAF, ECS Fargate, RDS, Secrets Manager, ECR, CloudWatch | application déployée dans le cloud |
| 3 | `ci/deploy` | pipeline de déploiement sur `main` : push de l'image vers ECR, `terraform apply`, puis analyse dynamique (DAST) avec **OWASP ZAP** sur l'URL publique | déploiement sécurisé depuis la CI/CD |

### Étape 1 : stockage sécurisé de l'état Terraform

Terraform enregistre dans un **état** (*state*) la description de toute l'infrastructure qu'il gère. Cet état peut contenir des données sensibles (la `SECRET_KEY` générée, la clé privée du certificat auto-signé) : le laisser sur un poste ou le versionner dans Git serait une fuite de secrets. Il est donc stocké dans un bucket S3 dédié, partagé par le poste de développement et la pipeline.

Ce bucket est mis en place une seule fois par `infra/bootstrap/`, dont l'état reste local (il ne contient aucun secret, et ce module ne peut pas stocker son état dans un bucket qui n'existe pas encore).

| Mesure | Détail | Pourquoi |
|---|---|---|
| Chiffrement **KMS** | clé dédiée `alias/devsecops-tfstate`, rotation annuelle | les secrets de l'état sont illisibles sans droit sur la clé |
| **Versioning** | anciennes versions conservées 90 jours | retour arrière après une erreur ou une corruption de l'état |
| **Accès public bloqué** | les 4 options de *Block Public Access*, ACL désactivées (`BucketOwnerEnforced`) | l'état ne peut jamais devenir public, même par erreur |
| **HTTPS obligatoire** | politique refusant toute requête avec `aws:SecureTransport = false` | pas d'interception de l'état en transit |
| **Journaux d'accès** | bucket de journaux séparé, conservés 1 an | chaque lecture ou écriture de l'état est tracée |
| **Verrouillage** | verrouillage natif S3 (`use_lockfile`, Terraform ≥ 1.10) | deux `terraform apply` simultanés (poste et CI) ne peuvent pas corrompre l'état |
| Protection contre la suppression | buckets hors du périmètre de Terraform ; `prevent_destroy` sur la clé KMS | un `terraform destroy` ne peut ni effacer l'état, ni supprimer la clé sans laquelle il serait illisible |
| Nom sans donnée du compte dans le dépôt | numéro de compte lu à l'exécution (`aws_caller_identity`) | aucune information du compte AWS n'est versionnée |

Mise en place (une seule fois, identifiants du lab chargés) :

```bash
cd infra/bootstrap
./create-buckets.sh
terraform init
terraform apply
```

#### Correction : refus d'une SCP du Learner Lab

La première version créait les buckets avec la ressource Terraform `aws_s3_bucket`. Au premier `terraform apply`, la clé KMS a été créée, puis les deux buckets ont échoué :

```text
Error: reading S3 Bucket (devsecops-tfstate-…) object lock configuration:
AccessDenied: … is not authorized to perform: s3:GetBucketObjectLockConfiguration
… with an explicit deny in a service control policy
```

Le fournisseur Terraform AWS relit la configuration *Object Lock* de chaque bucket qu'il gère, après la création puis à chaque `plan`. Une **SCP** (*Service Control Policy*) de l'organisation AWS Academy refuse explicitement cette lecture : aucune permission IAM ne peut lever ce refus, et l'option n'est pas désactivable dans le fournisseur. Les buckets avaient bien été créés, mais marqués *tainted* (à recréer) dans l'état.

Correction :

- les buckets sont créés par `create-buckets.sh` (AWS CLI, idempotent : un bucket existant n'est pas recréé). Un bucket S3 neuf a par défaut l'accès public bloqué, les ACL désactivées et un chiffrement SSE-S3 ;
- Terraform applique ensuite **toute** la configuration de sécurité (chiffrement KMS, versioning, politiques, journaux, cycle de vie), dont la lecture est autorisée par la SCP ;
- les deux buckets *tainted* ont été retirés de l'état (`terraform state rm`), sans être supprimés d'AWS ;
- effet de bord positif : Terraform ne gérant plus les buckets, un `terraform destroy` ne peut pas les supprimer.

### Sécurité de l'Infrastructure as Code dans la CI

Deux jobs analysent le dossier `infra/` à chaque pull request, sans aucun identifiant AWS :

| Job | Outil | Ce qu'il vérifie |
|---|---|---|
| `IaC Terraform (fmt, validate, test)` | Terraform 1.17.1 | format du code, validité de la configuration, tests `terraform test` avec un fournisseur AWS **simulé** (`mock_provider`) |
| `IaC (Checkov)` | Checkov 3.4.4 | mauvaises configurations de sécurité (chiffrement, accès public, journalisation…) selon les bonnes pratiques AWS et CIS |

Les fournisseurs Terraform sont figés par version et par **empreinte** dans `.terraform.lock.hcl` (versionné, vérifié avec `-lockfile=readonly`) : un fournisseur modifié sur le registre serait refusé. Dependabot propose leurs mises à jour.

Résultat Checkov sur le module `bootstrap` : **21 contrôles réussis, 0 échec, 0 exception**.

Limite assumée : la plupart des contrôles S3 de Checkov s'appliquent à la ressource `aws_s3_bucket`, absente depuis la correction ci-dessus. La première version, qui l'utilisait, obtenait 36 contrôles réussis et 6 exceptions justifiées (réplication inter-régions impossible sans rôle IAM, pas de consommateur de notifications, bucket de journaux qui ne peut pas se journaliser lui-même ni être chiffré en KMS). Les garanties que Checkov vérifiait sur le bucket sont désormais **prouvées par les tests** de `infra/bootstrap/tests/bootstrap.tftest.hcl` :

| Garantie | Test |
|---|---|
| nom du bucket dérivé du numéro de compte | `etat_protege` |
| versioning activé, chiffrement KMS, rotation de la clé | `etat_protege` |
| accès public bloqué (4 options), ACL désactivées | `etat_protege`, `journaux_proteges` |
| accès hors HTTPS refusés | `etat_protege`, `journaux_proteges` |
| accès à l'état journalisés | `etat_protege` |
| journaux chiffrés (SSE-S3) et écrits uniquement par le service de journalisation pour le bucket de l'état | `journaux_proteges` |

## Stockage sécurisé des mots de passe

### Fonctionnalité

L'application permet désormais de **créer un compte** (`/register`), de **se connecter** (`/login`) et de **se déconnecter** (`/logout`). Les mots de passe des utilisateurs sont stockés en base de données sous forme d'**empreinte Argon2id**, jamais en clair.

### Pourquoi Argon2id

| Option | Problème |
|---|---|
| Stockage en clair | une fuite de la base expose directement tous les mots de passe |
| Chiffrement (AES…) | réversible : qui obtient la clé obtient tous les mots de passe |
| Hachage rapide (MD5, SHA-256) | un GPU teste des milliards de candidats par seconde |
| **Argon2id** | fonction **lente et gourmande en mémoire**, conçue pour les mots de passe ; gagnante de la *Password Hashing Competition* (2015), recommandée par l'OWASP et standardisée par la RFC 9106 |

Implémentation : bibliothèque `argon2-cffi` (`25.1.0`), profil **RFC 9106 « low memory »** :

| Paramètre | Valeur | Effet |
|---|---|---|
| Variante | Argon2id | résiste à la fois aux attaques par GPU et par canaux auxiliaires |
| Mémoire | 64 Mio par calcul | rend les attaques massives sur GPU ou ASIC très coûteuses |
| Itérations | 3 | augmente le temps de calcul |
| Parallélisme | 4 | |
| Sel | 16 octets aléatoires par mot de passe | deux utilisateurs ayant le même mot de passe ont des empreintes différentes ; les tables précalculées sont inutiles |

L'empreinte stockée contient l'algorithme, les paramètres et le sel (`$argon2id$v=19$m=65536,t=3,p=4$<sel>$<hash>`) : la vérification n'a besoin de rien d'autre. **Mise à jour transparente** : si les paramètres sont renforcés plus tard, l'empreinte d'un utilisateur est recalculée automatiquement à sa prochaine connexion réussie (`check_needs_rehash`).

### Politique de mot de passe

Inspirée du **NIST SP 800-63B** : on privilégie la longueur et le refus des mots de passe connus plutôt que des règles de composition (majuscule, chiffre…) qui poussent à des mots de passe prévisibles.

| Règle | Valeur |
|---|---|
| Longueur minimale | 12 caractères |
| Longueur maximale | 128 caractères (évite de faire calculer Argon2 sur des entrées démesurées) |
| Mots de passe courants refusés | les 10 000 de SecLists, déjà embarqués dans l'application |
| Mot de passe identique à l'identifiant | refusé |
| Confirmation | les deux saisies doivent correspondre |
| Identifiant | 3 à 32 caractères `[a-z0-9_.-]`, normalisé en minuscules (pas de doublons `Alice` / `alice`) |

La fonctionnalité d'origine de l'application (vérifier un mot de passe dans les listes SecLists) sert ainsi directement à protéger les comptes.

### Protection de la connexion

| Mesure | Détail |
|---|---|
| Pas d'énumération des comptes | même message et même code (`401`) que l'identifiant existe ou non |
| Temps de réponse constant | si le compte n'existe pas, une vérification Argon2 factice est quand même calculée : on ne peut pas deviner les comptes existants en mesurant le temps de réponse |
| Fixation de session | la session est entièrement réinitialisée à la connexion |
| CSRF | tous les formulaires (inscription, connexion, déconnexion) portent un jeton CSRF ; la déconnexion se fait en `POST` |
| Cookie de session | `Secure`, `HttpOnly`, `SameSite=Lax` (voir le point 8 de l'audit du code) |

La limitation du nombre de tentatives (force brute) sera assurée au niveau de l'infrastructure, par une règle de limitation de débit du **WAF AWS** placé devant le load balancer : un compteur en mémoire dans l'application ne serait pas partagé entre les workers et les conteneurs.

### Base de données

- Accès par **SQLAlchemy** (`2.1.8`) : toutes les requêtes sont **paramétrées** par l'ORM, aucune concaténation de chaînes dans du SQL, donc pas d'injection SQL.
- Adresse de la base fournie par la variable d'environnement **`DATABASE_URL`**, obligatoire comme `SECRET_KEY` (l'application refuse de démarrer sans elle). Aucun mot de passe de base de données dans le code.
- **SQLite** en développement, dans les tests unitaires et dans les tests du conteneur ; **PostgreSQL** (AWS RDS, chiffré) en production, via le pilote `psycopg` (`3.3.8`). Le même code fonctionne avec les deux.
- Gunicorn charge l'application une seule fois avant de créer ses workers (`preload_app`) : les tables ne sont créées qu'une fois, et le pool de connexions est vidé avant la création des workers pour qu'aucune connexion ne soit partagée entre eux.

Lancer l'application en local :

```bash
cd app/app
SECRET_KEY=$(python -c "import secrets; print(secrets.token_hex(32))") DATABASE_URL=sqlite:///dev.db SESSION_COOKIE_SECURE=false python main.py
```

### Tests

**Tests unitaires** (`tests/unit/`, job `Tests unitaires (pytest)`) :

| Test | Vérifie |
|---|---|
| `test_register_stores_argon2id_hash_not_password` | l'empreinte stockée est en Argon2id, avec les bons paramètres, et ne contient pas le mot de passe |
| `test_same_password_gives_different_hashes` | le sel est bien aléatoire |
| `test_register_rejects_common_password` | un mot de passe des listes SecLists est refusé et rien n'est stocké |
| `test_register_rejects_short_password`, `..._equal_to_username`, `..._mismatched_confirmation`, `..._invalid_username` | la politique de mot de passe et d'identifiant |
| `test_register_rejects_duplicate_username` | doublon refusé (`409`), y compris en changeant la casse |
| `test_login_success_opens_session` | connexion valide |
| `test_login_wrong_password_and_unknown_user_same_answer` | réponses identiques : pas d'énumération |
| `test_logout_clears_session` | déconnexion |
| `test_login_rehashes_outdated_hash` | une empreinte aux anciens paramètres est recalculée à la connexion |
| `test_password_check_*` | la fonctionnalité d'origine (listes SecLists, validation des entrées) |

Le job Flake8 analyse aussi désormais le dossier `tests/`.

**Tests du conteneur** : `smoke_test.sh` vérifie en plus le refus de démarrer sans `DATABASE_URL`, puis, dans le conteneur durci, la création d'un compte (`201`), le refus d'un mauvais mot de passe (`401`) et la connexion (`302`), avec les jetons CSRF.
