"""Configuration des tests unitaires : environnement de test isolé."""
import os
import secrets
import sys
import tempfile
from pathlib import Path

import pytest

# Variables d'environnement de test, définies avant l'import de l'application
# (qui refuse de démarrer sans elles). Base SQLite jetable.
_db_dir = tempfile.mkdtemp()
os.environ["SECRET_KEY"] = secrets.token_hex(32)
os.environ["DATABASE_URL"] = f"sqlite:///{_db_dir}/test.db"
os.environ["SESSION_COOKIE_SECURE"] = "false"

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "app" / "app"))

import main  # noqa: E402


@pytest.fixture
def client():
    # La protection CSRF est vérifiée par les tests du conteneur ; ici on
    # teste la logique métier.
    main.app.config["WTF_CSRF_ENABLED"] = False
    with main.app.test_client() as c:
        yield c
    main.app.config["WTF_CSRF_ENABLED"] = True


@pytest.fixture
def username():
    """Identifiant unique par test (la base est partagée)."""
    return "user_" + secrets.token_hex(4)
