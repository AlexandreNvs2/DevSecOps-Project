# CLAUDE.md : contexte du projet pour Claude Code

Ce fichier est lu automatiquement par Claude Code au démarrage d'une session dans ce dépôt. Il permet de reprendre le travail sur une autre machine sans perdre le contexte. Il documente aussi, de façon transparente, la manière dont l'IA est utilisée dans ce projet.

## Le projet

Challenge final DevSecOps (60 pts, environ 10 h prévues) : intégrer et déployer de manière sécurisée une application Python (Flask) dans une pipeline CI/CD. Sept critères :

| Critère | Points | État |
|---|---|---|
| Application déployée dans le Cloud, accessible depuis Internet | 5 | à faire (AWS) |
| Sécurisation du code source | 10 | fait (PR #2) |
| Image Docker construite et sécurisée dans la CI | 10 | fait (PR #4) |
| Déploiement sécurisé depuis une pipeline CI/CD | 10 | à faire (AWS) |
| Stockage sécurisé des mots de passe | 10 | fait (PR #6) |
| README : architecture (schéma), cycle de vie sécurisé, justifications | 10 | tenu à jour à chaque étape ; schéma d'architecture à faire |
| Versioning et collaboration, maîtrise des accès | 5 | fait (signature, ruleset, checks obligatoires) |

Énoncé et activités du cours : https://ready-player-school.notion.site/272f3a8bf3b68212863b0175bfcb4a52 (pages publiques Notion, à lire avec un navigateur).

## Règles de travail (à respecter)

- **Convention de commit** : `[TYPE]-> description`, types `[FILE]`, `[CONF]`, `[FIX]`, `[DOCS]`, `[STYLE]`, `[TEST]`. Pour une correction de sécurité, citer l'identifiant (CWE, CVE, PYSEC, règle Bandit, Semgrep, Hadolint, Dockle).
- **Une branche par étape** (`feat/…`, `fix/…`, `docs/…`, `ci/…`) partant d'un `main` à jour. La doc de l'étape va dans la même branche et la même PR. Ouvrir la PR en brouillon, la passer en « Ready for review » quand tous les checks sont verts, fusionner en **merge commit** (pas de squash : le README cite des hash de commits).
- **Ne jamais masquer une alerte de scan sans justification** : une exception est commentée dans le code, documentée dans le README et couverte par un test qui prouve que le risque est absent.
- Répondre en **français**.

## Protection du dépôt

- GitHub : https://github.com/AlexandreNvs2/DevSecOps-Project, CI/CD avec **GitHub Actions** (le cours utilisait GitLab ; choix assumé et documenté).
- Ruleset `protect-main` sur `main`, sans aucune exception : PR obligatoire (0 approbation, projet réalisé seul), **commits signés** (SSH ed25519), pas de force push ni de suppression, discussions résolues, fusion par merge ou squash (pas de rebase), branche à jour et **checks obligatoires**.
- Checks obligatoires actuels : `Lint (Flake8)`, `SAST (Bandit)`, `SAST (Semgrep)`, `SCA (pip-audit)`, `Lint Dockerfile (Hadolint)`, `Build (image Docker)`, `Tests du conteneur`, `Scan image (Trivy)`, `Scan image (Dockle)`, `Tests unitaires (pytest)` (10 checks, vérifié le 12 novembre 2026). **À ajouter** après fusion de `feat/terraform-backend` : `IaC Terraform (fmt, validate, test)` et `IaC (Checkov)`.
- Dependabot actif (pip, image Docker, actions GitHub).

## Architecture actuelle

- `app/app/main.py` : Flask (vérification d'un mot de passe dans SecLists, inscription, connexion, déconnexion), CSRF (Flask-WTF), cookie de session durci.
- `app/app/security.py` : Argon2id (argon2-cffi, profil RFC 9106 low memory), politique de mot de passe (NIST SP 800-63B), protection contre l'énumération des comptes.
- `app/app/models.py` : SQLAlchemy 2 ; SQLite en local et en test, PostgreSQL (psycopg) prévu sur AWS RDS.
- Variables d'environnement **obligatoires** : `SECRET_KEY`, `DATABASE_URL` (l'application refuse de démarrer sans elles). `SESSION_COOKIE_SECURE=false` seulement en local (HTTP).
- `app/app/gunicorn.conf.py` : Gunicorn, écoute sur `127.0.0.1` par défaut, `0.0.0.0` uniquement dans l'image via `GUNICORN_BIND`, `preload_app`.
- `Dockerfile` : multi-étapes, `python:3.15.0-slim-trixie` figé par digest, utilisateur 10001 non root, pip retiré, setuid retirés, `zlib1g`, `apt` et `libapt-pkg7.0` corrigés figés, `HEALTHCHECK`.
- `.github/workflows/ci.yml` : 10 jobs, actions figées par SHA, outils figés par version, `persist-credentials: false`, `concurrency`.
- Tests : `tests/unit/` (pytest, 14 tests) et `tests/container/smoke_test.sh` (conteneur lancé en lecture seule, sans capacités).
- `infra/bootstrap/` : Terraform du bucket S3 de l'état (KMS, versioning, journaux d'accès, HTTPS obligatoire), état local non versionné ; tests `terraform test` avec `mock_provider`. Jobs CI `IaC Terraform (fmt, validate, test)` et `IaC (Checkov)` (Checkov 3.4.4 en Docker, 6 exceptions justifiées).

Lancer en local :

```bash
cd app/app
SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))") DATABASE_URL=sqlite:///dev.db SESSION_COOKIE_SECURE=false python3 main.py
```

Tests : `pytest tests/unit -v` depuis la racine, avec le venv activé.

## Sandbox AWS (vérifié le 12 novembre 2026)

AWS Academy **Learner Lab** (rôle `voclabs`), région **us-east-1**. Identifiants **temporaires** (environ 4 h) dans `~/.aws/credentials`, à recoller à chaque « Start Lab ». **Ne jamais les écrire dans le chat ni dans le dépôt.**

| Autorisé | Refusé |
|---|---|
| ECS (Fargate), ECR, ELB (ALB), VPC, security groups, NAT, EC2 (t3.micro à t3.large), Secrets Manager, KMS, WAF, ACM (demande et import), CloudWatch Logs, S3 | création de rôles IAM, fournisseur OIDC, App Runner |
| RDS sur petites classes (`db.t3.micro` testé) | |
| `iam:PassRole` uniquement sur **`LabRole`** (accepté par ecs-tasks, ec2, rds, secretsmanager…) | |

Conséquences : utiliser `LabRole` comme rôle d'exécution et de tâche ECS ; pas d'OIDC GitHub vers AWS, donc identifiants du lab dans les secrets GitHub, à renouveler à chaque session (limite à documenter, en production on utiliserait OIDC) ; pas de nom de domaine, donc HTTPS avec un certificat auto-signé importé dans ACM (avertissement navigateur, à documenter). Surveiller le budget du lab (NAT, ALB et RDS consomment en continu).

## Prochaines étapes

1. **Déploiement AWS** (critères 1 et 4), en Terraform, scanné par Checkov, en 3 PR (plan détaillé dans le README) : `feat/terraform-backend` (fait : bucket d'état, jobs IaC ; reste à lancer `terraform apply` dans `infra/bootstrap`), `feat/aws-infra`, `ci/deploy`. Choix validés : un seul NAT (budget), mot de passe RDS géré par AWS (`manage_master_user_password`, l'app construira l'URL depuis `DB_HOST`/`DB_USER`/`DB_PASSWORD` si `DATABASE_URL` absente), `SECRET_KEY` générée par Terraform dans Secrets Manager, `terraform destroy` en fin de session.
   - VPC sur 2 zones, sous-réseaux publics (ALB) et privés (ECS, RDS), NAT ;
   - ALB en HTTPS (certificat auto-signé importé dans ACM), WAF avec règle de limitation de débit sur `/login` ;
   - ECS Fargate, 2 tâches sur 2 zones, security group n'acceptant que l'ALB ;
   - RDS PostgreSQL chiffré, privé, n'acceptant que ECS ;
   - Secrets Manager pour `SECRET_KEY` et le mot de passe de la base ;
   - ECR (scan à l'envoi, tags immuables), CloudWatch Logs ;
   - pipeline de déploiement sur `main` (push de l'image vers ECR, `terraform apply`), puis DAST avec OWASP ZAP sur l'URL publique.
2. README final : schéma d'architecture (Mermaid), workflow du cycle de vie sécurisé, relecture.
3. Optionnel : job TruffleHog (recherche de secrets) dans la pipeline, vu dans l'activité 7 du cours.

## Poste de travail

- Windows (PC) : Git Bash, éviter MobaXterm et les terminaux administrateur pour Git (problèmes de droits sur `.git`). Semgrep et Gunicorn ne fonctionnent pas sous Windows.
- macOS : `python3`, venv dans `.venv/bin/activate`, `shasum -a 256` au lieu de `sha256sum`. Chaque machine a sa propre clé SSH ed25519, déclarée sur GitHub à la fois comme clé d'authentification et comme clé de signature.
