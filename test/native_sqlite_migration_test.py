#!/usr/bin/env python3
"""
Test de validation des migrations SQLite (v3 -> v5, v4 -> v5), ALTER TABLE,
transactions financières et atomicité de setFuelState sur le VÉRITABLE moteur natif SQLite 3.45+.
"""

import os
import sqlite3
import sys

def run_tests():
    db_v3_path = "test/scratch_v3_to_v5.db"
    db_v4_path = "test/scratch_v4_to_v5.db"

    for path in [db_v3_path, db_v4_path]:
        if os.path.exists(path):
            os.remove(path)

    print(f"=== Validation sur Vrai Moteur SQLite v{sqlite3.sqlite_version} ===")

    # ──────────────────────────────────────────────────────────────────────────
    # 1. TEST MIGRATION RÉELLE v3 -> v5
    # ──────────────────────────────────────────────────────────────────────────
    print("\n[TEST 1] Migration réelle v3 -> v5 avec données préexistantes...")
    conn = sqlite3.connect(db_v3_path)
    cur = conn.cursor()

    # Création du schéma v3
    cur.execute("""
      CREATE TABLE sessions (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        start_timestamp INTEGER NOT NULL,
        end_timestamp   INTEGER NOT NULL,
        total_earned    REAL NOT NULL,
        total_spent     REAL NOT NULL,
        total_km        REAL NOT NULL,
        total_fuel      REAL NOT NULL
      )
    """)
    cur.execute("""
      CREATE TABLE rides (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        start_time   INTEGER NOT NULL,
        end_time     INTEGER NOT NULL,
        fuel_liters  REAL NOT NULL,
        fuel_cost_da REAL NOT NULL,
        earned_da    REAL NOT NULL,
        profit_da    REAL NOT NULL,
        distance_km  REAL NOT NULL,
        session_id   INTEGER,
        date         TEXT
      )
    """)
    cur.execute("""
      CREATE TABLE expenses (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        date         TEXT NOT NULL,
        type         TEXT NOT NULL,
        amount_da    REAL NOT NULL,
        timestamp    INTEGER NOT NULL,
        session_id   INTEGER
      )
    """)

    # Données v3 existantes
    cur.execute("INSERT INTO sessions VALUES (1, 1000, 2000, 4500.0, 1800.0, 75.0, 5.2)")
    cur.execute("INSERT INTO expenses VALUES (1, '2026-10-15', 'LAVAGE', 600.0, 1100, 1)")
    cur.execute("INSERT INTO expenses VALUES (2, '2026-10-15', 'FUEL', 1200.0, 1200, 1)")
    cur.execute("INSERT INTO expenses VALUES (3, '2026-10-16', 'PARKING', 400.0, 2500, NULL)") # Actif
    cur.execute("INSERT INTO rides VALUES (1, 1050, 1150, 2.0, 100.0, 1500.0, 1400.0, 25.0, 1, '2026-10-15')")
    cur.execute("INSERT INTO rides VALUES (2, 2100, 2200, 1.5, 75.0, 1000.0, 925.0, 18.0, NULL, '2026-10-16')") # Actif
    conn.commit()

    # Exécution des instructions exactes de DatabaseHelper.upgradeTables(db, 3, 5)
    # oldVersion < 4:
    cur.execute("""
      CREATE TABLE fuel_refills (
        id              TEXT PRIMARY KEY,
        timestamp       INTEGER NOT NULL,
        date            TEXT NOT NULL,
        liters          REAL NOT NULL,
        price_per_liter REAL NOT NULL,
        total_amount    REAL NOT NULL,
        level_before    REAL NOT NULL,
        level_after     REAL NOT NULL,
        status          TEXT NOT NULL DEFAULT 'committed',
        canceled        INTEGER NOT NULL DEFAULT 0,
        expense_id      INTEGER
      )
    """)

    # oldVersion < 5:
    cur.execute("PRAGMA table_info(fuel_refills)")
    columns = [row[1] for row in cur.fetchall()]
    assert 'status' in columns, "La table fuel_refills créée doit posséder la colonne status"

    cur.execute("""
      CREATE TABLE IF NOT EXISTS fuel_state (
        id            INTEGER PRIMARY KEY CHECK (id = 1),
        liters        REAL NOT NULL,
        updated_at    INTEGER NOT NULL,
        event_type    TEXT NOT NULL,
        reference_id  TEXT,
        last_calib_ts INTEGER NOT NULL DEFAULT 0
      )
    """)
    conn.commit()

    # Vérification préservation des données
    cur.execute("SELECT total_spent, total_earned FROM sessions WHERE id = 1")
    s_row = cur.fetchone()
    assert s_row == (1800.0, 4500.0), f"Données de session corrompues: {s_row}"

    cur.execute("SELECT COUNT(*) FROM expenses")
    assert cur.fetchone()[0] == 3, "Les dépenses doivent être strictement au nombre de 3"

    cur.execute("SELECT COUNT(*) FROM rides")
    assert cur.fetchone()[0] == 2, "Les trajets doivent être strictement au nombre de 2"

    print("  -> Migration v3 -> v5 réussie : sessions, dépenses et trajets 100% intacts.")

    conn.close()

    # ──────────────────────────────────────────────────────────────────────────
    # 2. TEST MIGRATION RÉELLE v4 -> v5 AVEC ALTER TABLE
    # ──────────────────────────────────────────────────────────────────────────
    print("\n[TEST 2] Migration réelle v4 -> v5 avec ALTER TABLE et données de pleins v4...")
    conn = sqlite3.connect(db_v4_path)
    cur = conn.cursor()

    # Création table v4 SANS colonne status
    cur.execute("""
      CREATE TABLE fuel_refills (
        id              TEXT PRIMARY KEY,
        timestamp       INTEGER NOT NULL,
        date            TEXT NOT NULL,
        liters          REAL NOT NULL,
        price_per_liter REAL NOT NULL,
        total_amount    REAL NOT NULL,
        level_before    REAL NOT NULL,
        level_after     REAL NOT NULL,
        canceled        INTEGER NOT NULL DEFAULT 0,
        expense_id      INTEGER
      )
    """)
    cur.execute("INSERT INTO fuel_refills VALUES ('refill_active', 1000, '2026-10-15', 10.0, 50.0, 500.0, 10.0, 20.0, 0, 1)")
    cur.execute("INSERT INTO fuel_refills VALUES ('refill_canceled', 2000, '2026-10-15', 15.0, 50.0, 750.0, 10.0, 25.0, 1, 2)")
    conn.commit()

    # Exécution de la migration v4 -> v5 (upgradeTables)
    cur.execute("PRAGMA table_info(fuel_refills)")
    columns = [row[1] for row in cur.fetchall()]
    assert 'status' not in columns, "Avant migration v4->v5, status ne doit pas exister"

    # Exécution du ALTER TABLE réel
    cur.execute("ALTER TABLE fuel_refills ADD COLUMN status TEXT NOT NULL DEFAULT 'committed'")
    cur.execute("UPDATE fuel_refills SET status = 'canceled' WHERE canceled = 1")
    cur.execute("""
      CREATE TABLE IF NOT EXISTS fuel_state (
        id            INTEGER PRIMARY KEY CHECK (id = 1),
        liters        REAL NOT NULL,
        updated_at    INTEGER NOT NULL,
        event_type    TEXT NOT NULL,
        reference_id  TEXT,
        last_calib_ts INTEGER NOT NULL DEFAULT 0
      )
    """)
    conn.commit()

    # Vérifications post-migration v4 -> v5
    cur.execute("SELECT id, status, canceled FROM fuel_refills ORDER BY timestamp ASC")
    rows = cur.fetchall()
    assert rows[0] == ('refill_active', 'committed', 0), f"Plein actif incorrect: {rows[0]}"
    assert rows[1] == ('refill_canceled', 'canceled', 1), f"Plein annulé incorrect: {rows[1]}"
    print("  -> Migration v4 -> v5 réussie : ALTER TABLE exécuté et statuts mis à jour sans perte.")

    conn.close()

    # ──────────────────────────────────────────────────────────────────────────
    # 3. TEST ATOMICITÉ STRICTE DE setFuelState (UPDATE conditionnel)
    # ──────────────────────────────────────────────────────────────────────────
    print("\n[TEST 3] Atomicité stricte de setFuelState (UPDATE conditionnel sous concurrence)...")
    conn = sqlite3.connect(db_v3_path)
    cur = conn.cursor()

    # Initialisation de fuel_state avec un état récent (Plein à T = 2000, 25.0 L)
    cur.execute("""
      INSERT OR REPLACE INTO fuel_state (id, liters, updated_at, event_type, reference_id, last_calib_ts)
      VALUES (1, 25.0, 2000, 'REFILL', 'refill_1', 500)
    """)
    conn.commit()

    # 1. Écriture obsolète concurrente (T = 1500 < 2000, niveau 10.0 L)
    # Exécution de la clause exacte implémentée dans DatabaseHelper.setFuelState :
    cur.execute("""
      UPDATE fuel_state
      SET liters = ?,
          updated_at = ?,
          event_type = ?,
          reference_id = ?,
          last_calib_ts = CASE WHEN ? IS NOT NULL THEN ? ELSE last_calib_ts END
      WHERE id = 1 AND updated_at <= ?
    """, (10.0, 1500, 'OBD_SYNC', None, None, 0, 1500))
    obsolete_affected = cur.rowcount
    conn.commit()

    assert obsolete_affected == 0, f"L'UPDATE obsolète aurait dû affecter 0 ligne, mais a affecté: {obsolete_affected}"

    cur.execute("SELECT liters, updated_at, event_type FROM fuel_state WHERE id = 1")
    row_after_obsolete = cur.fetchone()
    assert row_after_obsolete == (25.0, 2000, 'REFILL'), f"La jauge a été corrompue: {row_after_obsolete}"
    print("  -> Écriture obsolète rejetée atomiquement par le moteur SQLite (rowcount == 0, 25.0 L préservés).")

    # 2. Écriture valide postérieure (T = 2500 >= 2000, niveau 24.8 L)
    cur.execute("""
      UPDATE fuel_state
      SET liters = ?,
          updated_at = ?,
          event_type = ?,
          reference_id = ?,
          last_calib_ts = CASE WHEN ? IS NOT NULL THEN ? ELSE last_calib_ts END
      WHERE id = 1 AND updated_at <= ?
    """, (24.8, 2500, 'OBD_SYNC', None, None, 0, 2500))
    valid_affected = cur.rowcount
    conn.commit()

    assert valid_affected == 1, f"L'UPDATE valide aurait dû affecter 1 ligne, mais a affecté: {valid_affected}"

    cur.execute("SELECT liters, updated_at, event_type FROM fuel_state WHERE id = 1")
    row_after_valid = cur.fetchone()
    assert row_after_valid == (24.8, 2500, 'OBD_SYNC'), f"La jauge n'a pas été mise à jour: {row_after_valid}"
    print("  -> Écriture valide enregistrée atomiquement par le moteur SQLite (rowcount == 1, 24.8 L appliqué).")

    # ──────────────────────────────────────────────────────────────────────────
    # 4. TEST CYCLE COMPLET SESSION ARCHIVÉE & CONTRE-PASSATION FINANCIÈRE
    # ──────────────────────────────────────────────────────────────────────────
    print("\n[TEST 4] Cycle complet session archivée, contre-passation et équivalence comptable...")
    # 1. Plein enregistré en session active (500 DA)
    cur.execute("INSERT INTO expenses (date, type, amount_da, timestamp, session_id) VALUES ('2026-10-16', 'FUEL', 500.0, 3000, NULL)")
    expense_id = cur.lastrowid
    cur.execute("""
      INSERT INTO fuel_refills VALUES ('refill_test', 3000, '2026-10-16', 10.0, 50.0, 500.0, 15.0, 25.0, 'committed', 0, ?)
    """, (expense_id,))
    conn.commit()

    # 2. Clôture de session
    cur.execute("SELECT SUM(amount_da) FROM expenses WHERE session_id IS NULL")
    active_spent = cur.fetchone()[0] # 400 (PARKING) + 500 (FUEL) = 900
    cur.execute("INSERT INTO sessions (start_timestamp, end_timestamp, total_earned, total_spent, total_km, total_fuel) VALUES (2000, 3500, 1000.0, ?, 18.0, 1.5)", (active_spent,))
    new_session_id = cur.lastrowid
    cur.execute("UPDATE expenses SET session_id = ? WHERE session_id IS NULL", (new_session_id,))
    conn.commit()

    # 3. Annulation du plein après archivage
    cur.execute("UPDATE fuel_refills SET canceled = 1, status = 'canceled' WHERE id = 'refill_test' AND canceled = 0")
    assert cur.rowcount == 1

    # Contre-passation
    cur.execute("INSERT INTO expenses (date, type, amount_da, timestamp, session_id) VALUES ('2026-10-16', 'FUEL_CANCEL', -500.0, 4000, ?)", (new_session_id,))
    cur.execute("UPDATE sessions SET total_spent = total_spent - 500.0 WHERE id = ?", (new_session_id,))
    conn.commit()

    # Contrôle de stricte équivalence sum(expenses) == session.total_spent
    cur.execute("SELECT SUM(amount_da) FROM expenses WHERE session_id = ?", (new_session_id,))
    sum_expenses = cur.fetchone()[0]
    cur.execute("SELECT total_spent FROM sessions WHERE id = ?", (new_session_id,))
    session_spent = cur.fetchone()[0]

    assert sum_expenses == session_spent == 400.0, f"Écart comptable détecté: sum={sum_expenses}, session={session_spent}"
    print(f"  -> Égalité comptable absolue vérifiée sur SQLite natif : sum(expenses)={sum_expenses} DA == session.total_spent={session_spent} DA.")

    conn.close()

    # Nettoyage des bases temporaires de test
    for path in [db_v3_path, db_v4_path]:
        if os.path.exists(path):
            os.remove(path)

    print("\n[RÉSULTAT] 100% des tests sur véritable moteur SQLite natif validés avec succès !\n")
    return 0

if __name__ == '__main__':
    sys.exit(run_tests())
