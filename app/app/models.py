"""Base de données : modèle utilisateur (SQLAlchemy 2).

Toutes les requêtes passent par l'ORM, donc sont paramétrées : aucune
concaténation de chaînes dans du SQL, pas d'injection SQL possible.
"""
from datetime import datetime, timezone

from sqlalchemy import DateTime, String, create_engine
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    username: Mapped[str] = mapped_column(String(32), unique=True, index=True)
    # Empreinte Argon2id complète : algorithme, paramètres, sel et hash.
    # Le mot de passe lui-même n'est jamais stocké.
    password_hash: Mapped[str] = mapped_column(String(255))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )


def init_db(database_url):
    """Crée les tables si besoin et renvoie une fabrique de sessions."""
    engine = create_engine(database_url, pool_pre_ping=True)
    Base.metadata.create_all(engine)
    # Gunicorn charge l'application une fois puis crée ses workers par fork :
    # on vide le pool pour qu'aucune connexion ne soit partagée entre eux.
    engine.dispose()
    return sessionmaker(bind=engine, expire_on_commit=False)
