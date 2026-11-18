"""Run walkthrough queries against the integration-test DuckDB file.

From integration_tests/ (after `uv run --project .. dbt build --profiles-dir .`):
    uv run --project .. python explore/run.py            # list the steps
    uv run --project .. python explore/run.py 03         # run step 03 (every query in the file)
    uv run --project .. python explore/run.py all        # run every step

Queries are split on lines that start with `-- query:`; each query's title is printed first.
Edit the .sql files freely: change the person, the date, the segment, and re-run.
"""
import pathlib, sys
import duckdb

here = pathlib.Path(__file__).parent
db = here.parent / "pocore_test.duckdb"
steps = sorted(here.glob("[0-9][0-9]_*.sql"))

if len(sys.argv) < 2:
    for s in steps:
        first = s.read_text().splitlines()[0].lstrip("- ")
        print(f"{s.name[:2]}  {first}")
    sys.exit(0)

wanted = steps if sys.argv[1] == "all" else [s for s in steps if s.name.startswith(sys.argv[1])]
con = duckdb.connect(str(db), read_only=True)
for step in wanted:
    print("\n" + "=" * 100 + f"\n{step.name}\n" + "=" * 100)
    for block in step.read_text().split("-- query:")[1:]:
        title, _, sql = block.partition("\n")
        print(f"\n>>> {title.strip()}")
        con.sql(sql).show(max_width=250, max_rows=60)
