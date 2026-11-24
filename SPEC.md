# po-donor-engine — Day-One Spec

Status: **draft** · 2026-11-10 · dbt package name: `po_donor_engine`

> **v0.2.0 (branch `v0.2.0`):** the package is now `po_core` (prefix `pocore_`), the entity `donor` is `person`, and the serving layer is replaced by **foundation** and **certified** tables. **`DESIGN_v0.2.0.md` supersedes** this spec's §3 (serving outputs), D13 (naming) and the layer table, and adds the new rules. Model and macro names below still use the old `pode_` prefix; read them as `pocore_`. A full fold-in of the design into this spec is still to do.

---

## 1. Purpose and scope

`po_donor_engine` is a reusable dbt package. Each client project:

1. Builds its own **conform** models (raw → the canonical shape).
2. Points the engine at them with vars.
3. Gets features, groups, KPIs and serving models without changing any engine code.

**This spec covers day one only.** Day one means the outputs available from the two required inputs, `donors` and `gifts`:

- **Group baselines:** how big each group is and how it historically performs on each KPI.
- **Group power:** what lift an experiment on that group could detect, and how long it would take.

Experiments (assignment, treatment lists, results, compliance) get their own spec later. They must not require changes to this contract, only optional additions.

**Method:** work backwards, from serving outputs to KPIs to features to the contract. **Every contract column must be used by at least one feature or KPI.** If nothing uses a column, it doesn't go in the contract.

---

## 2. Package interface

```yaml
# client dbt_project.yml
vars:
  po_donor_engine:
    as_of: "{{ env_var('PO_AS_OF', '2026-10-31') }}"   # scheduler sets PO_AS_OF; fallback is for local dev only (see D3)
    donors_model: conform_donors   # default: donors
    gifts_model:  conform_gifts    # default: gifts
```

- The engine owns `pode_can__donors` and `pode_can__gifts`. Each is a passthrough that selects explicit columns from `{{ pode_input_model('gifts') }}`, with the contract enforced and tests attached.
- **`pode_input_model(input)`** resolves `var('<input>_model')` to `ref(project_name, <model>)`. `project_name` is the root (client) project, and the two-argument `ref` makes the engine → client dependency explicit. Verified on DuckDB in step A: correct build order and no "package depends on root project" warning. A future `<input>_package` var (a MINOR change) would allow conform to come from a shared package.
- Vars map model **names**, not paths. Client conform models can live in any folder.
- Engine models are tagged `pode` (plus per-layer tags), so they can be selected regardless of folder layout (`--select tag:pode`).
- When contract or tests fail, everything downstream in the engine is skipped (`dbt build`).
- **Rules are tests, not `constraints:`.** Constraints are ignored on views (the canonical models are views) and are informational-only on some warehouses.
- Still to verify in step B: BigQuery `data_type` spellings in the contract, package schema naming alongside the client's `generate_schema_name`, and Lightdash picking up package models.

### 2a. Client control and extension

**Where tables land:** the client's warehouse, through the client's dbt connection. By default the schema is `<client target schema>_pode` (e.g. `analytics_pode`, `dbt_chris_pode`). dbt always uses the **client's** `generate_schema_name` macro, including for engine models, so a client's custom schema scheme applies to the engine as well.

**Names:** table name = model name (`pode_srv__group_summary`, …). Canonical models are views; everything else is tables.

**Clients control all of it** from their own `dbt_project.yml`:

```yaml
models:
  po_donor_engine:
    +schema: donor_engine        # instead of 'pode'
    can:
      +materialized: table       # instead of view
    srv:
      +schema: reporting
      pode_srv__group_summary:
        +alias: group_summary  # rename one table
```

They can also override `generate_schema_name` / `generate_alias_name`, set `+database`, or disable parts with `+enabled: false`.

**Extending the engine:**

| Extension | How | Supported? |
|---|---|---|
| Own models on top | `ref('pode_srv__…')` from the client project | Yes, the normal way |
| Custom groups | YAML `cust_*_vN` rules (§5a) | Yes |
| Own Lightdash views | YAML on their own downstream models | Yes |
| Edit an engine model | Not possible: `dbt deps` overwrites package files | No |
| Replace an engine model | `+enabled: false` plus their own model | Discouraged: it leaves the engine's guarantees and may break on upgrade |
| Something generally useful | Contribute it to the engine (MINOR release) | Preferred |

---

## 3. Serving outputs (day one)


Everything a client exposes lives in one schema, `pode_srv` (D13). Each table is a final answer at its stated grain. The full calculation tables behind them are internal (`pode_mtr__*`).

| table | grain | answers |
|---|---|---|
| `pode_srv__group_summary` | group | Who to focus on: size now, headline rate, detectable lift, testable?, value per +1 point |
| `pode_srv__group_summary_by_slice` | group × slice (`slice_by` = a breakdown column) | The same, split by channel / region / first-gift band / `attr_*` |
| `pode_srv__test_planning` | group × window × holdout % | Compare test options: detectable lift vs donors held out |
| `pode_srv__group_trend` | group × month-end | Size, entering / leaving, and gave / retained / revenue rates over time |
| `pode_srv__group_roster` | group × donor (latest month-end) | Who is in each group, to act on |
| `pode_srv__donor_movement` | fiscal year | New / second year / continuing / reactivated / reactivated second year / lost; retention |
| `pode_srv__donor_cohorts` | acquisition cohort × year | Each first-gift cohort through later years |
| `pode_srv__sustainer_ltv` | start cohort × slice | Sustainers started, survival at month N, LTV at N months; CPA and LTV:CPA when cost is supplied |
| `pode_srv__stage_transitions` | from month-end × horizon (3/12/24/36 months) × from stage × to stage | The donor journey: of donors in a stage then, where are they N months later; `is_latest` for an always-current view |
| `pode_srv__reconciliation` | month × category × donor type × eligibility × gift type × refund | Sign-off totals; every gift once, additive (§6.4) |
| `pode_srv__project_health` | check (finance: per year) | Is this project healthy? Freshness, gaps, recurring linking, empty groups, finance match (§6.4) |

### 3.1 Baselines and power (internal: `pode_mtr__group_baselines`, `pode_mtr__group_power`)

**Baselines:** one row per group × breakdown × KPI × window × anchor date: `n` (members on the anchor, always the denominator), `value`, `variance` (`p(1−p)` for rates, sample variance for means), `is_window_complete` (incomplete rows are kept, flagged, never pooled). Rate KPIs also carry `revenue_gap_per_success`: capped window revenue among donors who succeeded minus among those who didn't.

**Power:** one row per group × breakdown × KPI × window × lookback × holdout %. Three baselines, all pooled over complete anchors (Σ outcomes ÷ Σ n):

| baseline | anchors | use |
|---|---|---|
| `baseline_value` (typical) | last 12 (or 24) | context: the 12-month average |
| `baseline_recent` | last 3 | context: has something changed lately? |
| `baseline_same_season` | 11–13 months before `as_of` | **planning**: a test launched now runs through the same season. Year-end giving makes "recent" wrong every autumn. |

`baseline_planning` = same-season, else recent (`planning_basis` says which). `mde_abs_planning`, `is_testable` and the srv planning numbers use it. Known limit: after an unusual year (e.g. a surge), last year's season overstates this one. A first version, expected to be tuned with fundraisers.

MDE = (z₁₋α/₂ + z_power) · √(variance · (1/n_treatment + 1/n_holdout)). `is_testable` = relative MDE ≤ `max_plausible_relative_lift` (0.5). `readout_date_if_launched_now` = `as_of + outcome_window_days`.

**Headline choices per group:** `primary_window_days` (new 90, lapsed 180, others 365) and `primary_kpi` (`retained` for sustainers, `gave` otherwise); custom groups may set both. **Value** (summary only; observational, rough sizing, not a forecast): `value_per_point` = donors × 1 point × `revenue_gap_recent`, what each +1 point on the KPI is worth; the headline for ranking groups. `value_of_detectable_lift` = the same at the smallest provable lift; a floor for test planning only, because it shrinks as tests get more sensitive (bigger holdouts) and grows only with √n. (Replaced `opportunity_*` in v0.1.1-prototype.)

**Statistical settings are levers, but they get locked.**

| var | default |
|---|---|
| `alpha` (two-sided) | 0.05 |
| `power` | 0.8 |
| `holdout_grid` | [10, 15, 20, 30] |
| `baseline_lookback_months` | [12, 24] |

- These are planning settings. The values a client actually tests with are recorded in their `experiments` input before launch (pre-registration, §10).
- Results always use the pre-registered values. Changing them after seeing data means a new experiment, never a re-read.

Day-one deliverable phrased for the client: *"A 15% holdout on lapsed donors detects a 3-point reactivation lift, readable by May."*

### 3.2 Sustainer LTV (`pode_mtr__sustainer_month` → `pode_srv__sustainer_ltv`)

- Month 1 = month of the donor's first recurring payment (donor-level: restarts keep the original start). Revenue = recurring payments only.
- Survival at month N and LTV through month N divide by sustainers who have **reached** month N; null until someone has. Never extrapolated. (The demo's spreadsheet method divides by all starters; the two agree exactly for cohorts that have all reached N.)
- Cost is optional: the client adds `acquisition_cost` to `donors_extra_columns`. Paid = cost > 0. CPA = cost ÷ paid sustainers; LTV:CPA = paid sustainers' LTV ÷ CPA.
- Vars: `sustainer_survival_months` [2, 6, 12, 24], `sustainer_ltv_horizons_months` [12, 24, 60].
- Attribution modelling (how cost is allocated) stays in the client's conform, not the engine.

---

## 4. KPIs

**General form:** for donors in group S on anchor date A, the outcome happens in `(A, A + window]`. The denominator is every member of S on A. Experiments reuse the same definition with A = experiment start date, which keeps the baseline you sold and the metric you report identical.

**The KPI rule:** every experiment KPI has **one donor per denominator unit** (group members or assigned donors) and is either a **rate** or a **capped mean**. Anything else (ratio metrics like average gift size, medians, survival curves) is **descriptive only**. It can appear in baselines or Lightdash, but never in power or results.

**The window is a column, not part of the name.** One KPI at several `outcome_window_days` gives a cumulative curve (30 / 60 / 90 …). Only the window agreed before launch counts as the result. Earlier windows are labelled interim.

| kpi_id | metric_type | typical group / framing | default windows |
|---|---|---|---|
| `gave` | rate | new donors ("second gift"), lapsed ("reactivation"), active one-time ("retention") | 90 / 180 / 365 |
| `retained` | rate | sustainers ("still giving monthly N days later"): a recurring payment in the `recurring_active_days` (45) up to day A + N, the same rule as the sustainer group | 90 / 180 / 365 |
| `revenue_per_donor` | mean (capped) | any | 90 / 180 / 365 |

**Qualifying gift** (counts for `gave`): a non-refund gift with `is_kpi_eligible = true` where either
- `gift_type = 'one_time'`, or
- it is the first payment of a `recurring_schedule_id` not seen before A (a new sustainer sign-up).

Routine recurring payments don't count. **Upgrades to an existing schedule don't count on day one.** They become their own KPI once `recurring_schedules` is available.

**Revenue cap:** `revenue_per_donor` caps each donor's net revenue in the window at `var('revenue_cap')` (default $1,000; revisit per client, e.g. 99th percentile). The uncapped value is reported descriptively, so finance totals stay recognisable. The spec and the client deliverables must say clearly that experiment revenue is capped.

**Deferred:**
- Schedule-level recurring churn (needs `recurring_schedules`). Donor-level retention is covered by `retained`.
- Upgrades (needs `recurring_schedules`).
- Unsubscribe guardrail (needs `contactability_events`).

---

## 5. Features — `pode_ftr__donor_snapshot`

**Grain:** `donor_id × snapshot_date`. Every value is computed only from gifts with `gift_date <= snapshot_date` **and `is_kpi_eligible = true`**. A donor appears only from their `created_at`.

**Default group filter** (applied unless a group explicitly overrides it): `donor_type = 'individual' and not is_deceased`.

**As-of dates (snapshots):** month-ends for the last `snapshot_lookback_months` (default **72**, i.e. 6 years) up to `var('as_of')`. Not daily. (Experiment readouts anchor on the client's `assigned_date` in their own model, §10.)
- **This limits snapshot dates, not history.** Features at every snapshot still use all past gifts (lifetime giving, first gift date, …).
- **Validation:** the build fails if `snapshot_lookback_months < max(baseline_lookback_months) + max(KPI window in months)` (currently 24 + 12 = 36). Below that, power can't be computed.
- **Size check:** about donors × 72 rows. For 200k donors that's ~14M rows, which is fine as a full rebuild on BigQuery or Snowflake.
- **Built design (simple on purpose):** each donor × snapshot date joins that donor's gifts dated on or before it, aggregated with plain conditional sums. About 5s / 3.1M rows on BigQuery for the 77k-donor synthetic data. Optimization path for large clients (around 1M donors), in order; none changes outputs (PATCH releases):
  1. partition / cluster the `ftr` and `seg` tables by `snapshot_date` (then `group_id`);
  2. incremental snapshot (new month-ends plus a reprocessed trailing window), required to match `--full-refresh` exactly (tested);
  3. shorter `snapshot_lookback_months` (minimum 36);
  4. a windowed running-total design.
- **Possible later optimization:** build incrementally. Any incremental version must **reprocess a trailing window** (e.g. the last 3 months), because late-arriving gifts change recent snapshots. Without that, an incremental build would give different results from a full rebuild, which breaks D9.

| feature | derived from | notes |
|---|---|---|
| `first_gift_date`, `first_gift_amount`, `first_gift_band` | gifts | fixed bands: `<25`, `25–99`, `100–249`, `250–999`, `1000+` |
| `last_gift_date`, `days_since_last_gift` | gifts | |
| `gift_count_12m`, `net_giving_12m` | gifts | refunds netted, dated by refund date |
| `gift_count_lifetime`, `net_giving_lifetime` | gifts | |
| `is_new_donor` | gifts | first gift ≤ 90 days ago. A flag, so it can combine with other stages (e.g. new monthly donors = `is_new_donor and is_recurring_active`). |
| `is_reactivated` | gifts | gave in the last 365 days, after a gap of more than 365 days before that |
| `first_gift_year`, `last_gift_year` | gifts | calendar year |
| `net_giving_ytd` | gifts | net eligible giving, Jan 1 to `snapshot_date` |
| `net_giving_prior_year` | gifts | net eligible giving in the full previous calendar year |
| `gave_prior_year_not_ytd` | gifts | calendar-year LYBUNT. Depends on time of year: in February almost everyone qualifies, so it's most meaningful from about Q3 (say so in the column description). |
| `is_recurring_active` | gifts, or `recurring_schedules` if provided | **Default:** heuristic, a recurring payment within the last N days (var, default 45). Good enough on day one because day-one KPIs don't target sustainers; its job is to keep them out of other groups. **If `recurring_schedules_model` is set:** active means `start_date <= snapshot_date` and (`cancel_date` is null or `cancel_date > snapshot_date`). Same column, more accurate. Required for sustainer KPIs. |
| `lifecycle_stage` | the above + `donors.created_at` | exactly one of `sustainer` / `new` / `active` / `lapsed` / `deep_lapsed` / `prospect`; fixed rules (see D6) |
| `acquisition_channel`, `acquisition_theme` | donors | current value; allowed under D7 |
| `region` | donors | current value; allowed under D7 |

Not on day one: reachable channels (needs `contactability_events`).

The `pode_ftr__donor_snapshot` column list is the **menu for group rules**. It must be documented clearly (column descriptions in YAML).

---

## 5a. Groups

### Standard vs custom

| | Defined in | Changed by | Id prefix |
|---|---|---|---|
| **Standard** | engine package; identical for every client | engine release only | `std_` |
| **Custom** | client `dbt_project.yml` | you and the client, per client | `cust_` |

- Every client gets all standard groups automatically: `std_prospect_v1`, `std_new_v1`, `std_active_v1`, `std_lapsed_v1`, `std_deep_lapsed_v1`, `std_sustainer_v1`. **A client with no custom groups configures nothing.**
- Standard groups can't be edited per client. "Lapsed, but our way" becomes a custom group (`cust_lapsed_clientx_v1`), so standard groups stay comparable across clients.

### Config

```yaml
vars:
  po_donor_engine:
    groups:
      - id: cust_lapsed_mid_value_v1
        label: "Lapsed, $100+ lifetime"
        rule: "lifecycle_stage = 'lapsed' and net_giving_lifetime >= 100"
```

- **Naming:** lowercase snake_case, `std_` / `cust_` prefix, ending in `_v<N>`. The engine validates this at compile time. A custom id without `cust_`, or a duplicate id, fails the build.
- **Versioning:** to change a rule, add a new id with the next `_v<N>`. Never edit an existing one. Git is the history.
- **Overlap is allowed.** A donor can be in several groups. Priority between competing *experiments* is an experiment-phase concern, not a group property.

### Terms: who joined when

`pocore__person__group__term` has one row per person x group x term: each unbroken stretch of month-ends
a person spent in a group (`joined_month_end`, `left_month_end` null while still in, `term_number` 2 after
leaving and coming back). Month-end precision. `is_joined_before_data` marks people already in the group at
the engine's first month-end (real start unknown).

### How a rule works

A rule is a SQL `WHERE` condition over `pode_ftr__donor_snapshot` columns. The engine compiles every group, standard and custom, into one model:

```sql
-- pode_seg__membership (compiled)
select 'cust_lapsed_mid_value_v1' as group_id, 'custom' as group_source, donor_id, snapshot_date
from {{ ref('pode_ftr__donor_snapshot') }}
where (lifecycle_stage = 'lapsed' and net_giving_lifetime >= 100)   -- rule, always wrapped in brackets
  and donor_type = 'individual' and not is_deceased                 -- default filter, added automatically
union all
...
```

- **Grain:** `group_id × donor_id × snapshot_date`. Baselines, power and (later) experiment balance checks all read from this model.
- The query reads only `pode_ftr__donor_snapshot`, so a rule that references any other column fails at compile time. That is how "features only" is enforced.
- The brackets stop an `or` in a rule from escaping the default filter.
- Rules are raw SQL. That's fine while only we write them; a client-facing editor would need validation first (out of scope).

### Group profile (sign-off)

Before a group is used for planning or an experiment, a **group profile** is reviewed with the client: size, lifecycle mix, giving bands, region. It catches rules that compile but select the wrong people. The usual causes are nulls (`region != 'ON'` drops donors with no region), `>` vs `>=`, or a different idea of what "lapsed" means. This is the group equivalent of the reconciliation sign-off.

### Engine version pinning

A rule's text can stay the same while its meaning changes, if an engine release changes how a feature is computed. Therefore:
- Clients pin an engine version.
- Any change to a feature's calculation is a **breaking (major) release**.
- Experiments record the engine version they launched on.

---

## 6. Canonical contract (v0)

### 6.1 `donors`

| column | type | required | constraints / tests | used by |
|---|---|---|---|---|
| `donor_id` | string | yes | not_null, unique | everything |
| `created_at` | date | yes | not_null; `<= as_of` (warn) | when a prospect exists; `prospect` stage |
| `donor_type` | string | yes | accepted: `individual`, `organization` | default group filter; reconciliation breakdown |
| `is_deceased` | boolean | yes | not_null | default group filter (never in a treatment list) |
| `region` | string | nullable | — | feature `region` |
| `acquisition_channel` | string | nullable | — | feature `acquisition_channel` |
| `acquisition_theme` | string | nullable | — | feature `acquisition_theme` |

`donors` includes contacts with zero gifts (prospects). `created_at` is required so that a prospect never appears in snapshots dated before they existed.

**Do not add** to `donors` any client field that changes *because of* giving, such as donor status, major-donor flag or lifecycle stage (see D7). The engine derives those from `gifts`.

### 6.2 `gifts`

| column | type | required | constraints / tests | used by |
|---|---|---|---|---|
| `gift_id` | string | yes | not_null, unique | tests |
| `donor_id` | string | yes | not_null, relationships → `donors` | everything |
| `gift_date` | date | yes | not_null; `<= as_of` (warn); **freshness:** warn if `max(gift_date)` is more than `freshness_warn_days` (default 7) before `as_of` | features, KPIs |
| `amount` | numeric | yes | not_null; refunds negative, others positive | giving features |
| `gift_type` | string | yes | accepted: `one_time`, `recurring` | qualifying-gift rule, `is_recurring_active` |
| `recurring_schedule_id` | string | conditional | not_null when `gift_type = 'recurring'` | qualifying-gift rule |
| `is_refund` | boolean | yes | `is_refund ⇒ amount < 0` | netting |
| `gift_category` | string | yes | accepted: `cash`, `pledge_payment`, `matching`, `daf`, `grant`, `bequest`, `in_kind`, `other` | default eligibility rule; reconciliation; cross-client benchmarks |
| `is_kpi_eligible` | boolean | yes | not_null | features and KPIs use only eligible gifts |
| `exclusion_reason` | string | conditional | null ⇔ `is_kpi_eligible`; free text, e.g. `capital_campaign`, `event_fmv` | reconciliation breakdown |

**Conform labels; it never drops revenue.**
- Every hard-credit revenue row goes into `gifts`.
- Soft credits are the one exception: they aren't revenue rows, and including them would double-count.
- Client-specific rules ("exclude the capital campaign", "event tickets above fair market value only") set `is_kpi_eligible = false` with an `exclusion_reason`. They never delete the row.

The engine ships the default as a macro, which conform calls and extends:

```sql
{{ po_donor_engine.pode_default_kpi_eligible('gift_category') }}   -- cash, pledge_payment, daf
    and campaign_code != 'CAPITAL-2026'                        -- client rule
    as is_kpi_eligible
```

`is_kpi_eligible` is client-specific by design. Cross-client benchmarks recompute eligibility from `gift_category` with the default rule and ignore the flag.

**Unlinked recurring payments (known gap, partly covered).** If a recurring payment arrives without its `recurring_schedule_id`, conform may label it `one_time`. No contract rule is broken, but the routine payment then counts as "gave again" and inflates the `gave` KPI. Three layers of defence:

1. **Conform guidance:** derive `gift_type` from the most reliable signal the CRM has (in NPSP, the recurring-donation lookup *and* the payment or record type), not from schedule-id presence alone. Where two signals exist, add a client-side test comparing them.
2. **Engine test `pode_suspected_unlinked_recurring` (severity `warn`).** It flags non-refund `one_time` gifts that look recurring:
   - **Partial pattern:** same donor and amount as one of that donor's recurring gifts, 25–35 days apart.
   - **Full pattern:** 3+ `one_time` gifts of the identical amount at 25–35 day intervals.

   It's `warn` because some genuine donors give the same one-time amount monthly. The warning prompts a review; it doesn't block.
3. **Reconciliation:** recurring share by month (§6.4). A sudden drop signals that schedule linking broke in the CRM.

Not caught: unlinked payments with irregular amounts, or non-monthly (quarterly/annual) schedules. Accepted.

### 6.3 Optional inputs (preview)

Optional inputs never change required columns or outputs. When one is present, a feature gets more accurate or a KPI becomes available.

**`recurring_schedules`** (enabled with `recurring_schedules_model`)

| column | type | required | constraints / tests |
|---|---|---|---|
| `recurring_schedule_id` | string | yes | not_null, unique; every `gifts.recurring_schedule_id` must match one |
| `donor_id` | string | yes | relationships → `donors` |
| `start_date` | date | yes | not_null |
| `cancel_date` | date | nullable | null = still active; `>= start_date` |
| `amount`, `frequency` | numeric, string | yes | for later upgrade and churn KPIs |

A table with only a current status (no dates) **does not qualify**. Applying today's status to past snapshots leaks the future (D7), which is worse than the heuristic.

**`donor_attribute_history`** (future): slowly changing dimension (SCD Type 2) history (`donor_id`, `attribute`, `value`, `valid_from`, `valid_to`). When present, attributes like `region` use the value that was valid on each `snapshot_date`. When absent, the current value is used.

### 6.4 Reconciliation and project health (engine-provided, human sign-off)

Two serving tables (in `pode_srv`, D13: client and consultant both read them):

- **`pode_srv__reconciliation`**: one row per month × `gift_category` × `donor_type` × eligibility / `exclusion_reason` × `gift_type` × refund × `is_after_as_of`; `gifts` and `net_amount`. Every canonical gift counted once, nothing dropped. Additive, so any grouping is correct: "$4.2M = $3.9M eligible + $180K capital campaign + $120K event fair market value", or recurring share by month. No distinct-donor counts (not additive).
- **`pode_srv__project_health`**: one row per check (`finance_match`: one per year), `value` vs `threshold`, `status` ok / warn / info, plus run context (`as_of`, fiscal year start, modules on). Covers what is *allowed but needs a human*; the dbt tests already stop the build on broken data and aren't repeated.

| check | warns when |
|---|---|
| `data_freshness` | latest gift > 45 days before `as_of` |
| `gifts_after_as_of` | info: count (ignored by every metric) |
| `months_without_gifts` | any month in the lookback, from the first gift on, has no gifts |
| `recurring_share_drop` | latest complete month's recurring share < half the prior 12 months' |
| `suspected_unlinked_recurring` | any (same logic as the warn test, shared macro) |
| `eligible_share_12m`, `active_donors_12m`, `donors_total`, `gifts_total` | info |
| `empty_groups` | any group has no donors at the latest month-end |
| `finance_match` (per year) | engine net revenue (all gifts) differs from finance by more than `finance_tolerance_pct` (default 1) |

**Finance totals (optional input):** the client points `finance_totals_model` at a model or seed with `(giving_year, finance_revenue)`, the finance-reported (usually audited) revenue. Not set: one `finance_match` row says "not supplied". **Phase 1 is finished when `finance_match` is ok for the agreed years**, not when the tests pass; when it warns, `pode_srv__reconciliation` shows where the gap is.

Thresholds are fixed numbers until a client needs different ones. The check list grows only when a real conform surprises us. Data-quality judgments (are the regions right?) belong in the group profile review (§5a), not here.

### 6.5 Extra (client-chosen) columns: `attr_*`

Any conform model can carry extra columns beyond the contract. The client lists which ones to bring through, per input:

```yaml
vars:
  po_donor_engine:
    donors_extra_columns: [is_board_member, wealth_rating, volunteer_status]
    gifts_extra_columns:  [campaign_code, payment_method]
```

- **Companion models, not the contracted ones.** The enforced contracts need a fixed column list, so extras go to `pode_can__donor_attributes` (`donor_id` + `attr_*`) and `pode_can__gift_attributes` (`gift_id` + `attr_*`), both built from the **same** conform models. There is nothing extra for the client to build. Values pass through as-is (no casting).
- **Donor attributes join into `pode_ftr__donor_snapshot`** as `attr_<name>` columns, so they work in group rules (`rule: "attr_is_board_member"`) and in `baseline_breakdowns` (`[acquisition_channel, attr_wealth_rating]`).
- **Gift attributes** are available at gift level on day one. Donor-level features derived from them (e.g. "gave to the spring appeal") are a later step.
- **D7 applies:** current values only, so donor attributes must not change *because of* giving (fine: board member, volunteer, screened wealth rating; never: donor status, major-donor flags). Time-aware attributes are the upgrade path (§6.3).
- Empty lists (the default) change nothing.

### 6.6 Tiers: what a client must supply, and what's optional

| tier | what's missing | engine behaviour |
|---|---|---|
| Required contract | `donors` or `gifts` can't be produced | No engine. Closing this gap *is* the conform work. |
| Optional column | e.g. `acquisition_cost` (via `donors_extra_columns`) | Everything runs; dependent columns are null (CPA, LTV:CPA). |
| Optional module | a whole area is absent or untrustworthy (e.g. no recurring giving) | Switch the module off; its models aren't built, so its srv tables don't exist (better than empty tables a BI tool or LLM reads as zeros). |

Client switch: `vars: {po_donor_engine: {modules: {sustainers: false}}}`. Modules default to on; an unknown module name is an error. Engine models opt in with `{{ config(enabled=pode_module_enabled('<module>')) }}`.

| module | models | needs |
|---|---|---|
| core (always on) | can, snapshot, outcomes, groups, baselines, power, summary, trend, roster, test planning, movement, cohorts | donors + gifts |
| `sustainers` | `pode_mtr__sustainer_month`, `pode_srv__sustainer_ltv` | recurring gifts (cost optional) |
| future | experiments, upgrades, contact guardrails | `experiments` + `experiment_assignments` (§10), `recurring_schedules`, contactability (§6.3) |

- **Engine rule:** nothing outside a module may `ref()` a model inside it (dbt fails at parse time when the module is off).
- **Switching a module off later doesn't drop its old tables:** dbt never drops models it no longer builds. Drop them by hand (or in the client's deploy script) so stale tables don't linger in `pode_srv`.
- Tested: the DuckDB integration project builds with every module on, and with `--vars '{modules: {sustainers: false}}'`.

---

## 7. Decisions (proposed — confirm or change)

- **D1 Gift definition: conform labels, the engine uses the labels.**
  - `gifts` contains all hard-credit revenue, each row labelled with a `gift_category`. Pledges themselves are not gifts; their payments are (`pledge_payment`).
  - Soft credits are excluded entirely.
  - Matching gifts stay with the matching organization, not the employee.
  - DAF gifts are attributed to the recommending individual, not the fund.
  - Default KPI eligibility: `cash`, `pledge_payment`, `daf`. Client exceptions go through `is_kpi_eligible` / `exclusion_reason` (see §6.2).
- **D2 Donor identity:** `donor_id` = the unit you communicate with, so that randomization never splits a household across arms (contamination).
  - Default is the **household** for clients that use direct mail; contacts are acceptable for email-only programs.
  - One grain per client, chosen in conform, documented, and not changed.
  - The engine doesn't know which grain it is.
- **D3 Time:** `as_of` is a required var, and the engine never calls `current_date()`. Same inputs and same `as_of` give the same outputs.
- **D4 Refunds:** separate rows with negative amount, dated at the refund date, with `is_refund = true`. Accepted consequence: a gift inside a KPI window that is refunded after the window still counts as "gave."
- **D5 Currency and timezone:**
  - A single reporting currency; multi-currency is out of scope.
  - `gift_date` is the client's **local** date. Conform converts timestamps before truncating, so a gift at 11pm Pacific on Dec 31 stays in the right fiscal year and year-end campaign.
- **D6 Lifecycle thresholds: fixed in the engine, not overridable per client.** Standard groups are built on `lifecycle_stage`, so they must mean the same thing everywhere. A client who wants different thresholds writes a custom group on the raw features (e.g. `days_since_last_gift between 548 and 1095`).
  - **Exactly one stage per donor.** Rules are checked in this order, and the first match wins. Gifts used: eligible, positive (non-refund), `gift_date <= snapshot_date`.

    | order | stage | rule (days = `snapshot_date − date`) |
    |---|---|---|
    | 1 | `sustainer` | `is_recurring_active` |
    | 2 | `new` | first gift ≤ 90 days ago |
    | 3 | `active` | last gift ≤ 365 days ago |
    | 4 | `lapsed` | last gift 366–730 days ago |
    | 5 | `deep_lapsed` | last gift > 730 days ago |
    | 6 | `prospect` | `created_at <= snapshot_date`, no gifts |

  - **Days, not months:** exact and the same on every warehouse. Month, year and fiscal-year *features* are derived from the stored dates (calendar-year features on day one; months and fiscal year later, via a cross-warehouse macro).
  - **Combinations use flags, not stages:** `is_new_donor`, `is_recurring_active`, `is_reactivated` (§5).
  - **Refunds and recency (option a):** recency ignores refunds, so a donor whose only gift was refunded stays `new`/`active`. The count of affected donors appears in the group profile. Upgrade path: an optional `original_gift_id` on refund rows.
  - **Exact edges:** 365 days = `active`, 366 = `lapsed`; 730 = `lapsed`, 731 = `deep_lapsed`. Tests check these dates.
  - **Changing thresholds is a breaking (major) engine release.** Adding features or flags is not.
- **D7 Current-value attributes:**
  - Allowed without history when they change rarely and not because of giving (region, acquisition channel or theme). The small leakage is documented.
  - Never accepted when they change *because of* giving (status, major-donor flags, client lifecycle fields).
  - Upgrade path: the optional `donor_attribute_history` input (§6.3). This is non-breaking.
  - Recommended for every client from day one: a dbt snapshot of the donors conform model. History can only be collected going forward, so it's cheap insurance even before the engine uses it.
- **D8 Group config:** custom group rules live in YAML (vars), not seeds. YAML is read at compile time with no warehouse round-trip, and it is versioned in git. Details are in §5a.
- **D9 The engine is always idempotent.** Same inputs and same `as_of` give the same outputs, and any model can be fully rebuilt at any time. Real-world events (experiment launches, sends) come in as **inputs**, never as stateful models.
- **D10 Warehouses:**
  - **BigQuery** (demo/dev) and **DuckDB/MotherDuck** are first-class from day one. `integration_tests/` run on local DuckDB: fast, free, no credentials, and it keeps the SQL portable.
  - **Snowflake** is added when the first Snowflake client arrives.
  - Use dbt's cross-database macros (`dbt.dateadd`, `dbt.datediff`, `dbt.type_*`). Gaps get engine macros using `adapter.dispatch`: hashing (for an optional suggested split, §10), month differences.
  - **Passing on DuckDB is not proof of portability.** DuckDB accepts SQL that BigQuery rejects, so every engine change is also built on BigQuery before release. Known traps (all hit during step C):
    1. Duplicate column names, e.g. `select x.*, y.col` where `x.*` already has `col` (DuckDB silently renames).
    2. `GROUP BY` on a literal (`group by 'all'`): just omit the literal.
    3. Parameterized types in `CAST` (`cast(x as numeric(18,2))`): use `pode_type_money()`.
    4. A CTE with the same name as its column (`select current_year from current_year` is a struct on BigQuery).
    5. `dbt.generate_series` yields decimals on BigQuery: cast to `dbt.type_int()` when used as a year or count.
    6. Jinja: a SQL `--` comment right before a `{%-` block can swallow the following SQL (whitespace trimming).
    7. Doubled-quote escapes in string literals (`'month''s'`): BigQuery reads two adjacent literals. Reword fixed text; quote config values (e.g. group labels) with `pode_string_literal()`.
    8. `least()` / `greatest()`: NULL handling differs (BigQuery, Snowflake and Databricks return NULL if any argument is NULL; Postgres, Redshift and DuckDB ignore NULLs), and SQL Server only has them from 2022. Use `pocore_helpers__clamp(expr, low, high)` (a plain `case`). Found in v0.2.0: `greatest(NULL, 0)` in group power returned 0 on DuckDB and NULL on BigQuery.
- **D11 Z-values for power** come from a lookup table in the engine macro `pode_z()` (probability → z). SQL has no inverse-normal function and dbt Jinja has no `math` module. An α or power value not in the table fails the build clearly; add a row to support it. (Originally specified as a seed; a macro is simpler, with no seed loading or column-type issues.)
- **D12 Versioning (semantic versioning: MAJOR.MINOR.PATCH):**

  | bump | when | examples |
  |---|---|---|
  | MAJOR | existing outputs change meaning or value, or something breaks | threshold change; feature calculated differently; standard group redefined; new **required** contract column; renamed or removed output column; **any bug fix that changes output numbers** |
  | MINOR | additions only; existing numbers unchanged | new feature, flag, KPI, standard group, optional input, serving model |
  | PATCH | no output value changes | docs, performance, crash fixes, a new warehouse's dispatch macro |

  - Clients pin an **exact tag** in `packages.yml` (`revision: v1.3.0`), never a branch or a range. Upgrades are deliberate.
  - `CHANGELOG.md` has a "numbers that will change" section on every MAJOR release.
  - The contract is versioned with the engine, not separately.
  - **`0.x` until the first real client;** breaking changes are free before then. **`1.0.0` = the first client's phase 1 starts.**
- **D13 Model naming and Lightdash exposure:**

  **Format:** `pode_<layer>__<name>`. `pode_` (po donor engine) namespaces every engine model and macro, so they can't collide with client models. Layer codes are all 3 letters, so names line up.

  | layer code | layer | models | in Lightdash? |
  |---|---|---|---|
  | `can` | canonical: checks inputs that conform has already standardized (contract, casts, tests) | `pode_can__donors`, `pode_can__gifts` | no |
  | `ftr` | features | `pode_ftr__donor_snapshot`, `pode_ftr__kpi_outcomes` | `pode_ftr__donor_snapshot` for exploration |
  | `seg` | groups | `pode_seg__membership`, `pode_seg__profile` | `pode_seg__profile` |
  | `mtr` | internal metrics: full calculation tables (all KPIs, windows, slices, lookbacks, holdouts) | `pode_mtr__group_baselines`, `pode_mtr__group_power` | no |
  | `srv` | **serving: the only exposed layer, in its own schema (`pode_srv`)** | `pode_srv__group_summary`, `pode_srv__group_summary_by_slice`, `pode_srv__group_trend`, `pode_srv__test_planning`, `pode_srv__group_roster` | yes, all |

  **Date naming (one term, one meaning):**

  | name | means |
  |---|---|
  | `as_of` (var) | the pipeline cutoff passed in (D3) |
  | `snapshot_date` | the month-end a row describes; the latest one is the last month-end on or before `as_of` |
  | `anchor_date` | a snapshot date used as the start of a KPI window (outcomes, internal metrics) |
  | `donors_at_snapshot` | donors in the group on `snapshot_date` |
  | `outcome_window_days` | the follow-up period a KPI is measured over: "did they give within N days after the snapshot/anchor date?" Each group has a primary one (new 90, lapsed 180, others 365; custom via `primary_window_days`) |

  **Serving rule:** every `srv` row is a final answer at its stated grain, and the table's obvious grouping is correct. Each description starts with "One row per …". All logic lives in SQL; BI metadata is labels only (physical-first: works the same in any BI tool or LLM). **Client workflow:** conform to the contract → run the engine → point BI tools and LLMs at the `pode_srv` schema only.
  | `exp` / `sim` | future: experiments / demo simulation | — | — |

  - Package name stays `po_donor_engine` (descriptive in `packages.yml`). Macros are `pode_*` (e.g. `pode_default_kpi_eligible`).
  - Lightdash shows friendly labels via YAML, so the prefixes only need to be clear to whoever maintains the code.
  - Everything without Lightdash metadata stays hidden.
  - **No `config()` blocks in engine model files** for schema, alias or materialization. In-file `config()` overrides the client's `dbt_project.yml`, which would take control away from clients. Set these in the engine's `dbt_project.yml`, where clients can override them.
  - **Conform vs canonical:** conform (client side) *does* the standardizing; canonical (engine side) only *checks* the result and rejects anything that doesn't fit.---

## 8. Open questions

### Resolved

1. **Zero-gift contacts:** included as prospects. `created_at` is required again, and a `prospect` stage is added.
2. **Qualifying gift:** one-time gifts plus the first payment of a new schedule. Upgrades don't count on day one.
3. **Revenue per donor:** added as a capped-mean KPI. The serving shape is generalized to `metric_type` / `value` / `variance`.
4. **Group config:** YAML (D8).
5. **Statistical settings:** defaults α = 0.05 two-sided, power = 0.8, holdout grid 10/15/20/30. Vars for planning; the values actually used are pre-registered in the client's `experiments` input (§10).
6. **Baseline:** trailing 12 complete anchors by default, pooled (weighted by n). It's a lever, and the power table also shows 24 months for comparison (§3.2).
7. **Current-value attributes:** accept the small error for region and acquisition; giving-driven fields are banned. SCD history is a future optional input (D7, §6.3).
8. **Sustainer detection:** the gift heuristic by default. The optional `recurring_schedules` input replaces it when the client has a dated schedule table, and it's required for sustainer KPIs (§5, §6.3).

### Still open

- ~~**Client-specific features in group rules.**~~ **Resolved (§6.5):** extra columns from any conform model are passed through as `attr_*`. Donor attributes become snapshot columns usable in group rules and breakdowns. Still open: turning **gift** attributes (campaign, appeal, payment method) into donor-level features, and time-aware (`valid_from`/`valid_to`) attributes.

---

## 9. Out of scope for day one

- Assignment, treatment lists, simulation (sim) layer, experiment results, compliance checks.
- Optional inputs: `recurring_schedules`, `contactability_events`, `sends`.
- Identity resolution beyond the client's chosen `donor_id`.
- Multi-currency, source-system conform templates (e.g. NPSP package).
- Detailed Lightdash YAML (metric definitions come after the serving models are stable).

---

## 10. Future work: experiments (assignment is an INPUT)

**Decided 2026-11-18, replacing the earlier "launch record" design.** The engine does not run tests and does not create or store who is in which group. People run tests in their own tools (CRM campaign members, an email platform's holdout, a mail house's split), and the assignment comes back to the engine as an optional **contract input**. The engine stays a pure function of its inputs (D9), with nothing write-once to protect.

- **Inputs** (optional, unlock the experiments module):
  - `experiment_assignments`: `experiment_id`, `person_id`, `arm` (`treatment` / `holdout`, or several arms), `assigned_date`. It records intended treatment, not receipt; contact history covers receipt.
  - `experiments`: one row per experiment with what was decided **before** launch (pre-registration): name, primary KPI, outcome window, intended holdout %, α / power. Results always use these values; changing them after seeing data means a new experiment, never a re-read.
- **Readout:** the same forward outcome windows the engine already computes, anchored on `assigned_date` instead of a month-end (DESIGN §9.3, §9.6).
- **The engine checks the input instead of trusting it** (health checks plus a "trustworthy?" flag on the readout):
  - group sizes vs the intended holdout % (sample ratio mismatch);
  - balance at launch: the groups compared on giving history as of `assigned_date`, using `foundation__person__month` (a hand-picked holdout shows up here);
  - no person in two active experiments; every `person_id` exists;
  - contamination, once contact history exists: were holdout people contacted anyway?
- **Test planning is unchanged:** detectable lift, holdout options and readable-by dates are pure analysis the client uses *before* setting a test up.
- **Optional helper:** a deterministic suggested split (hash of `person_id` + `experiment_id`) clients can export. A pure function, so idempotent; the input is still the record of who was actually assigned.
- **Open:** person merges after launch need a merge map (old → surviving `person_id`) as an input.
