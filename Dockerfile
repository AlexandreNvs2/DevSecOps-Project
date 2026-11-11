# syntax=docker/dockerfile:1

# Image de base figée par version ET par empreinte (digest) : on sait
# exactement ce qu'on construit, et une image modifiée sur le registre
# serait refusée. Dependabot proposera les mises à jour.
FROM python:3.13.18-slim-trixie@sha256:e48f59cdba69a3cbd9ed2cf0f348d90d45a8d350d98134cf1070bc106ee9ed90 AS base


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

# pip est retiré de l'image finale : rien ne peut y être installé une fois
# en production. Utilisateur dédié sans shell ni répertoire personnel.
RUN python -m pip uninstall --yes pip \
    && groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --no-create-home \
       --shell /usr/sbin/nologin app

COPY --from=builder /opt/venv /opt/venv

# Code appartenant à root, en lecture seule pour l'utilisateur app :
# l'application ne peut pas modifier son propre code.
WORKDIR /app
COPY app/app/ /app/

USER app

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/', timeout=2)"]

CMD ["gunicorn", "main:app"]
