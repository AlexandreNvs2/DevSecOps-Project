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
