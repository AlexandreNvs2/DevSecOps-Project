"""Configuration Gunicorn, serveur WSGI de production de l'application.

Lancement : gunicorn main:app, depuis app/app/
(ce fichier est lu automatiquement).
"""
import os

# Adresse d'écoute. Par défaut, uniquement la machine locale.
# Dans le conteneur Docker, GUNICORN_BIND vaudra 0.0.0.0:8080 pour que le
# conteneur soit joignable ; l'exposition réelle est alors contrôlée par le
# réseau (security group, load balancer), pas par l'application.
bind = os.environ.get("GUNICORN_BIND", "127.0.0.1:8080")

# Processus de traitement des requêtes.
workers = int(os.environ.get("GUNICORN_WORKERS", "2"))

# Fichiers de contrôle des workers (battement de cœur). Dans l'image, le
# système de fichiers est en lecture seule : GUNICORN_WORKER_TMP_DIR vaut
# /dev/shm, un système de fichiers en mémoire toujours inscriptible, sur
# Docker comme sur AWS Fargate. En local, le répertoire temporaire du système.
worker_tmp_dir = os.environ.get("GUNICORN_WORKER_TMP_DIR")

# Socket de contrôle de Gunicorn (administration à chaud : workers,
# rechargement) désactivé : inutile en production, ce serait une interface
# d'administration de plus dans le conteneur, et elle échoue de toute façon
# sur un système de fichiers en lecture seule.
control_socket_disable = True

# L'application est chargée une seule fois avant la création des workers :
# les tables de la base ne sont créées qu'une fois (pas de concurrence).
preload_app = True

# Une requête bloquée plus de 30 s est interrompue et son worker relancé.
timeout = 30
graceful_timeout = 30
keepalive = 5

# Limites sur la taille des requêtes (protection contre les requêtes
# démesurées) : ligne de requête, nombre et taille des en-têtes.
limit_request_line = 4094
limit_request_fields = 50
limit_request_field_size = 8190

# Journaux sur la sortie standard, récupérés par Docker puis par AWS.
accesslog = "-"
errorlog = "-"
loglevel = "info"
