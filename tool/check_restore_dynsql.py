"""Parse every dynamic SQL template in admin_apply_restore, FROM THE SOURCE.

Why this exists
---------------
libpg_query parses plpgsql bodies but treats `EXECUTE format('...')` as an
opaque expression, so the SQL *inside* those templates is never checked. On
2026-10-22 that gap shipped a real bug to production: the pass-1 INSERT read

    insert into public.%I (%s) select %s from _restore_stage
                                              ^ no alias

while its column list emitted `s.<col>`. Every real restore failed with
42P01. A dry run never reaches that statement, so previews looked perfect.

It was missed twice:
  1. libpg_query cannot see inside EXECUTE format().
  2. A hand-written check of the templates "passed", because the templates had
     been RETYPED from memory with the alias present. A fixture that is wrong
     in the same way as the code proves nothing.

So this script does NOT retype anything. It extracts each template from the
migration file, substitutes %I/%s/%L the way the function does at runtime, and
parses the result with the real Postgres parser.

Usage:
    python -I tool/check_restore_dynsql.py [migration.sql]
"""
import re
import sys

from pglast import parser

DEFAULT = "supabase/migrations/20261022000000_backup_and_recovery.sql"

# Two shapes, so a single-column PK and a composite PK are both covered.
FIXTURES = [
    {
        "label": "reports (single PK, self-FK, user column)",
        "tbl": "reports",
        "pk": ["id"],
        "cols": ["id", "user_id", "status", "ai_classified_at", "duplicate_of"],
        "self": "duplicate_of",
    },
    {
        "label": "user_roles (composite PK, no self-FK)",
        "tbl": "user_roles",
        "pk": ["user_id", "role_id"],
        "cols": ["user_id", "role_id"],
        "self": None,
    },
]


def templates_from_source(path):
    """Every single-quoted SQL template inside admin_apply_restore's body.

    Three things here are load-bearing, each learned by getting it wrong:

    1. Start at the `create ... function admin_apply_restore` DEFINITION, not
       at the first mention of the name -- that is a header comment 229 chars
       into the file, and sweeping from there pulls in prose.
    2. Strip `--` comments BEFORE pairing quotes. The comments in this file
       contain apostrophes ("function's", "Mayor's Office") and backticked
       identifiers; leaving them in desynchronises every quote pair after the
       first one, so real templates stop matching and the scan silently
       returns almost nothing.
    3. Require a SQL verb AND a plausible length, so `'update set '` -- a
       fragment concatenated into a larger statement -- is not mistaken for a
       whole template.
    """
    src = open(path, encoding="utf-8").read()

    m = re.search(r"create\s+(or\s+replace\s+)?function\s+public\.admin_apply_restore",
                  src, re.I)
    if not m:
        raise SystemExit("could not find the admin_apply_restore definition")
    body = src[m.start():]
    end = body.find("\n$$;")
    if end != -1:
        body = body[:end]

    # Drop line comments; keep everything else byte-for-byte.
    body = "\n".join(re.sub(r"--.*$", "", line) for line in body.split("\n"))

    out = []
    for raw in re.findall(r"'((?:[^']|'')*)'", body):
        text = raw.replace("''", "'")
        if not re.match(r"\s*(insert|select|update|delete|alter|drop|create)\b",
                        text, re.I):
            continue
        # A real template names a table or has a placeholder; `update set ` and
        # `select count(*) from _restore_stage` differ by far more than length,
        # so require some structure rather than trusting a character count.
        if "%" not in text and "_restore_stage" not in text:
            continue
        out.append(text)
    return out


def fill(tmpl, fx):
    """Substitute the format() placeholders the way the function does.

    The argument list is chosen PER TEMPLATE, matched by a distinctive phrase,
    because a placeholder's meaning depends on where it sits in that specific
    statement. A single positional queue shared across templates cannot work:
    it produced `max(nothing)` and `s.user_roles`, which failed to parse for
    reasons that had nothing to do with the code under test -- noise that
    hides the one real defect.

    Returns None for a template this fixture does not exercise.
    """
    cols, pk, self_col, tbl = fx["cols"], fx["pk"], fx["self"], fx["tbl"]

    same = " and ".join(f"live.{c} is not distinct from s.{c}" for c in cols)
    pkjoin = " and ".join(f"live.{k} = s.{k}" for k in pk)
    collist = ", ".join(cols)
    sellist = ", ".join(("null" if c == self_col else f"s.{c}") for c in cols)
    setlist = ", ".join(f"{c} = excluded.{c}"
                        for c in cols if c not in pk and c != self_col)
    pklist = ", ".join(pk)
    user_col = "user_id" if "user_id" in cols else pk[0]
    seq_col = pk[0]

    flat = " ".join(tmpl.split())

    if "disable trigger" in flat or "enable trigger" in flat:
        args = [tbl]
    elif "jsonb_populate_record" in flat:
        args = [tbl]
    elif "auth.users u" in flat:
        args = [user_col, user_col]
    elif "interval" in flat and "created_at" in flat:
        args = ["90"]
    elif "jsonb_build_object" in flat:
        args = [pk[0], pk[0], same, tbl, pkjoin]
    elif flat.lower().startswith("insert into public."):
        args = [tbl, collist, sellist, pklist,
                ("update set " + setlist) if setlist else "nothing"]
    elif flat.lower().startswith("update public."):
        if self_col is None:
            return None  # the self-FK pass never runs for this table
        args = [tbl, self_col, self_col, pkjoin, self_col, self_col, self_col,
                tbl, pk[0], self_col]
    elif "setval" in flat:
        args = [f"public.{tbl}", seq_col, seq_col, tbl, seq_col, tbl]
    else:
        args = []  # no placeholders (drop table, select count(*), ...)

    out, qi, i = [], 0, 0
    while i < len(tmpl):
        if tmpl[i] == "%" and i + 1 < len(tmpl):
            spec = tmpl[i + 1]
            if spec in "IsL":
                if qi >= len(args):
                    raise AssertionError(
                        f"template needs more arguments than mapped "
                        f"({qi + 1} > {len(args)}): {flat[:70]}")
                val = args[qi]
                qi += 1
                out.append(f"'{val}'" if spec == "L" else val)
                i += 2
                continue
            if spec == "%":
                out.append("%")
                i += 2
                continue
        out.append(tmpl[i])
        i += 1

    if qi != len(args):
        raise AssertionError(
            f"mapped {len(args)} arguments but template used {qi}: {flat[:70]}")
    return "".join(out)


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT
    tmpls = templates_from_source(path)
    print(f"{path}\n  {len(tmpls)} dynamic SQL template(s) extracted from source\n")

    failures = 0
    for fx in FIXTURES:
        print(f"  -- {fx['label']}")
        for t in tmpls:
            sql = fill(t, fx)
            if sql is None:
                continue  # this fixture does not exercise that template
            head = " ".join(t.split())[:62]
            try:
                parser.parse_sql(sql)
                print(f"    [pass] {head}")
            except Exception as exc:
                failures += 1
                print(f"    [FAIL] {head}")
                print(f"           {exc}")
                print(f"           generated: {' '.join(sql.split())[:200]}")
        print()

    # ── The check that actually catches the 2026-10-22 bug ──────────────────
    #
    # Parsing CANNOT find it. `insert into t (...) select s.a from _restore_stage`
    # is valid SQL grammar -- a missing table alias is a NAME-RESOLUTION error,
    # raised only at execution time as 42P01. Every parser on earth accepts it.
    #
    # It also has to run on the FILLED sql, not the template: in the template
    # the column list is the placeholder `%s`, and the `s.<col>` references
    # only exist after substitution.
    print("  -- alias resolution (what the parser cannot see)")
    for fx in FIXTURES:
        for t in tmpls:
            sql = fill(t, fx)
            if sql is None or "_restore_stage" not in sql:
                continue
            # Which aliases does this statement actually define?
            defined = set(re.findall(r"_restore_stage\s+(?:as\s+)?([a-z_]+)", sql))
            defined |= set(re.findall(r"public\.[a-z_]+\s+(?:as\s+)?([a-z_]+)", sql))
            defined |= set(re.findall(r"auth\.users\s+(?:as\s+)?([a-z_]+)", sql))
            used = set(re.findall(r"\b([a-z_]+)\.[a-z_]+", sql))
            # Schema qualifiers and real table names are not aliases.
            used -= {"public", "auth", "pg_catalog", "information_schema"}
            #  is ON CONFLICT's standard pseudo-table, not an alias.
            used -= {"excluded"}
            used -= {fx["tbl"], "users", "_restore_stage"}
            missing = sorted(used - defined)
            if missing:
                failures += 1
                print(f"    [FAIL] {fx['label']}: uses {missing} with no such alias")
                print(f"           {' '.join(sql.split())[:190]}")
    if not failures:
        print("    [pass] every qualifier resolves to a defined alias")

    print("OK — every template parses" if not failures
          else f"*** {failures} problem(s) ***")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
