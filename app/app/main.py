import os
from pathlib import Path

from flask import Flask, redirect, render_template, request, session, url_for
from flask_wtf.csrf import CSRFProtect
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

import security
from models import User, database_url_from_env, init_db

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

# En-têtes de sécurité HTTP ajoutés à chaque réponse (alertes de l'analyse
# dynamique OWASP ZAP sur l'application déployée, voir le README).
SECURITY_HEADERS = {
    # Navigateur obligé d'utiliser HTTPS pendant un an (ignoré en HTTP).
    "Strict-Transport-Security": "max-age=31536000",
    # Aucune ressource externe, aucun script, aucun style en ligne ; pages
    # non intégrables dans un cadre (clickjacking) ; formulaires envoyés
    # uniquement à l'application.
    "Content-Security-Policy": (
        "default-src 'none'; form-action 'self'; "
        "frame-ancestors 'none'; base-uri 'none'"
    ),
    "X-Frame-Options": "DENY",
    # Pas d'interprétation d'un fichier dans un autre type que celui déclaré.
    "X-Content-Type-Options": "nosniff",
    # Aucune adresse transmise aux sites tiers.
    "Referrer-Policy": "no-referrer",
    # Aucune API sensible du navigateur (caméra, micro, position...).
    "Permissions-Policy": (
        "camera=(), microphone=(), geolocation=(), payment=(), usb=()"
    ),
    # Isolation de la page vis-à-vis des autres origines.
    "Cross-Origin-Opener-Policy": "same-origin",
    "Cross-Origin-Embedder-Policy": "require-corp",
    "Cross-Origin-Resource-Policy": "same-origin",
    # Pages personnelles (identifiant, jeton CSRF) : jamais mises en cache,
    # ni par le navigateur ni par un proxy (directives recommandées par
    # l'OWASP pour du contenu sensible servi en HTTPS, ZAP 10015).
    "Cache-Control": "no-store, no-cache, must-revalidate",
}


@app.after_request
def set_security_headers(response):
    response.headers.update(SECURITY_HEADERS)
    return response


# Base de données : adresse fournie par l'environnement, comme la clé
# secrète. En développement et en test, DATABASE_URL (par exemple
# sqlite:////tmp/app.db). Sur AWS, DB_HOST, DB_USER et DB_PASSWORD, ce
# dernier injecté depuis AWS Secrets Manager (voir models.py). Sans
# configuration, l'application refuse de démarrer.
DATABASE_URL = database_url_from_env(os.environ)

Session = init_db(DATABASE_URL)

DATA_DIR = Path(__file__).parent / "data"


def load_wordlist(filename):
    """Charge une liste de mots de passe une seule fois, au démarrage."""
    path = DATA_DIR / filename
    with path.open(encoding="utf-8", errors="ignore") as f:
        return frozenset(line.strip() for line in f if line.strip())


WORST_500 = load_wordlist("500-worst-passwords.txt")
WORST_10K = load_wordlist("10k-most-common.txt")

COMMON_PASSWORDS = (WORST_500, WORST_10K)

MAX_PASSWORD_LENGTH = security.MAX_PASSWORD_LENGTH


@app.route("/")
def hello():
    return render_template("index.html", username=session.get("username"))


@app.route("/register", methods=["GET", "POST"])
def register():
    if request.method == "GET":
        return render_template("register.html")

    username = security.normalize_username(request.form.get("username"))
    new_password = request.form.get("password", "")
    confirmation = request.form.get("password_confirm", "")

    problem = security.username_problem(username)
    if not problem and new_password != confirmation:
        problem = "Les deux mots de passe ne correspondent pas."
    if not problem:
        problem = security.password_problem(
            new_password, username, COMMON_PASSWORDS
        )
    if problem:
        return render_template("register.html", error=problem), 400

    user = User(
        username=username,
        password_hash=security.hash_password(new_password),
    )
    with Session() as db:
        db.add(user)
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            return (
                render_template(
                    "register.html", error="Cet identifiant est déjà pris."
                ),
                409,
            )
    return render_template(
        "login.html", info="Compte créé. Vous pouvez vous connecter."
    ), 201


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "GET":
        return render_template("login.html")

    username = security.normalize_username(request.form.get("username"))
    candidate = request.form.get("password", "")
    # Message unique, que le compte existe ou non : pas d'énumération.
    failure = render_template(
        "login.html", error="Identifiant ou mot de passe incorrect."
    ), 401

    if not candidate or len(candidate) > MAX_PASSWORD_LENGTH:
        return failure

    with Session() as db:
        user = db.scalar(select(User).where(User.username == username))
        if user is None:
            security.verify_dummy(candidate)
            return failure
        if not security.verify_password(user.password_hash, candidate):
            return failure
        # Paramètres Argon2 renforcés depuis la création du compte :
        # l'empreinte est recalculée avec les nouveaux paramètres.
        if security.needs_rehash(user.password_hash):
            user.password_hash = security.hash_password(candidate)
            db.commit()
        user_id, user_name = user.id, user.username

    # Nouvelle session à la connexion : empêche la fixation de session.
    session.clear()
    session["user_id"] = user_id
    session["username"] = user_name
    return redirect(url_for("hello"))


@app.route("/logout", methods=["POST"])
def logout():
    session.clear()
    return redirect(url_for("hello"))


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
