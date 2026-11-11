import os
from pathlib import Path

from flask import Flask, request, render_template
from flask_wtf.csrf import CSRFProtect

app = Flask(__name__)

# Clé secrète : signe le cookie de session et les jetons CSRF.
# Elle n'est jamais écrite dans le code : elle vient de l'environnement
# (en production, d'un gestionnaire de secrets AWS). Sans elle, l'application
# refuse de démarrer plutôt que de tourner avec une clé faible.
SECRET_KEY = os.environ.get("SECRET_KEY")
if not SECRET_KEY:
    raise RuntimeError("La variable d'environnement SECRET_KEY est requise.")

app.config.update(
    SECRET_KEY=SECRET_KEY,
    # Cookie de session illisible par JavaScript (limite le vol par XSS).
    SESSION_COOKIE_HTTPONLY=True,
    # Cookie non envoyé par les requêtes provenant d'autres sites.
    SESSION_COOKIE_SAMESITE="Lax",
    # Cookie envoyé uniquement en HTTPS ; désactivable en local (HTTP).
    SESSION_COOKIE_SECURE=os.environ.get("SESSION_COOKIE_SECURE", "true")
    == "true",
)

# Protection CSRF sur toutes les requêtes POST.
csrf = CSRFProtect(app)

DATA_DIR = Path(__file__).parent / "data"


def load_wordlist(filename):
    """Charge une liste de mots de passe une seule fois, au démarrage."""
    path = DATA_DIR / filename
    with path.open(encoding="utf-8", errors="ignore") as f:
        return frozenset(line.strip() for line in f if line.strip())


WORST_500 = load_wordlist("500-worst-passwords.txt")
WORST_10K = load_wordlist("10k-most-common.txt")

MAX_PASSWORD_LENGTH = 128


@app.route("/")
def hello():
    return "Welcome to the website. Go to /password to check your password !"


@app.route("/password", methods=["GET", "POST"])
def password():
    if request.method == "POST":
        password = request.form.get("password", "")
        if not password or len(password) > MAX_PASSWORD_LENGTH:
            return "Invalid password", 400
        if password in WORST_500:
            return (
                "Your password is in 500 worst passwords... "
                "Change it immediately"
            )
        elif password in WORST_10K:
            return (
                "Your password is in 10K worst passwords... "
                "Change it immediately"
            )
        else:
            return "Your password seems to be safe"
    return render_template("password.html")


if __name__ == "__main__":
    # Serveur de développement Flask, uniquement en local.
    # En production, l'application est servie par Gunicorn (gunicorn.conf.py).
    app.run(port=8080, host="127.0.0.1")
