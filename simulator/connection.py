"""Connexion Snowflake du simulateur.

Le simulateur joue le rôle d'un outil d'ingestion : il se connecte avec le rôle
LOADER, qui peut écrire dans RAW et rien d'autre.
"""

import os
from pathlib import Path

import snowflake.connector
from dotenv import load_dotenv

PROJECT_ROOT = Path(__file__).resolve().parent.parent

RAW_DATABASE = "RAW"
RAW_SCHEMA = "DUNNHUMBY"


def get_connection():
    """Ouvre une connexion Snowflake (rôle loader) à partir des variables du .env."""
    load_dotenv(PROJECT_ROOT / ".env")

    conn = snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        private_key_file=os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"],
        role="LOADER",
        warehouse="LOADING_WH",
        database=RAW_DATABASE,
    )
    # sans ça, les rôles secondaires (dont accountadmin) restent actifs en arrière-plan
    conn.cursor().execute("use secondary roles none")
    return conn


def ensure_schema(conn):
    """Crée le schéma de destination s'il n'existe pas encore."""
    conn.cursor().execute(f"create schema if not exists {RAW_DATABASE}.{RAW_SCHEMA}")
    conn.cursor().execute(f"use schema {RAW_DATABASE}.{RAW_SCHEMA}")


if __name__ == "__main__":
    # test rapide : python simulator/connection.py
    with get_connection() as conn:
        ensure_schema(conn)
        row = conn.cursor().execute(
            "select current_user(), current_role(), current_secondary_roles(), current_warehouse(), current_schema()"
        ).fetchone()
        print("user / role / secondary roles / warehouse / schema :", row)
