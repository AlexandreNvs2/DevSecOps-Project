#!/usr/bin/env bash
# Tests de fonctionnement et de sécurité du conteneur.
# Usage : tests/container/smoke_test.sh <image>
set -euo pipefail

IMAGE="$1"
NAME="smoke-test"
URL="http://127.0.0.1:8080"
COOKIES="$(mktemp)"

fail() { echo "ÉCHEC : $*"; docker logs "$NAME" || true; exit 1; }
ok() { echo "OK : $*"; }

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; rm -f "$COOKIES"; }
trap cleanup EXIT

# 1. Sans SECRET_KEY ou sans DATABASE_URL, l'application doit refuser de
#    démarrer.
if docker run --rm -e DATABASE_URL=sqlite:////tmp/t.db "$IMAGE" \
     python -c "import main" >/dev/null 2>&1; then
  fail "l'application démarre sans SECRET_KEY"
fi
ok "démarrage refusé sans SECRET_KEY"
if docker run --rm -e SECRET_KEY=test "$IMAGE" \
     python -c "import main" >/dev/null 2>&1; then
  fail "l'application démarre sans DATABASE_URL"
fi
ok "démarrage refusé sans DATABASE_URL"

# 2. Lancement durci : système de fichiers en lecture seule, aucune
#    capacité Linux, pas d'élévation de privilèges.
docker run -d --name "$NAME" -p 8080:8080 \
  --read-only --tmpfs /tmp \
  --cap-drop ALL --security-opt no-new-privileges \
  -e SECRET_KEY="$(openssl rand -hex 32)" \
  -e DATABASE_URL=sqlite:////tmp/app.db \
  -e SESSION_COOKIE_SECURE=false \
  "$IMAGE" >/dev/null

for _ in $(seq 1 30); do
  curl -fsS "$URL/" >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS "$URL/" >/dev/null || fail "l'application ne répond pas sur /"
ok "l'application répond sur / (Gunicorn)"

# 3. Le processus ne tourne pas en root.
uid="$(docker exec "$NAME" id -u)"
[ "$uid" != "0" ] || fail "le conteneur tourne en root"
ok "utilisateur non root (uid $uid)"

# 4. pip est absent de l'image finale.
if docker exec "$NAME" python -m pip --version >/dev/null 2>&1; then
  fail "pip est présent dans l'image finale"
fi
ok "pip absent de l'image finale"

# 5. Le code n'est pas modifiable par l'application.
if docker exec "$NAME" sh -c 'echo x >> /app/main.py' 2>/dev/null; then
  fail "le code de l'application est modifiable"
fi
ok "code en lecture seule"

# 5b. Cache apt vide (justifie l'exception Dockle DKL-DI-0005).
# (« ; true » : find renvoie une erreur sur les dossiers illisibles par
# l'utilisateur non root, ce qui ne doit pas interrompre le script.)
apt_files="$(docker exec "$NAME" sh -c 'find /var/lib/apt/lists -type f ! -name lock 2>/dev/null; true' | wc -l | tr -d ' ')"
[ "$apt_files" = "0" ] || fail "cache apt non vide ($apt_files fichiers)"
ok "cache apt vide"

# 5c. Aucun binaire setuid/setgid dans l'image.
suid="$(docker exec "$NAME" sh -c 'find / -xdev -type f -perm /6000 2>/dev/null; true' | wc -l | tr -d ' ')"
[ "$suid" = "0" ] || fail "$suid binaire(s) setuid/setgid présent(s)"
ok "aucun binaire setuid/setgid"

# 6. Protection CSRF : un POST sans jeton est refusé.
code="$(curl -s -o /dev/null -w '%{http_code}' -X POST -d 'password=password' "$URL/password")"
[ "$code" = "400" ] || fail "POST sans jeton CSRF : code $code au lieu de 400"
ok "POST sans jeton CSRF refusé (400)"

# 7. Parcours normal : formulaire, jeton, vérification d'un mot de passe.
page="$(curl -fsS -c "$COOKIES" "$URL/password")"
token="$(echo "$page" | sed -n 's/.*name="csrf_token" value="\([^"]*\)".*/\1/p')"
[ -n "$token" ] || fail "jeton CSRF absent du formulaire"
echo "$page" | grep -q 'type="password"' || fail "champ mot de passe non masqué"

answer="$(curl -fsS -b "$COOKIES" -X POST \
  --data-urlencode "password=password" --data-urlencode "csrf_token=$token" \
  "$URL/password")"
echo "$answer" | grep -q "500 worst" || fail "'password' non détecté : $answer"
ok "'password' détecté dans la liste des 500"

code="$(curl -s -o /dev/null -w '%{http_code}' -b "$COOKIES" -X POST \
  --data-urlencode "password=" --data-urlencode "csrf_token=$token" \
  "$URL/password")"
[ "$code" = "400" ] || fail "mot de passe vide : code $code au lieu de 400"
ok "mot de passe vide refusé (400)"

# 8. Création de compte puis connexion, avec Argon2id dans le conteneur.
reg_page="$(curl -fsS -b "$COOKIES" -c "$COOKIES" "$URL/register")"
token="$(echo "$reg_page" | sed -n 's/.*name="csrf_token" value="\([^"]*\)".*/\1/p' | head -1)"
code="$(curl -s -o /dev/null -w '%{http_code}' -b "$COOKIES" -c "$COOKIES" -X POST \
  --data-urlencode "username=smoketest" --data-urlencode "password=Tr0ub4dor-cheval-agrafe" \
  --data-urlencode "password_confirm=Tr0ub4dor-cheval-agrafe" \
  --data-urlencode "csrf_token=$token" "$URL/register")"
[ "$code" = "201" ] || fail "création de compte : code $code au lieu de 201"
ok "compte créé (201)"

code="$(curl -s -o /dev/null -w '%{http_code}' -b "$COOKIES" -c "$COOKIES" -X POST \
  --data-urlencode "username=smoketest" --data-urlencode "password=mauvais-mot-de-passe" \
  --data-urlencode "csrf_token=$token" "$URL/login")"
[ "$code" = "401" ] || fail "mauvais mot de passe : code $code au lieu de 401"
ok "connexion refusée avec un mauvais mot de passe (401)"

code="$(curl -s -o /dev/null -w '%{http_code}' -b "$COOKIES" -c "$COOKIES" -X POST \
  --data-urlencode "username=smoketest" --data-urlencode "password=Tr0ub4dor-cheval-agrafe" \
  --data-urlencode "csrf_token=$token" "$URL/login")"
[ "$code" = "302" ] || fail "connexion : code $code au lieu de 302"
ok "connexion réussie (302)"

echo "Tous les tests du conteneur sont passés."
