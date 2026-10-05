"""Rebuilds the chat-agent test fixture from the lgu_facts migrations.

    python tool/gen_lgu_facts_fixture.py

Replays every INSERT/UPDATE on public.lgu_facts in supabase/migrations, in
filename order, into an in-memory SQLite table, and writes the published,
non-empty rows (as the client sends them, ordered by sort_order) to
supabase/functions/chat-agent/lgu_facts_fixture.json.

Why a replay and not a live query: the read-only audit role cannot see
lgu_facts (RLS), and there is no in-app editor, so the migrations ARE the
table. Re-run this whenever a migration touches lgu_facts.
"""
import glob
import json
import re
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "supabase/functions/chat-agent/lgu_facts_fixture.json"


def statements(sql: str):
    """Splits on ';' outside string literals and drops -- comments."""
    out, cur, i, quoted = [], [], 0, False
    while i < len(sql):
        c = sql[i]
        if quoted:
            cur.append(c)
            if c == "'":
                if sql[i + 1:i + 2] == "'":
                    cur.append("'")
                    i += 1
                else:
                    quoted = False
        elif sql.startswith("--", i):
            j = sql.find("\n", i)
            i = len(sql) if j < 0 else j
            continue
        elif c == "'":
            quoted = True
            cur.append(c)
        elif c == ";":
            out.append("".join(cur))
            cur = []
        else:
            cur.append(c)
        i += 1
    out.append("".join(cur))
    return out


def main():
    db = sqlite3.connect(":memory:")
    db.execute("attach ':memory:' as public")
    db.execute(
        "create table public.lgu_facts(key text primary key, label text,"
        " value text default '', category text default 'general',"
        " sort_order int default 0, is_published int default 1)"
    )
    for path in sorted(glob.glob(str(ROOT / "supabase/migrations/*.sql"))):
        for st in statements(Path(path).read_text(encoding="utf-8")):
            # Postgres joins adjacent literals split across lines; SQLite won't.
            st = re.sub(r"'\s*\n\s*'", "", st.strip())
            if re.match(r"(insert into|update) public\.lgu_facts", st, re.I):
                db.execute(st)
    rows = db.execute(
        "select key, label, value, category from public.lgu_facts"
        " where value <> '' and is_published order by sort_order, key"
    ).fetchall()
    facts = [dict(key=k, label=l, value=v, category=c) for k, l, v, c in rows]
    OUT.write_text(json.dumps(facts, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"{len(facts)} facts -> {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
