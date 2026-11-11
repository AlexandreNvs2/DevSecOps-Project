"""Hachage des mots de passe (Argon2id) et règles de validation."""
import re

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError
from argon2.profiles import RFC_9106_LOW_MEMORY

# Argon2id avec les paramètres recommandés par la RFC 9106 (profil « low
# memory ») : 3 itérations, 64 Mio de mémoire, 4 fils, sel aléatoire de
# 16 octets par mot de passe.
hasher = PasswordHasher.from_parameters(RFC_9106_LOW_MEMORY)

MIN_PASSWORD_LENGTH = 12
MAX_PASSWORD_LENGTH = 128
USERNAME_PATTERN = re.compile(r"^[a-z0-9_.-]{3,32}$")

# Empreinte factice, vérifiée quand le compte demandé n'existe pas : la
# réponse prend alors le même temps que pour un compte existant, ce qui
# empêche de deviner les comptes en mesurant le temps de réponse.
_DUMMY_HASH = hasher.hash("compte-inexistant")


def normalize_username(username):
    return (username or "").strip().lower()


def username_problem(username):
    """Renvoie un message d'erreur, ou None si l'identifiant est valide."""
    if not USERNAME_PATTERN.fullmatch(username):
        return (
            "Identifiant invalide : 3 à 32 caractères parmi "
            "lettres minuscules, chiffres, « _ », « . » et « - »."
        )
    return None


def password_problem(password, username, common_passwords):
    """Renvoie un message d'erreur, ou None si le mot de passe est accepté.

    Politique inspirée du NIST SP 800-63B : longueur minimale, pas de
    règles de composition imposées, refus des mots de passe connus.
    """
    if len(password) < MIN_PASSWORD_LENGTH:
        return (
            f"Mot de passe trop court : {MIN_PASSWORD_LENGTH} caractères "
            "minimum."
        )
    if len(password) > MAX_PASSWORD_LENGTH:
        return (
            f"Mot de passe trop long : {MAX_PASSWORD_LENGTH} caractères "
            "maximum."
        )
    if password.lower() == username:
        return "Le mot de passe ne doit pas être l'identifiant."
    if any(password in wordlist for wordlist in common_passwords):
        return (
            "Ce mot de passe fait partie des mots de passe les plus "
            "courants. Choisissez-en un autre."
        )
    return None


def hash_password(password):
    return hasher.hash(password)


def verify_password(stored_hash, password):
    """Vrai si le mot de passe correspond à l'empreinte stockée."""
    try:
        return hasher.verify(stored_hash, password)
    except (VerificationError, InvalidHashError):
        return False


def verify_dummy(password):
    """Vérification factice pour un compte inexistant (même durée)."""
    verify_password(_DUMMY_HASH, password)
    return False


def needs_rehash(stored_hash):
    """Vrai si l'empreinte utilise d'anciens paramètres Argon2."""
    return hasher.check_needs_rehash(stored_hash)
