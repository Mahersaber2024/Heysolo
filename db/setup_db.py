"""
db/setup_db.py

Explicitly (re)creates every table heysolo_bot needs (experts, accounts,
bot_users, user_accounts, user_topics) by running the same SCHEMA that
db.database.PgDatabase normally runs the first time the bot connects.

install.sh calls this right after db.env is written and the venv (with
psycopg2) is ready, so a fresh install gets a fully migrated schema before
the systemd service ever starts - instead of relying on the bot's own lazy
migration on first connection. Safe to re-run any time (every statement in
SCHEMA is CREATE TABLE/INDEX IF NOT EXISTS).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import psycopg2

from db.database import db_params

DB_CONFIG = db_params()


def test_connection() -> bool:
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        cursor = conn.cursor()
        cursor.execute("SELECT version()")
        version = cursor.fetchone()
        print(f"✅ Connected to PostgreSQL: {version[0][:50]}...")
        cursor.close()
        conn.close()
        return True
    except Exception as e:
        print(f"❌ Connection failed: {e}")
        print("\n📌 Please check:")
        print("  1. Is PostgreSQL installed and running?")
        print("  2. Are the HEYSOLO_DB_* values in db.env correct?")
        print("  3. Has the database/role already been created (e.g. by install.sh)?")
        return False


def create_tables() -> bool:
    """Delegates to db.database.PgDatabase, which creates every table this
    bot needs (experts, accounts, bot_users, user_accounts, user_topics)
    with CREATE TABLE IF NOT EXISTS, so this is always safe to re-run."""
    try:
        from db.database import PgDatabase
        print("\n📊 Creating/verifying tables...")
        PgDatabase()  # __init__ connects, runs SCHEMA and seeds the default experts
        print("✅ experts, accounts, bot_users, user_accounts, user_topics ready")
        return True
    except Exception as e:
        print(f"❌ Error creating tables: {e}")
        return False


def show_tables():
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        cursor = conn.cursor()
        cursor.execute("""
            SELECT table_name FROM information_schema.tables
            WHERE table_schema = 'public' ORDER BY table_name
        """)
        tables = cursor.fetchall()

        if tables:
            print("\n📋 Tables in database:")
            print("-" * 30)
            for table in tables:
                try:
                    cursor.execute(f'SELECT COUNT(*) FROM "{table[0]}"')
                    count = cursor.fetchone()[0]
                    print(f"  • {table[0]} ({count} rows)")
                except Exception:
                    print(f"  • {table[0]}")
        else:
            print("\n📭 No tables found in database.")

        cursor.close()
        conn.close()
    except Exception as e:
        print(f"❌ Error showing tables: {e}")


def drop_all_tables():
    """Drop all tables (use with caution!)"""
    confirm = input("⚠️ Are you sure you want to drop ALL tables? (yes/no): ")
    if confirm.lower() != "yes":
        print("❌ Operation cancelled.")
        return False
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        cursor = conn.cursor()
        for table in ("user_topics", "user_accounts", "bot_users", "accounts", "experts"):
            cursor.execute(f'DROP TABLE IF EXISTS "{table}" CASCADE')
        conn.commit()
        cursor.close()
        conn.close()
        print("✅ All tables dropped successfully!")
        return True
    except Exception as e:
        print(f"❌ Error dropping tables: {e}")
        return False


def main():
    auto_mode = "--auto" in sys.argv

    print("🚀 Setting up PostgreSQL tables for HeySolo Bot...")
    print("=" * 50)
    print(f"📊 Database: {DB_CONFIG['dbname']} @ {DB_CONFIG['host']}:{DB_CONFIG['port']}")
    print(f"👤 User: {DB_CONFIG['user']}")
    print("=" * 50)

    print("\n🔌 Testing connection...")
    if not test_connection():
        print("\n❌ Cannot connect to database with the credentials from db.env.")
        sys.exit(1)

    if not create_tables():
        print("❌ Failed to create tables.")
        sys.exit(1)

    show_tables()

    print("\n" + "=" * 50)
    print("✅ Database setup completed successfully!")

    if not auto_mode and "--drop" in sys.argv:
        drop_all_tables()


if __name__ == "__main__":
    main()
