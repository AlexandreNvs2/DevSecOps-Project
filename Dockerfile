# syntax=docker/dockerfile:1

# Image de base figée par version ET par empreinte (digest) : on sait
# exactement ce qu'on construit, et une image modifiée sur le registre
# serait refusée. Dependabot proposera les mises à jour.
FROM python:3.15.0-slim-trixie@sha256:f5b92f2a669a4c347044f29367f31983280b648250ca94dea66f98c53bc87e58 AS base


# ---- Étape 1 : installation des dépendances --------------------------------
FROM base AS builder

# Environnement virtuel isolé, copié tel quel dans l'image finale.
RUN python -m venv /opt/venv

COPY app/app/requirements.txt /tmp/requirements.txt
RUN /opt/venv/bin/pip install --no-cache-dir -r /tmp/requirements.txt \
    && /opt/venv/bin/pip uninstall --yes pip


# ---- Étape 2 : image finale -------------------------------------------------
FROM base AS runtime

LABEL org.opencontainers.image.title="password-checker" \
      org.opencontainers.image.description="Vérification d'un mot de passe dans les listes SecLists" \
      org.opencontainers.image.source="https://github.com/AlexandreNvs2/DevSecOps-Project"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    GUNICORN_BIND=0.0.0.0:8080

# 1. Correctif de sécurité Debian : zlib1g corrigé (CVE-2026-85091,
#    CVE-2026-76844, signalées HIGH par Trivy), publié après l'image de base.
#    Version figée ; à retirer quand Dependabot fournira une image de base
#    qui l'inclut. Si l'image de base contient un jour une version plus
#    récente, apt refusera de rétrograder et le build échouera : c'est le
#    signal pour supprimer cette ligne.
# 2. pip est retiré de l'image finale : rien ne peut y être installé une fois
#    en production.
# 3. Bits setuid/setgid retirés (su, passwd, mount...) : aucun binaire de
#    l'image ne peut plus s'exécuter avec les droits root (Dockle CIS-DI-0008).
# 4. Utilisateur dédié sans shell ni répertoire personnel.
RUN apt-get update \
    && apt-get install --yes --no-install-recommends --only-upgrade \
       zlib1g=1:1.3.dfsg+really1.3.1-1+deb13u1 \
    && rm -rf /var/lib/apt/lists/* \
    && python -m pip uninstall --yes pip \
    && find / -xdev -type f -perm /6000 -exec chmod a-s {} + \
    && groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --no-create-home \
       --shell /usr/sbin/nologin app

COPY --from=builder /opt/venv /opt/venv

# Code appartenant à root, en lecture seule pour l'utilisateur app :
# l'application ne peut pas modifier son propre code.
WORKDIR /app
COPY app/app/ /app/

# Identifiant numérique (et non le nom « app ») : vérifiable sans lire
# /etc/passwd, par exemple par une règle « runAsNonRoot » (Hadolint DL3066).
USER 10001:10001

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/', timeout=2)"]

CMD ["gunicorn", "main:app"]
