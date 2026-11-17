# Bakehouse Sales Genie Agent

Source-controlled export of the Genie Agent **lalitstar - Bakehouse Sales**
(original space ID `01f1e205aec91588a33bf2e242c332a6`, exported 2026-11-16 23:30 UTC).
This folder contains everything needed to recreate, deploy, and evaluate the agent with the Databricks REST API.

## Folder contents

| File | Purpose |
| --- | --- |
| `README.md` | This file. |
| `serialized_space.json` | Full agent configuration (the `serialized_space` payload): tables and column configs, synonyms, text instructions, example SQL, join specs, SQL expressions, benchmarks. **This is what the API needs.** |
| `space_metadata.json` | Title, description, warehouse ID, parent folder, etag and timestamps of the exported version. |
| `agent_sql.sql` | Human-readable copy of the agent's SQL (example query, join, `region` expression, benchmark answers). Reference only, not used by the API. |

## What the agent contains

* **Tables** (`labuser18456042_1794852728.genie_course_bakehouse`): `media_customer_reviews_gold`, `sales_customers_gold`, `sales_franchises_gold`, `sales_suppliers_gold`, `sales_transactions_gold`
* **Synonyms**: `totalPrice` = revenue, sales, total sales, total revenue, income
* **Instructions**: USD formatting, 2-decimal rounding, franchise name with ID, fiscal year starting in February
* **Example SQL**: "Who are our best customers?" (top 10 by `totalPrice`)
* **Join**: `sales_franchises_gold.supplierID = sales_suppliers_gold.supplierID` (many-to-one, show orphaned rows)
* **SQL expression**: `region` (country mapped to APJ / AMER / EMEA / Other)
* **Benchmarks**: "What are total sales by region?", "How many customers do we have?"

Not included in the export: sharing permissions, conversation history, user feedback, previous benchmark run results, monitoring data.

## Prerequisites

* All 5 tables above exist and the caller has `SELECT` on them (plus `USE CATALOG` / `USE SCHEMA`).
* A SQL warehouse the caller can use (exported value: `f151794d102b8e21`, `shared_warehouse`).
* Authentication: a personal access token or OAuth token for the workspace.
* To deploy to another workspace or catalog, edit the table identifiers in `serialized_space.json` and `warehouse_id` / `parent_path` in `space_metadata.json` first.

In the examples below, replace each placeholder including the angle brackets, e.g. `<WORKSPACE_URL>` becomes `https://my-workspace.cloud.databricks.com`.

## API reference

| Step | Method and path |
| --- | --- |
| Create agent | `POST /api/2.0/genie/spaces` |
| Get agent (incl. config) | `GET /api/2.0/genie/spaces/{space_id}?include_serialized_space=true` |
| Update agent | `PATCH /api/2.0/genie/spaces/{space_id}` |
| Delete (trash) agent | `DELETE /api/2.0/genie/spaces/{space_id}` |
| Start benchmark eval run | `POST /api/2.0/genie/spaces/{space_id}/eval-runs` |
| Get eval run status | `GET /api/2.0/genie/spaces/{space_id}/eval-runs/{eval_run_id}` |
| List eval results | `GET /api/2.0/genie/spaces/{space_id}/eval-runs/{eval_run_id}/results` |
| Get eval result details | `GET /api/2.0/genie/spaces/{space_id}/eval-runs/{eval_run_id}/results/{result_id}` |

## 1. Create (deploy) the agent

The create request takes `serialized_space` as a **JSON string** (the file contents, escaped), plus `warehouse_id` (required), and optional `title`, `description`, `parent_path`.

### Python (Databricks SDK, e.g. from a notebook in this Git folder)

```python
import json
from databricks.sdk import WorkspaceClient

w = WorkspaceClient()  # uses notebook auth, or DATABRICKS_HOST / DATABRICKS_TOKEN
folder = "<PATH_TO_THIS_FOLDER>"  # e.g. /Workspace/Users/<you>/<repo>/Bakehouse_Sales-agent

serialized_space = open(f"{folder}/serialized_space.json").read()
meta = json.load(open(f"{folder}/space_metadata.json"))

space = w.api_client.do("POST", "/api/2.0/genie/spaces", body={
    "serialized_space": serialized_space,
    "warehouse_id": meta["warehouse_id"],
    "title": meta["title"],
    "description": meta["description"],
    "parent_path": meta["parent_path"],
})
space_id = space["space_id"]
print("Created agent:", space_id)
```

### curl

```bash
export DATABRICKS_HOST="<WORKSPACE_URL>"
export DATABRICKS_TOKEN="<TOKEN>"

# Build the request body: serialized_space must be a string, so jq --rawfile loads the file as an escaped string
jq -n \
  --rawfile ss serialized_space.json \
  --slurpfile m space_metadata.json \
  '{serialized_space: $ss, warehouse_id: $m[0].warehouse_id, title: $m[0].title,
    description: $m[0].description, parent_path: $m[0].parent_path}' > create_body.json

curl -s -X POST "$DATABRICKS_HOST/api/2.0/genie/spaces" \
  -H "Authorization: Bearer $DATABRICKS_TOKEN" \
  -H "Content-Type: application/json" \
  -d @create_body.json
```

The response contains the new `space_id`. A new agent always gets a new space ID.

## 2. Verify the deployed configuration

```python
new = w.api_client.do("GET", f"/api/2.0/genie/spaces/{space_id}",
                      query={"include_serialized_space": "true"})
deployed = json.loads(new["serialized_space"])
source = json.loads(serialized_space)

for section in ["data_sources", "benchmarks"]:
    print(section, "matches:", deployed[section] == source[section])
for key in source["instructions"]:
    print("instructions." + key, "matches:", deployed["instructions"][key] == source["instructions"][key])
```

**Expected difference:** on create, Genie may add extra `join_specs` it infers from Unity Catalog key
constraints (in testing, 4 extra many-to-one joins were added). The original join and its instruction are preserved.
All other sections should match exactly. Remove the extra joins with an update (step 4) if you need an exact match.

## 3. Evaluate the agent with its benchmarks

Start a run (an empty body evaluates all benchmark questions; pass `benchmark_question_ids` to run a subset), poll until it finishes, then inspect results.

```python
import time

run = w.api_client.do("POST", f"/api/2.0/genie/spaces/{space_id}/eval-runs", body={})
run_id = run["eval_run_id"]

while True:
    status = w.api_client.do("GET", f"/api/2.0/genie/spaces/{space_id}/eval-runs/{run_id}")
    if status.get("eval_run_status") not in ("RUNNING", "NOT_STARTED"):
        break
    time.sleep(10)

print(status["eval_run_status"], f"{status.get('num_correct', 0)}/{status.get('num_questions')} correct,",
      status.get("num_needs_review", 0), "need review")

results = w.api_client.do("GET", f"/api/2.0/genie/spaces/{space_id}/eval-runs/{run_id}/results")
for r in results.get("eval_results", []):
    d = w.api_client.do("GET", f"/api/2.0/genie/spaces/{space_id}/eval-runs/{run_id}/results/{r['result_id']}")
    print("-", r["question"], "->", d.get("assessment"))
    print("  Generated SQL:", d["actual_response"][0]["response"][:200])
```

Run statuses: `NOT_STARTED`, `RUNNING`, `DONE`, `EVALUATION_FAILED`, `EVALUATION_CANCELLED`, `EVALUATION_TIMEOUT`.
Each result detail includes the `assessment` (e.g. `GOOD`), the agent's generated SQL and its result set (`actual_response`), and the benchmark SQL and its result set (`expected_response`).

With curl:

```bash
curl -s -X POST "$DATABRICKS_HOST/api/2.0/genie/spaces/<SPACE_ID>/eval-runs" \
  -H "Authorization: Bearer $DATABRICKS_TOKEN" -H "Content-Type: application/json" -d '{}'

curl -s "$DATABRICKS_HOST/api/2.0/genie/spaces/<SPACE_ID>/eval-runs/<EVAL_RUN_ID>" \
  -H "Authorization: Bearer $DATABRICKS_TOKEN"

curl -s "$DATABRICKS_HOST/api/2.0/genie/spaces/<SPACE_ID>/eval-runs/<EVAL_RUN_ID>/results" \
  -H "Authorization: Bearer $DATABRICKS_TOKEN"
```

### Reference results (validated 2026-11-16)

| Benchmark | Expected answer | Assessment |
| --- | --- | --- |
| What are total sales by region? | APJ 29,802; AMER 21,687; EMEA 14,982 | GOOD |
| How many customers do we have? | 300 | GOOD |

Values depend on the current table data.

## 4. Update an existing agent from this folder

`serialized_space` in an update is a **full replacement**. Pass the `etag` from a recent GET to avoid overwriting concurrent changes.

```python
current = w.api_client.do("GET", f"/api/2.0/genie/spaces/{space_id}")
w.api_client.do("PATCH", f"/api/2.0/genie/spaces/{space_id}", body={
    "serialized_space": open(f"{folder}/serialized_space.json").read(),
    "etag": current["etag"],
})
```

## 5. Delete an agent

```python
w.api_client.do("DELETE", f"/api/2.0/genie/spaces/{space_id}")  # moves the agent to trash
```

## 6. Re-export after changes in the UI

To keep this folder current, fetch the agent and overwrite the files, then commit and push:

```python
s = w.api_client.do("GET", "/api/2.0/genie/spaces/<SPACE_ID>", query={"include_serialized_space": "true"})
open(f"{folder}/serialized_space.json", "w").write(json.dumps(json.loads(s["serialized_space"]), indent=2) + "\n")
meta = {k: s.get(k) for k in ["space_id", "title", "warehouse_id", "parent_path", "etag",
                              "create_time", "update_time", "description"]}
open(f"{folder}/space_metadata.json", "w").write(json.dumps(meta, indent=2) + "\n")
```

The `etag` in `space_metadata.json` identifies the exported version; compare it with a fresh GET to tell whether the live agent has changed since export.
