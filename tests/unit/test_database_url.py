"""Construction de l'adresse de la base à partir de l'environnement."""
import pytest
from sqlalchemy import make_url

from models import database_url_from_env

AWS_ENV = {
    "DB_HOST": "db.example.internal",
    "DB_USER": "app",
    # Mot de passe généré par RDS : caractères spéciaux possibles.
    "DB_PASSWORD": "p@ss:w/rd?#%&=",
    "DB_NAME": "app",
    "DB_PORT": "5432",
}


def test_database_url_takes_priority():
    env = dict(AWS_ENV, DATABASE_URL="sqlite:////tmp/x.db")
    assert database_url_from_env(env) == "sqlite:////tmp/x.db"


def test_url_built_from_aws_variables():
    url = database_url_from_env(AWS_ENV)
    assert url.drivername == "postgresql+psycopg"
    assert url.host == "db.example.internal"
    assert url.port == 5432
    assert url.database == "app"
    assert url.username == "app"


def test_password_special_characters_are_escaped():
    url = database_url_from_env(AWS_ENV)
    # Après sérialisation puis relecture, le mot de passe est intact :
    # aucun caractère spécial ne peut modifier l'hôte ou les paramètres.
    parsed = make_url(url.render_as_string(hide_password=False))
    assert parsed.password == AWS_ENV["DB_PASSWORD"]
    assert parsed.host == AWS_ENV["DB_HOST"]


def test_tls_is_required():
    url = database_url_from_env(AWS_ENV)
    assert url.query["sslmode"] == "require"


def test_password_hidden_in_representation():
    url = database_url_from_env(AWS_ENV)
    assert AWS_ENV["DB_PASSWORD"] not in str(url)
    assert AWS_ENV["DB_PASSWORD"] not in repr(url)


@pytest.mark.parametrize("missing", ["DB_HOST", "DB_USER", "DB_PASSWORD"])
def test_refuses_to_start_without_configuration(missing):
    env = {k: v for k, v in AWS_ENV.items() if k != missing}
    with pytest.raises(RuntimeError):
        database_url_from_env(env)
