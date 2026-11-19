# v0.2.0 / v0.3.0 design: `po_core`, foundation and certified

**Status:** draft for review (rewritten 2026-11-18). Nothing here is built yet. Once it is accepted, it replaces the matching parts of `SPEC.md`: §3 (serving outputs), D13 (naming), and the layer table.

**How to read this:**
- §1–§2: the idea and the structure.
- §3–§5: the rules.
- §6: what v0.2.0 actually builds.
- §7–§8: how clients and the internal layers work.
- §9: the future direction (designed, **not** built).
- §10–§13: work list, risks, use-case gaps, open decisions.

---

## 1. The idea

**Contract in, contract out.** The client supplies standard inputs (`people`, `gifts`). The engine returns two kinds of reliable output:

| tier | reliable? | for | character |
|---|---|---|---|
| **Foundation** | yes: tested, grain-specific, maintained by us | advanced analysts | **flexible.** The facts and standard definitions, ready for any further modelling (Kimball or otherwise). |
| **Certified** | yes: built **only from foundation** | business users, dashboards | **opinionated.** Our view of what to look at: segments, baselines, test planning, movement, cohorts. |
| **Internal** | — | us | the machinery: Jinja, statistics, advanced patterns. Clients don't touch it. |

**The iterative dynamic.** Certified is our *opinion*. A client who disagrees, or needs something else, builds on foundation in their own project. If their version turns out to be a better opinion, we add it to certified or replace ours. This works because every opinion, ours and theirs, starts from the same tested facts.

**Foundation is not opinion-free.** Stage thresholds, eligible gifts and reactivation are *definitional* opinions. So foundation always exposes **the ingredients next to each derived value** (`days_since_last_gift`, `gift_count_12m`… next to `lifecycle_stage`), and the **forward outcomes** that baselines are built from. Anyone can rebuild our opinions from the same rows.

**Guiding principle for certified:** the engine absorbs the complexity so the output doesn't have to. A certified table is about one thing, optionally over time, optionally split one way, and its name says so.

---

## 2. Names, tiers and schemas

**Package:** `po_core`. **Prefix:** `pocore_`. The prefix is longer than `poc_`, which reads as "proof of concept", and more distinctive than `core_`, which would risk colliding with clients' own models. The clean release repo becomes `po-core`.

| tier | name pattern | folder | schema |
|---|---|---|---|
| canonical (internal) | `pocore_can__*` | `can/` | `pocore_internal` |
| features (internal) | `pocore_ftr__*` | `ftr/` | `pocore_internal` |
| segments (internal) | `pocore_seg__*` | `seg/` | `pocore_internal` |
| metrics (internal) | `pocore_mtr__*` | `mtr/` | `pocore_internal` |
| **foundation** | `pocore_foundation__<grain>` | `foundation/` | `pocore_foundation` |
| **certified** | `pocore__<grain>` | `certified/` | `pocore` |
| **admin** | `pocore_admin__*` | `admin/` | `pocore` |

```
inputs → can → ftr → seg ──→ FOUNDATION ──→ CERTIFIED
                      │          ▲              ▲
                      └→ mtr ────┼──────────────┘   (statistics: built from foundation,
                                 │                   feed certified)
                         (internal machinery)
```

Concretely:
- **Foundation** is assembled from the internal fact-building layers (`can`, `ftr`, `seg`).
- **The statistics layer (`mtr`)** reads *foundation*, not the raw internals, so every certified number traces back to foundation rows.
- **Certified** reads foundation and `mtr` only.

- **A name with no layer code is certified**: the shortest names go to the tables most people read.
- **Public tiers use words, internal tiers use 3-letter codes.**
- **No dbt aliases:** model name = warehouse table name = BI name.
- **A business-user BI connection needs only `pocore`.** Advanced analysts also get `pocore_foundation`.
- **Internals are visible but unsupported.** Referencing them is "at your own risk", and they may change in any release. Convention first; enforce with dbt `access: private` only if clients start depending on internals. *(Verify how dbt `access` behaves across packages before relying on it.)*

---

## 3. Contract in

### 3.1 Renames
| today | v0.2.0 |
|---|---|
| input `donors` | `people` |
| `donor_id` | `person_id` |
| `donor_type` (`individual` / `organization`) | `person_type` (same values) |
| var `donors_model` | `people_model` |
| var `donors_extra_columns` | `people_extra_columns` |

**Why `person`:** the contract already includes people with zero gifts (prospects), and non-donor sources will grow that group. "Donor" becomes a state (a stage or flag), not the entity. Organisations remain `person_type = 'organization'`.

### 3.2 Three scope statements
1. **Who a person is:** anyone the organisation knows, with or without gifts. `person_id` is whatever unit the conform produces (an individual, or a household). D2 still applies: randomisation never splits the unit.
2. **What a gift is:** one row per gift or refund. **No soft credits.** Every gift is credited to exactly one person, or "every gift counted once" breaks. Gift splits across funds stay out of `gifts`.
3. **What one run covers:** one reporting entity. **`org_unit`** is reserved as an optional **partition key**: it leads every table's key when present and does not count as a grain level.

### 3.3 The contract drives what gets built (modules)

The client never picks modules. They deliver contract inputs, and the engine builds whatever those inputs support. A client with only `people` and `gifts` gets a complete, working set of outputs. Each additional input unlocks more.

| contract level | example | what it switches |
|---|---|---|
| required inputs | `people`, `gifts` | the core: always on; the build fails without them |
| optional inputs | `recurring_schedules`, `finance_totals`, future `activities`, experiment inputs | **whole modules**: their tables exist only when the input is configured (`*_model` var set) |
| optional columns on an input | `acquisition_cost` on `people`, future `cancel_reason` on `recurring_schedules` | **columns**: filled when supplied, NULL otherwise |

**The contract documents what each optional input unlocks**, so it doubles as the phasing menu ("supply this, get that"). Example:

| optional input / column | unlocks |
|---|---|
| `recurring_schedules` | accurate recurring status (replaces the heuristic), sustainer KPIs; future `foundation__recurring_plan` and plan-based lapse features |
| `finance_totals` | finance reconciliation checks |
| `people.acquisition_cost` | CPA and LTV:CPA columns |
| future `activities` | activity features, contact health checks (were holdout people contacted?) |

**Mechanics:**
- **`enabled` is the gate, not tags.** Module models start with `config(enabled = pocore_module_enabled('<module>'))`. A disabled model doesn't exist in the project, and dbt refuses at compile time if an enabled model depends on it. The client runs a plain `dbt build`. Tags (`tag:pocore_<module>`) are labels for selection, docs and BI, never the gate: a tag-excluded model still exists, and anything referencing it fails at run time.
- **`pocore_module_enabled()` reads the contract:** a module is on when its input var is configured. This extends today's `modules:` var and `pode_module_enabled()`.
- **Opinion modules** are the only explicit switches: modules that need no new data but may not be relevant (e.g. `sustainers: false` for a client without a monthly-giving programme). They default to on when the data supports them.
- **Tables disappear, columns don't.** When a module is off, its whole tables are disabled, but its columns on shared tables stay as NULL (rule 6). Dashboards and custom models never break when a module is turned on or off.
- **Configured ≠ good.** Supplying an input switches its module on. Health checks report fill rates per input and column, so a thin input is visible rather than silently producing weak numbers. Contract tests stay the hard gate.

This replaces and extends SPEC §6.6 (tiers) and the `modules` var.

---

## 4. Entity registry

Each word in a table name maps to fixed key columns.

| word | key columns | kind |
|---|---|---|
| `person` | `person_id` | primary |
| `segment` | `segment_id` | primary |
| `gift` | `gift_id` | primary |
| `cohort` | `cohort_type`, `cohort_year` | primary |
| `year` | `fiscal_year` | time |
| `month` | `month_end_date` | time |
| `age` | `age_months` (cohorts), `age_days` (future campaign curves) | time since a start |
| `breakdown` | `breakdown_by`, `breakdown_value` | split |
| `test_option` | `outcome_window_days`, `holdout_pct` | setting |
| `kpi` | `kpi_id` | setting (custom KPIs only) |
| *future:* `activity`, `recurring_plan`, `experiment`, `experiment_arm`, `campaign`, `channel` | see §9 | |

**Compound words** are allowed only when their columns can't be separated. Precedent: entities in feature stores and semantic layers, and hubs and links in Data Vault.

---

## 5. Rules

### 5.1 Both public tiers
1. **The name lists the grain.** Every key column is implied by a word in the name: no hidden keys.
2. **One table per grain per tier.** A new number at an existing grain is a new column.
3. **The grain is tested.** The description starts with "One row per …", and a uniqueness test covers the key columns.
4. **Repeat attributes, never measures.** A table may repeat descriptive attributes of a coarser entity (region, channel, stage), because people group by them. It never repeats measures of a coarser entity (e.g. `lifetime_giving` on a gift row), because people sum them.
5. **Contracted columns.** Adding a column is MINOR. Renaming, removing or changing the grain is MAJOR.
6. **Standard columns are identical for every client.** Client-defined columns are allowed only on **person-grain** tables and only with a `cust_` or `attr_` prefix. Lists that generate columns (KPI windows, stage horizons) are fixed by the engine.

### 5.2 Foundation
7. **Facts and definitions, not answers.** Atomic or periodic-snapshot grains; ingredients next to every derived value; forward outcomes included.
8. **May be large and technical.** It's documented for analysts who know dbt and SQL.
9. **Columns of different kinds are labelled.** Running totals and rolling windows (`net_giving_12m` on a monthly row) are *not* summable across rows, and the column descriptions say so.

### 5.3 Certified
10. **At most three grain levels:** one primary, an optional time, an optional split or setting. Bridges join two primaries.
11. **Safe to drag and drop:** summable columns are summable, and every rate ships with its numerator and denominator.
12. **Built only from foundation** (directly, or through `mtr` statistics computed from foundation).
13. **One split level at most.** For several splits:
    - on additive numbers: use foundation person or gift tables and split in BI or SQL;
    - on engine statistics: a configured **crossed breakdown** (`region × channel`) counts as one split;
    - custom KPIs go in one long table, `pocore__segment__kpi`.

### 5.4 Both
14. **Build only what's used.** The registry is a vocabulary, not a promise to build every grain.
15. **New primary entities need a decision record** in the SPEC.

**Kimball mapping** (useful for handover):

| table has… | fact-table type | e.g. |
|---|---|---|
| no time word | current snapshot or dimension | `foundation__person`, `pocore__segment` |
| `__month` / `__year` | periodic snapshot | `foundation__person__month`, `pocore__person__year` |
| `__age` | cohort / accumulating | `pocore__cohort__age` |
| `gift` | transaction fact | `foundation__gift` |

---

## 6. What v0.2.0 builds

Mostly the existing engine, reorganised into the two public tiers, with **one genuinely new table** (`foundation__gift`) and the old serving tables rebuilt as cuts of foundation.

### 6.1 Foundation (4 tables)
| table | one row per | holds | comes from |
|---|---|---|---|
| `pocore_foundation__person` | person | contract attributes, `attr_*`, current state (latest snapshot values: stage, days since last gift, 12-month and lifetime giving, recurring status) | `can__people` + latest snapshot |
| `pocore_foundation__gift` | gift (incl. refunds) | contract columns, plus `is_kpi_eligible`, `is_qualifying` (counts as "gave"), `is_recurring_payment`, `is_first_gift`, `is_reactivation_gift`, gift number for the person, days since previous gift, **stage at time of gift**, repeated person attributes | `can__gifts` + new enrichment (logic exists today inside `kpi_outcomes` and the snapshot) |
| `pocore_foundation__person__month` | person × month-end | **ingredients** (all snapshot features) and **derived** values (stage, flags), plus **forward outcomes** (`gave_90d`, `revenue_90d`, `retained_180d`… with `is_complete_*`) | today's `ftr__donor_snapshot` + `ftr__kpi_outcomes`, merged (same grain) |
| `pocore_foundation__person__segment__month` | person × segment × month-end | membership history | today's `seg__membership` |

That gives advanced analysts:
- who people are (`__person`);
- what they did (`__gift`);
- what was true about them at each month-end and what happened next (`__person__month`);
- which groups they were in (`__person__segment__month`).

That's enough to rebuild any certified table, or to disagree with it.

### 6.2 Certified (10 tables + 2 admin)

**Changed during the build:** the plan merged donor cohorts and sustainer LTV into one `__cohort__age`. They are different grains: first-gift cohorts follow *calendar fiscal years*, sustainer cohorts follow *months since starting*. One table would need an `age` column meaning different things on different rows, so they are `pocore__cohort__year` and `pocore__cohort__age` (+ `__breakdown` for the per-channel CPA/LTV). The old "all start years mixed" sustainer rows are dropped: pool cohorts from the counts instead. Sustainer horizons now only set how many months get a row, never which columns exist.
| table | one row per | holds | replaces |
|---|---|---|---|
| `pocore__person__segment` | person × segment (latest) | the roster: membership, entry date, repeated person attributes for display | `segment_roster` |
| `pocore__person__year` | person × fiscal year | that year's giving (summable), movement status, `stage`, `stage_1y_ago`…`stage_3y_ago` | new; **replaces `stage_transitions`** |
| `pocore__segment` | segment (latest) | size, headline rate, detectable lift, testable?, value per point | `segment_summary` |
| `pocore__segment__month` | segment × month-end | size, entering/leaving, rates with numerators and denominators | `segment_trend` |
| `pocore__segment__breakdown` | segment × breakdown value (latest) | same as `__segment`, split | `segment_summary_by_slice` |
| `pocore__segment__test_option` | segment × window × holdout | the test design menu | `test_planning` |
| `pocore__year` | fiscal year | movement counts, retention, finance totals | `donor_movement` |
| `pocore__cohort__year` | cohort × fiscal year (`cohort_type = 'first_gift'`) | members who gave each year by status, % of cohort, revenue | `donor_cohorts` |
| `pocore__cohort__age` | cohort × month of life (`cohort_type = 'first_recurring'`; sustainers module) | survival, revenue, LTV to date, CPA, LTV:CPA | `sustainer_ltv` (whole cohorts) |
| `pocore__cohort__age__breakdown` | cohort × month of life × breakdown value (acquisition channel) | the same, per channel | `sustainer_ltv` (by channel) |
| `pocore_admin__health` | check | project health, plus new checks that tables agree (below) | `project_health` |
| `pocore_admin__reconciliation` | sign-off totals | every gift once | `reconciliation` |

**No certified `__person`:** the person grain lives in foundation. Business users get people through the roster (`__person__segment`) and `__person__year`. That avoids two tables at the same grain with subtly different columns.

**Stage transitions → `__person__year`:** the Sankey is "count people by `stage_1y_ago` → `stage` for one year", and clicking a flow gives the people behind it.

**New consistency checks** (enforced by tests, reported in health):
- `__year` totals = sums of `__person__year`;
- `foundation__gift` ties exactly to the `gifts` input;
- certified segment sizes = counts in `foundation__person__segment__month`.

### 6.3 Size (500k people)
| table | rows |
|---|---|
| `foundation__person__month` | ~36M, wide. Cluster by `month_end_date`. |
| `foundation__gift` | ~5–10M. Cluster by `gift_date`. |
| `pocore__person__year` | ~5M. Cluster by `fiscal_year`. |
| everything else | small |

---

## 7. Client projects

```
client project
  models/conform/     ← the conform (the work we sell)
  models/custom/      ← their opinions and extensions, client prefix
      ref('pocore__person__year')                    certified
      ref('pocore_foundation__person__month')        foundation (the usual starting point)
      ref('pocore_mtr__segment_power')               ⚠ internal: at your own risk
  dbt_project.yml vars ← custom segments (and later custom features/outcomes, §9)

po_core package       ← never edited per client
```

- **Use as-is:** connect BI to `pocore`.
- **Build on foundation (the normal path for a different opinion):** custom models in the client's project, client prefix. They keep receiving engine upgrades.
- **Anything needing engine statistics for a custom group** (baselines, power) goes through config (custom segments), not custom SQL.
- **If a custom model replaces a certified number, rename it** (`client_retention_rate`), so two definitions never share a name.
- **Promotion:** when a client's opinion proves better, or the same extension is built for 2–3 clients, it moves into certified (or foundation) in the next release.
- **Answering nuanced questions:** standard questions are answered in certified; one-off questions with simple SQL on foundation (or an analyst agent: grain-named tables with "One row per …" descriptions are ideal agent input); repeated questions become certified columns.
- **License:** the repo is public with no LICENSE, which means *all rights reserved*. Decide before the clean `po-core` release.

---

## 8. How the internal layers work (reference)

| layer | question | notes |
|---|---|---|
| `can` | what did the client give us? | thin passthroughs; contract tests |
| `ftr` | what was true about each person at each month-end (**backward**: `gift_date <= snapshot_date`), and what happened after (**forward**: `gift_date > anchor_date` within N days)? | "As of, no peeking": every month-end is replayed as if it were today. Recent anchors with unfinished windows are flagged `is_complete = false`. |
| `seg` | which segment was each person in, each month? | segments are rules over the snapshot columns, so a new segment is config |
| `mtr` | what do groups add up to, and what could a test detect? | the statistics: pooling, seasonality, power. Reads foundation. |

**Feature vs outcome:** "gave in the *last* 90 days" (backward from the row's date) is used to *choose* people. "Gave in the *next* 90 days" (forward from the row's date) is used to *judge* results. Both are usually in the past relative to today.

**Events vs states:** events (gifts, revenue, first gifts) roll up to any period, so use `foundation__gift`. States (stage, active, retained) are measured *at* a date and don't sum, so use snapshots (`__person__month`, `__person__year`, `__segment__month`).

**Counting people vs counting events:** decide what you're counting first.
- Counting people: event conditions become person features.
- Counting gifts: person attributes are repeated on gift rows.

---

## 9. Future direction (designed, not built)

All of this is **additive**: it can arrive later without breaking anything in v0.2.0.

### 9.1 Activities: "did X, did Y, X but not Y"
Gifts, email clicks, event attendance, petitions and calls are **activities at different grains that roll up to a person**.
- **Contract:** an optional `activities` input with one shape: `person_id, activity_type, activity_date, amount, campaign_id, attributes`. New sources become new activity types, not new SQL.
- **Foundation:** `pocore_foundation__activity` (transaction fact).
- **Scale rule:** high-volume activities are **pre-aggregated to person × month × activity type** first. Features are then rolling sums over monthly buckets, so cost grows with people × months, not with activity volume. Windows are month-aligned (3 months ≈ 90 days). Day-precise windows remain for gifts and anchored outcomes.

### 9.2 Features and outcomes as config
The engine's mechanism is **one step**: activity + direction (backward/forward) + window + aggregation (count / sum / exists / min / max / last date) + an optional simple filter (equals, in list, ≥, ≤ on activity columns).
```yaml
custom_features:
  - {name: cust_clicks_90d,        activity: email_click, window_days: 90,  agg: count}
  - {name: cust_gave_spring_2025,  activity: gift, filter: {campaign_id: spring_2025}, window_days: all, agg: exists}
custom_outcomes:
  - {name: cust_clicked_30d,       activity: email_click, window_days: 30,  agg: exists}
```
- **Standard** features and outcomes are defined by the engine, fixed, and the same for every client. **Custom** ones live in client config with a `cust_` prefix.
- Custom features appear on `foundation__person__month` (history) and `foundation__person` (current). Custom outcomes can be a segment's KPI, with statistics in `pocore__segment__kpi`.
- **"X but not Y"** is a segment rule over two features.
- The build fails clearly on an unknown activity type or a reused standard name.

### 9.3 Anchored outcomes: "after X, did Y?"
Outcomes measured from each occurrence of an activity, not from month-ends:
```yaml
anchored_outcomes:
  - name: gave_after_spring_click
    anchor: {activity: email_click, campaign_id: spring_2025}
    outcome: {activity: gift, window_days: 14, agg: sum}
```
That's the same mechanism as experiment launches (which are anchors too).

### 9.4 Deliberately not built: a sequence language
"A, then B within 7 days, then C, excluding D" needs a query language in YAML, and activity × activity joins that get expensive at scale. **Two or more ordered steps are a custom model** in the client project, on foundation tables. Repeated sequences get promoted to a standard anchored outcome.

### 9.5 Future entities
| entity | tables |
|---|---|
| experiments | `pocore__experiment`, `pocore__experiment_arm` (readout), `foundation__person__experiment` (the client's assignment input, conformed and checked; §9.6) |
| campaigns (decision record: attribution) | `pocore__campaign`, `pocore__campaign__age` (`age_days`), `pocore__campaign__breakdown` |
| marketing spend | `pocore__channel`, `pocore__channel__month` |
| recurring plans | `foundation__recurring_plan` (start, stop, reason) |
| contacts / email | an activity type (§9.1), plus a health check: were holdout people contacted? |
| gift splits | an optional allocation input; `pocore__fund__year` |

Use clicks, not opens: Apple Mail Privacy Protection inflates opens.

### 9.6 Experiments: assignment is an input, not something the engine creates

The engine doesn't run tests, people do. So the engine never creates or stores who is in which group (that would be the one stateful, write-once thing in an otherwise idempotent engine). Instead:
- **Optional contract inputs:** `experiment_assignments` (`experiment_id`, `person_id`, `arm`, `assigned_date`) from whatever tool ran the test, and `experiments` (pre-registered KPI, window, intended holdout %, α/power).
- **Readout:** forward outcomes anchored on `assigned_date` (the §9.3 mechanism), compared between arms.
- **Checks, because the input can't be trusted blindly:** group sizes vs intended holdout, balance at launch on giving history (`foundation__person__month` as of `assigned_date`), one active experiment per person, and later contamination (holdout contacted?). Results carry a "trustworthy?" flag.
- **Test planning is unchanged** (pure analysis, used before a test is set up). Optional helper: a deterministic hash-based suggested split clients can export.
- Nothing in v0.2.0 depended on the old write-once design, apart from comments that have been removed.

---

## v0.3.0: populations, configured; exploration on foundation (2026-11-18)

**Boundaries (decided):**
- **dbt first.** The engine produces **foundation** (tested facts, for all exploration) and **certified population summaries**: the standard metric set (size, same-season rate, value per point, detectable lift, monthly trend, test options) for every configured population. Fundraisers think in populations of people; certified answers "how is each population doing, and is it worth testing?".
- **Configuration is done by us** (SQL rules in config; no friendly syntax layer, no separate segments file yet).
- **Exploration happens on foundation:** example SQL (`analyses/pocore_segment_explorer.sql`) and one starter Lightdash explore in the demo. No viewer product yet; revisit when a client says what their people will use.

**Changes:**
1. **Everything is a segment.** `__segment__breakdown` and the `baseline_breakdowns` var are removed (setting the var now fails with a pointer to `split_by`). Breakdowns were only a shortcut for writing many segments, and having two concepts was confusing.
2. **`split_by` on a segment** also creates one segment per value of a low-cardinality column (`<id>__<value>`, label "Lapsed — Web"). Split rows carry `parent_segment_id`, `split_by`, `split_value`, and add up to the parent.
3. **Segment sets** (`segment_sets` var): listed segments in priority order, each person in the FIRST one they match (`<set>__<segment>`, labels numbered "1. …", "2. …"), plus optional `include_remainder` ("Everyone else"). A set's populations don't overlap and add up to the whole population. Set rows carry `segment_set_id` and use their parent's KPI and window; the remainder uses the defaults.
4. **`pocore__person__year` → `pocore_foundation__person__year`, `pocore__person__segment` → `pocore_foundation__person__segment`.** They are person-level rows (exploration material), not population summaries.
5. **Fix: segments with no completed outcome window no longer vanish** from the certified tables (a new custom segment, a new split value). They appear with their size and empty rates.

**Certified after v0.3.0:** `pocore__segment`, `pocore__segment__month`, `pocore__segment__test_option`, `pocore__year`, `pocore__cohort__year`, `pocore__cohort__age` (+ `__age__breakdown`, the sustainer per-channel cut: a cohort split, kept as is for now).
**Foundation after v0.3.0:** `__person`, `__gift`, `__person__month`, `__person__segment__month`, `__person__segment`, `__person__year`.

```yaml
segments:
  - id: cust_lapsed_v1
    label: "Lapsed"
    rule: "lifecycle_stage = 'lapsed'"
    split_by: acquisition_channel        # optional
segment_sets:
  - id: set_lapsed_value_v1              # must look like set_<name>_v<N>
    segments: [cust_lapsed_500_v1, cust_lapsed_100_v1, std_lapsed_v1]
    include_remainder: true              # optional; remainder_label optional
```

---

## v0.3.1: Supporter Insights export (2026-11-18)

- **New tier `export`** (schema `pocore`, module `pack`, on by default): tables shaped for one consumer, Supporter Insights (`pocore-pack`, its own repo).
  - `pocore_export__pack_cube`: one row per period (now / recent / same_season) × combination of the client's dropdown values; people, gave, revenue of givers and non-givers. Counts and sums only. Portable SQL (dbt macros), tested: the "now" rows add up to the population.
  - `pocore_export__pack_settings`: client name, window, holdout, minimum group size, engine version, as_of.
  - `pocore_export__pack_dimensions`: the dropdowns and bands, including the band SQL the pack writes into the segment rules it generates.
- **All client config lives in the client's dbt project** (`vars: po_core: pack:`; defaults and validation in `macros/pocore_pack_settings.sql`). The engine and the pack are client-agnostic.
- **The pack reads through dbt** (`dbt show`, using the client's profiles.yml and environment login): no credentials of its own, no warehouse-specific code. It checks `engine_version` and fails clearly if incompatible.
- **Delivery:** a step right after `dbt build` in the client's job (`pocore-pack build --project-dir . --target prod`), so a pack only ships when the engine's tests pass. Engine pinned by git tag, pack by version (also a git tag); both semver.

---

## v0.3.2 – v0.3.5 (2026-11-18)

- **v0.3.2** `standard_splits`: break down the standard groups from config (no duplicate custom copies).
- **v0.3.3** person features `reactivations_lifetime`, `days_since_reactivation` (as of each month-end); one shared column list (`pocore_snapshot_columns`) for `foundation__person` and `foundation__person__month`, with a test that the two agree on every shared column.
- **v0.3.4** actual (uncapped) revenue per person on `pocore__segment__month`; `revenue_cap` in the pack settings.
- **v0.3.5** a third measure, `started_monthly`: signed up to a new monthly plan within 30/90/180/365 days (gift flag `is_recurring_signup`). Groups can use it as their `primary_kpi`.
- **v0.3.6** "Planning Pack" renamed Supporter Insights. One list per engine concept, so a new one is added in one place:
  - `pocore_measures()`: every group measure, with how it reads ("gave within {days} days") and whether its windows add up (false for `retained`). Exported as `pocore_export__pack_measures`; the pack words its charts from it.
  - `pocore_active_days()` (365): the single 12-month line behind "active", "lapsed" (twice it) and a win-back gift.
  - `pocore_lifecycle_stages()`: stage labels and order. The stage logic stays written out in the person snapshot; a `lifecycle_stage` pack dimension without bands gets these labels as bands. A test fails if a stage has no label.

---

## 10. Work list (v0.2.0)

1. **Renames:** package, prefix, `donor` → `person`, folders, schemas. No logic changes, so every number must equal v0.1.2.
2. **Fixed KPI windows** `[30, 90, 180, 365]`, no longer a client var (rule 6). `retained` only at 90/180/365 (§13.2).
3. **Warehouse trap 8: no `least` / `greatest`.** NULL handling differs by warehouse (BigQuery, Snowflake and Databricks return NULL if any argument is NULL; Postgres, Redshift and DuckDB ignore NULLs), and older SQL Server lacks them. Add a `pocore_clamp(expr, low, high)` macro (a `case` expression). Today's uses:
   - `pode_ftr__kpi_outcomes.sql` line 101;
   - `pode_mtr__segment_power.sql` line 175.

   Also reject `revenue_cap: null`, and add the trap to D10.
4. **Foundation tables** (§6.1). The snapshot and outcomes merge into `__person__month`. `__gift` is new.
5. **Re-point `mtr` and certified at foundation**, rebuilding each certified table (§6.2) with a "One row per …" description and a uniqueness test.
6. **Consistency tests** (§6.2), surfaced in health.
7. **Demo project:** `packages.yml`, rename the `donor_engine__*` views, and update `_donor_engine.yml` (Lightdash) to the new names and columns.
8. **Drop old tables** in BigQuery dev and prod (dbt never drops renamed models).
9. **SPEC:** fold this in and retire the replaced sections.

Run the integration tests after every step. Step 1 must reproduce v0.1.2 exactly.

---

## 11. Risks to watch

| risk | what we do |
|---|---|
| client-defined KPIs | standard KPIs as columns; custom ones in `pocore__segment__kpi` |
| federated organisations | `org_unit` as an optional partition key |
| wide-table bloat (`foundation__person__month` especially) | every feature must have a consumer; column groups; remove dead columns |
| attributes that change over time | say per column whether it's current or as-of; the future fix is a `person_attribute_history` input |
| a wrong grain is expensive to fix | v0.2.0 is the cheap moment; build only what's used |
| nuanced questions not answerable by drag and drop | expected and stated as a service tier (§7). Trust comes from definitions living in foundation, so ad-hoc SQL agrees with dashboards, and from consistency tests between tables. |

---

## 12. Gaps found from a worked use case: reactivating lapsed regular givers

A prospective use case: predict which **lapsed regular givers** (people whose monthly plan stopped) can be won back, in a file of millions acquired through face-to-face, digital and phone channels, proven against a random holdout.

**Covered:**
- test sizing (`__segment__test_option`);
- expected rates (baselines);
- who's worth pursuing (segments and breakdowns by time since lapse, channel, tenure);
- field completeness (conform plus health);
- (planned) the readout.

**Gaps:**
1. **A `restarted_recurring` KPI.** `gave` counts one-time gifts and *new* sign-ups only.
2. **Plan-based lapse features** (months as a regular giver, payments made, time since the plan stopped, upgrades). These need `recurring_schedules` and, eventually, `foundation__recurring_plan`.
3. **Lapse reason** (voluntary vs payment failed): an optional `cancel_reason` on `recurring_schedules`.
4. **Contact history** (§9.1). Without it, baselines mix "came back unprompted" with "came back because contacted".
5. **Contact or campaign cost**, for "reactivations per dollar".
6. **Scale:** millions of people × 72 snapshots. Uses the optimisation path (partitioning, incremental with a trailing window, shorter lookback).

**Where prediction fits:** `foundation__person__month` *is* a leakage-safe training set, with features as of each month-end and outcomes after it. A model reads it and writes scores back as a person attribute, which segments then use. This is a direct payoff of putting outcomes in foundation.

---

## 13. Decisions (2026-11-18)

1. **Framing and §6 scope:** accepted.
2. **Fixed KPI windows:** `[30, 90, 180, 365]`; 30 days is needed. `retained` is only defined for windows longer than `recurring_active_days` (45), so the fixed column set is `gave` / `revenue` at 30/90/180/365 and `retained` at 90/180/365. There is no `retained_30d` column, rather than one that is always NULL. The current compile-time error ("every window must be > recurring_active_days") becomes a per-KPI rule.
3. **Stage horizons on `__person__year`:** 1, 2 and 3 years.
4. **Certified `__person`:** undecided. Start without it (business users get people via the roster and `__person__year`); adding it later is additive.
5. **Outcomes merged into `foundation__person__month`.**
6. **Internals:** convention, not `access: private`.
7. **License:** none for now. The repo stays public and *all rights reserved*.
8. **§12 gaps 1–3:** v0.3.0 (default; not explicitly answered).
