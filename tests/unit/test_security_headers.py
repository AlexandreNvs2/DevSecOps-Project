"""En-têtes de sécurité HTTP (alertes OWASP ZAP sur l'application déployée)."""
import pytest

import main
from test_app import login, register

EXPECTED = {
    "Strict-Transport-Security": "max-age=31536000",
    "X-Frame-Options": "DENY",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
    "Cross-Origin-Opener-Policy": "same-origin",
    "Cross-Origin-Embedder-Policy": "require-corp",
    "Cross-Origin-Resource-Policy": "same-origin",
    "Cache-Control": "no-store, no-cache, must-revalidate",
}


@pytest.mark.parametrize("path", ["/", "/login", "/register", "/password"])
def test_security_headers_on_every_page(client, path):
    response = client.get(path)
    for name, value in EXPECTED.items():
        assert response.headers.get(name) == value, name


def test_security_headers_on_errors(client):
    # Y compris sur les réponses d'erreur.
    response = client.get("/page-inexistante")
    assert response.status_code == 404
    assert response.headers.get("X-Content-Type-Options") == "nosniff"
    assert response.headers.get("Cache-Control") == EXPECTED["Cache-Control"]


def test_csp_blocks_everything_not_needed(client):
    csp = client.get("/").headers["Content-Security-Policy"]
    directives = dict(d.strip().split(" ", 1) for d in csp.split(";"))
    assert directives["default-src"] == "'none'"
    assert directives["frame-ancestors"] == "'none'"
    assert directives["form-action"] == "'self'"
    assert directives["base-uri"] == "'none'"
    assert "unsafe-inline" not in csp and "unsafe-eval" not in csp


def test_permissions_policy_disables_sensitive_apis(client):
    policy = client.get("/").headers["Permissions-Policy"]
    for api in ("camera", "microphone", "geolocation"):
        assert f"{api}=()" in policy


INLINE_CODE = ("style=", "<style", "<script", "onclick=", "onload=")


def test_templates_have_no_inline_style_or_script():
    # La CSP interdit les styles et scripts en ligne : aucun template ne doit
    # en contenir, sinon la page serait cassée en production.
    for template in (main.DATA_DIR.parent / "templates").glob("*.html"):
        html = template.read_text(encoding="utf-8").lower()
        for forbidden in INLINE_CODE:
            assert forbidden not in html, f"{forbidden} dans {template.name}"


def test_session_cookie_flags(client, username):
    # Justifie l'exception ZAP 10112 (gestion de session identifiée) : le
    # cookie de session est illisible par JavaScript et non envoyé par les
    # requêtes d'autres sites.
    register(client, username)
    response = login(client, username)
    assert response.status_code == 302
    cookie = response.headers["Set-Cookie"].lower()
    assert "httponly" in cookie
    assert "samesite=lax" in cookie


def test_session_cookie_secure_by_default():
    # En production (variable absente), le cookie n'est envoyé qu'en HTTPS ;
    # seuls les tests et le développement local le désactivent.
    assert main.app.config["SESSION_COOKIE_SECURE"] is False  # tests
    source = (main.DATA_DIR.parent / "main.py").read_text(encoding="utf-8")
    assert 'os.environ.get("SESSION_COOKIE_SECURE", "true")' in source
