"""Tests unitaires : vérification de mot de passe, comptes, hachage."""
from argon2 import PasswordHasher
from sqlalchemy import select

import main
from models import User

STRONG = "Tr0ub4dor-cheval-agrafe"


def register(client, username, password=STRONG, confirm=None):
    return client.post("/register", data={
        "username": username,
        "password": password,
        "password_confirm": password if confirm is None else confirm,
    })


def login(client, username, password=STRONG):
    return client.post("/login", data={
        "username": username, "password": password,
    })


def stored_hash(username):
    with main.Session() as db:
        return db.scalar(
            select(User.password_hash).where(User.username == username)
        )


# --- Vérification d'un mot de passe (/password) -----------------------------

def test_password_check_lists(client):
    assert b"500 worst" in client.post(
        "/password", data={"password": "password"}).data
    assert b"10K worst" in client.post(
        "/password", data={"password": "1124"}).data
    assert b"seems to be safe" in client.post(
        "/password", data={"password": "a"}).data


def test_password_check_rejects_invalid_input(client):
    assert client.post("/password", data={"password": ""}).status_code == 400
    assert client.post(
        "/password", data={"password": "x" * 129}).status_code == 400


# --- Inscription ------------------------------------------------------------

def test_register_stores_argon2id_hash_not_password(client, username):
    assert register(client, username).status_code == 201
    h = stored_hash(username)
    assert h.startswith("$argon2id$")
    assert STRONG not in h
    assert "m=65536,t=3,p=4" in h


def test_same_password_gives_different_hashes(client, username):
    register(client, username + "a")
    register(client, username + "b")
    assert stored_hash(username + "a") != stored_hash(username + "b")


def test_register_rejects_common_password(client, username):
    # « unbelievable » : 12 caractères, présent dans la liste des 10 000.
    r = register(client, username, password="unbelievable")
    assert r.status_code == 400
    assert stored_hash(username) is None


def test_register_rejects_short_password(client, username):
    assert register(client, username, password="Court-1").status_code == 400


def test_register_rejects_password_equal_to_username(client):
    assert register(
        client, "identifiant_long", password="identifiant_long"
    ).status_code == 400


def test_register_rejects_mismatched_confirmation(client, username):
    assert register(
        client, username, confirm=STRONG + "x"
    ).status_code == 400


def test_register_rejects_invalid_username(client):
    for bad in ["ab", "a" * 33, "nom avec espace", "<script>"]:
        assert register(client, bad).status_code == 400


def test_register_rejects_duplicate_username(client, username):
    assert register(client, username).status_code == 201
    assert register(client, username.upper()).status_code == 409


# --- Connexion --------------------------------------------------------------

def test_login_success_opens_session(client, username):
    register(client, username)
    r = login(client, username)
    assert r.status_code == 302
    with client.session_transaction() as s:
        assert s["username"] == username


def test_login_wrong_password_and_unknown_user_same_answer(client, username):
    register(client, username)
    wrong = login(client, username, password=STRONG + "x")
    unknown = login(client, "inconnu_" + username)
    assert wrong.status_code == unknown.status_code == 401
    assert wrong.data == unknown.data


def test_logout_clears_session(client, username):
    register(client, username)
    login(client, username)
    client.post("/logout")
    with client.session_transaction() as s:
        assert "username" not in s


def test_login_rehashes_outdated_hash(client, username):
    weak = PasswordHasher(time_cost=1, memory_cost=8192, parallelism=1)
    with main.Session() as db:
        db.add(User(username=username, password_hash=weak.hash(STRONG)))
        db.commit()
    assert login(client, username).status_code == 302
    assert "m=65536,t=3,p=4" in stored_hash(username)
