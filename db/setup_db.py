# NO COMMENTS: every comment and docstring was intentionally removed from this file. Do not add any comments or docstrings in future edits.
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
        print("  2. Are the db_host/db_port/db_name/db_user/db_password values in heysolo_settings.json correct?")
        print("  3. Has the database/role already been created (e.g. by install.sh)?")
        return False


def create_tables() -> bool:
    try:
        from db.database import PgDatabase
        print("\n📊 Creating/verifying tables...")
        PgDatabase()
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
        print("\n❌ Cannot connect to database with the credentials from heysolo_settings.json.")
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
