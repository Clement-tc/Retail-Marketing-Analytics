"""Simulateur de flux : charge les CSV dunnhumby dans RAW.DUNNHUMBY.

Usage :
    python simulator/simulate.py load-history [--history-weeks 90]
    python simulator/simulate.py deliver-week --week 91 [--seed 42] [--dry-run]

Les défauts injectés par deliver-week sont volontaires (voir README) et tracés
dans RAW.DUNNHUMBY.SIMULATOR_LOG.
"""

import argparse
from datetime import datetime, timezone

import numpy as np
import pandas as pd
from snowflake.connector.pandas_tools import write_pandas

from connection import PROJECT_ROOT, ensure_schema, get_connection

DATA_DIR = PROJECT_ROOT / "data" / "kaggle"

HISTORY_WEEKS = 90

# tables de référence : chargées en entier, remplacées à chaque chargement
REFERENCE_TABLES = [
    "product",
    "hh_demographic",
    "campaign_desc",
    "campaign_table",
    "coupon",
    "coupon_redempt",
]

# un générateur aléatoire distinct par (seed, semaine, type de défaut) :
# chaque défaut est reproductible et indépendant des autres
DEFECT_SALT = {"late": 1, "duplicate": 2, "bad_value": 3, "product_change": 4}


def rng_for(seed, week, defect):
    return np.random.default_rng([seed, week, DEFECT_SALT[defect]])


# --- chargement ---------------------------------------------------------------


def add_load_metadata(df, batch_id):
    """Ajoute les colonnes techniques : quand et dans quel lot la ligne est arrivée."""
    df = df.copy()
    df["_LOADED_AT"] = pd.Timestamp(datetime.now(timezone.utc))
    df["_BATCH_ID"] = batch_id
    return df


def load_table(conn, df, table_name, overwrite):
    """Envoie un DataFrame dans RAW.DUNNHUMBY.<table_name>."""
    # noms de colonnes en majuscules, sans guillemets : convention snowflake
    df.columns = [c.upper() for c in df.columns]
    success, _, nrows, _ = write_pandas(
        conn,
        df,
        table_name=table_name.upper(),
        auto_create_table=True,
        overwrite=overwrite,
        quote_identifiers=False,
        use_logical_type=True,
    )
    if not success:
        raise RuntimeError(f"échec du chargement de {table_name}")
    print(f"  {table_name:<18} {nrows:>10,} lignes")


def read_transactions():
    return pd.read_csv(DATA_DIR / "transaction_data.csv")


def load_history(conn, history_weeks):
    """Premier chargement : tables de référence + transactions des semaines 1 à N."""
    print("tables de référence :")
    for name in REFERENCE_TABLES:
        df = pd.read_csv(DATA_DIR / f"{name}.csv")
        load_table(conn, add_load_metadata(df, "history"), name, overwrite=True)

    print(f"transactions (semaines 1 à {history_weeks}) :")
    transactions = read_transactions()
    history = transactions[transactions["WEEK_NO"] <= history_weeks].reset_index(drop=True)
    load_table(conn, add_load_metadata(history, "history"), "transaction_data", overwrite=True)


# --- défauts ------------------------------------------------------------------


def late_rows_mask(week_rows, week, seed, late_rate):
    """Lignes de la semaine retenues pour être livrées en retard.

    Le tirage ne dépend que de (seed, semaine) : on peut le recalculer
    plus tard, au moment de livrer ces lignes, sans garder d'état.
    """
    return rng_for(seed, week, "late").random(len(week_rows)) < late_rate


def build_week_batch(transactions, week, args):
    """Construit la livraison de la semaine : lignes à l'heure + retards d'une semaine passée."""
    this_week = transactions[transactions["WEEK_NO"] == week].reset_index(drop=True)
    held_back = late_rows_mask(this_week, week, args.seed, args.late_rate)
    on_time = this_week[~held_back]

    # lignes d'une semaine passée, retenues à l'époque, qui arrivent maintenant
    origin_week = week - args.late_delay
    if origin_week > args.history_weeks:
        origin = transactions[transactions["WEEK_NO"] == origin_week].reset_index(drop=True)
        late = origin[late_rows_mask(origin, origin_week, args.seed, args.late_rate)]
    else:
        late = this_week.iloc[0:0]

    log = log_rows("late_arrival", late, f"semaine {origin_week} livrée en semaine {week}")
    log_held = log_rows("held_back", this_week[held_back], f"sera livrée en semaine {week + args.late_delay}")
    batch = pd.concat([on_time, late], ignore_index=True)
    return batch, [log, log_held]


def inject_duplicates(batch, week, args):
    """Renvoie une partie des lignes une seconde fois (renvoi d'un même message par la source)."""
    picked = rng_for(args.seed, week, "duplicate").random(len(batch)) < args.dup_rate
    duplicates = batch[picked]
    log = log_rows("duplicate", duplicates, "ligne envoyée deux fois")
    return pd.concat([batch, duplicates], ignore_index=True), log


def inject_bad_values(batch, week, args):
    """Abîme quelques lignes : product_id manquant ou quantité négative."""
    rng = rng_for(args.seed, week, "bad_value")
    batch = batch.copy()
    batch["PRODUCT_ID"] = batch["PRODUCT_ID"].astype("Int64")  # entier qui accepte les nulls

    picked = np.flatnonzero(rng.random(len(batch)) < args.bad_rate)
    null_product = picked[: len(picked) // 2]
    negative_qty = picked[len(picked) // 2 :]

    logs = [
        log_rows("null_product_id", batch.iloc[null_product], "product_id mis à null"),
        log_rows("negative_quantity", batch.iloc[negative_qty], "quantité passée en négatif"),
    ]
    batch.loc[null_product, "PRODUCT_ID"] = pd.NA
    batch.loc[negative_qty, "QUANTITY"] = -batch.loc[negative_qty, "QUANTITY"].abs().clip(lower=1)
    return batch, logs


def apply_product_changes(products, week, args):
    """Change la catégorie de quelques produits, de façon cumulative depuis la 1re livraison.

    À la semaine N, on rejoue les changements des semaines history+1 à N : le
    catalogue évolue dans le temps au lieu de revenir à son état d'origine.
    """
    products = products.copy()
    changes = []
    for w in range(args.history_weeks + 1, week + 1):
        rng = rng_for(args.seed, w, "product_change")
        picked = np.flatnonzero(rng.random(len(products)) < args.product_change_rate)
        for i in picked:
            department = products.at[i, "DEPARTMENT"]
            candidates = products[(products["DEPARTMENT"] == department)
                                  & (products["COMMODITY_DESC"] != products.at[i, "COMMODITY_DESC"])]
            if candidates.empty:
                continue
            donor = candidates.iloc[rng.integers(len(candidates))]
            if w == week:
                changes.append({
                    "PRODUCT_ID": products.at[i, "PRODUCT_ID"],
                    "DETAILS": f"{products.at[i, 'COMMODITY_DESC']} -> {donor['COMMODITY_DESC']}",
                })
            products.at[i, "COMMODITY_DESC"] = donor["COMMODITY_DESC"]
            products.at[i, "SUB_COMMODITY_DESC"] = donor["SUB_COMMODITY_DESC"]

    log = pd.DataFrame(changes, columns=["PRODUCT_ID", "DETAILS"])
    log.insert(0, "DEFECT_TYPE", "product_change")
    log["BASKET_ID"] = pd.NA
    return products, log


def log_rows(defect_type, rows, details):
    """Une ligne de journal par ligne abîmée : c'est le 'corrigé' des défauts injectés."""
    return pd.DataFrame({
        "DEFECT_TYPE": defect_type,
        "BASKET_ID": rows["BASKET_ID"].to_numpy(),
        "PRODUCT_ID": rows["PRODUCT_ID"].astype("Int64").to_numpy(),
        "DETAILS": details,
    })


# --- livraison hebdomadaire ---------------------------------------------------


def batch_already_loaded(conn, batch_id):
    count = conn.cursor().execute(
        "select count(*) from transaction_data where _batch_id = %s", (batch_id,)
    ).fetchone()[0]
    return count > 0


def deliver_week(conn, args):
    batch_id = f"week_{args.week}"
    if args.week <= args.history_weeks:
        raise SystemExit(f"la semaine {args.week} fait partie de l'historique (1 à {args.history_weeks})")
    if conn is not None and batch_already_loaded(conn, batch_id):
        raise SystemExit(f"{batch_id} est déjà chargée : relivrer créerait des doublons non tracés")

    transactions = read_transactions()
    batch, logs = build_week_batch(transactions, args.week, args)
    batch, dup_log = inject_duplicates(batch, args.week, args)
    batch, bad_logs = inject_bad_values(batch, args.week, args)
    products, product_log = apply_product_changes(pd.read_csv(DATA_DIR / "product.csv"), args.week, args)

    log = pd.concat([*logs, dup_log, *bad_logs, product_log], ignore_index=True)
    log.insert(0, "BATCH_ID", batch_id)
    log.insert(1, "WEEK_NO", args.week)
    log = log.astype({"BASKET_ID": "Int64", "PRODUCT_ID": "Int64"})

    print(f"livraison {batch_id} : {len(batch):,} lignes de transactions")
    print(log["DEFECT_TYPE"].value_counts().to_string())

    if args.dry_run:
        print("dry-run : rien n'a été envoyé à snowflake")
        return

    load_table(conn, add_load_metadata(batch, batch_id), "transaction_data", overwrite=False)
    load_table(conn, add_load_metadata(products, batch_id), "product", overwrite=True)
    load_table(conn, add_load_metadata(log, batch_id), "simulator_log", overwrite=False)


# --- ligne de commande --------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description="Simulateur de flux dunnhumby vers Snowflake")
    commands = parser.add_subparsers(dest="command", required=True)

    history = commands.add_parser("load-history", help="chargement initial (tables de référence + historique)")
    history.add_argument("--history-weeks", type=int, default=HISTORY_WEEKS)

    deliver = commands.add_parser("deliver-week", help="livre une semaine de transactions avec défauts")
    deliver.add_argument("--week", type=int, required=True)
    deliver.add_argument("--seed", type=int, default=42)
    deliver.add_argument("--history-weeks", type=int, default=HISTORY_WEEKS)
    deliver.add_argument("--dup-rate", type=float, default=0.01)
    deliver.add_argument("--late-rate", type=float, default=0.02)
    deliver.add_argument("--late-delay", type=int, default=3, help="retard en semaines")
    deliver.add_argument("--bad-rate", type=float, default=0.001)
    deliver.add_argument("--product-change-rate", type=float, default=0.0005)
    deliver.add_argument("--dry-run", action="store_true", help="calcule la livraison sans rien envoyer")

    args = parser.parse_args()

    if args.command == "deliver-week" and args.dry_run:
        deliver_week(None, args)
        return

    with get_connection() as conn:
        ensure_schema(conn)
        if args.command == "load-history":
            load_history(conn, args.history_weeks)
        elif args.command == "deliver-week":
            deliver_week(conn, args)


if __name__ == "__main__":
    main()
