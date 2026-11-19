{#
  pocore_ftr__kpi_outcomes — what each person did AFTER each month-end (SPEC §4).
  One row per person x anchor_date (anchors = the month-end snapshot dates). Experiment
  readouts will use the same windows anchored on the client's assigned_date, in their own
  model (DESIGN §9.6), not as extra rows here. Wide: one column per KPI x window. Windows are FIXED by the engine
  (pocore_kpi_windows(): 30/90/180/365; retained only 90/180/365), so every client gets
  the same columns.

  KPIs (per-donor; rate or capped mean — the KPI rule):
    gave_Nd     1 if a QUALIFYING gift arrives in (anchor, anchor + N days], else 0.
                Qualifying = non-refund eligible gift that is one-time, OR the first
                payment of a recurring schedule (a new sign-up). Routine recurring
                payments don't count; upgrades don't count (day one).
    started_monthly_Nd  1 if the person signs up to a NEW monthly plan (the first payment of a
                recurring schedule) in (anchor, anchor + N days], else 0. Converting one-time
                donors (or prospects) to monthly giving.
    revenue_Nd  net eligible giving in the window, floored at 0 and capped at
                `revenue_cap`. revenue_uncapped_Nd kept for descriptive use.
    retained_Nd 1 if the donor is still an active sustainer on day anchor + N: a recurring
                payment in the `recurring_active_days` (45) days up to and including that day.
                The same rule that puts donors in the sustainer segment (D6). The headline
                KPI for sustainers, where "gave a qualifying gift" is the wrong question.
                Needs N > recurring_active_days (only gifts after the anchor are looked at),
                so there is no retained_30d.
    is_complete_Nd  the whole window has elapsed by as_of. Incomplete windows are
                    partial and must never be treated as final.
#}

{%- set windows = pocore_kpi_windows() -%}
{%- set retained_windows = pocore_kpi_windows('retained') -%}
{%- set max_window = windows | max -%}
{%- set revenue_cap = var('revenue_cap') -%}
{%- if revenue_cap is none -%}
    {{ exceptions.raise_compiler_error("po_core: revenue_cap must be a number (it caps per-person revenue so outliers don't swamp means); null is not allowed") }}
{%- endif -%}
{%- set recurring_active_days = var('recurring_active_days') | int -%}
{%- set as_of_sql = "cast('" ~ var('as_of') ~ "' as date)" -%}

with anchors as (

    select person_id, snapshot_date as anchor_date
    from {{ ref('pocore_ftr__person_snapshot') }}

),

-- Eligible gifts with the engine's gift-level definitions (pocore_ftr__gift_flags).
gifts_flagged as (

    select
        g.person_id, g.gift_id, g.gift_date, g.amount,
        f.is_qualifying,
        f.is_recurring_payment,
        f.is_recurring_signup
    from {{ ref('pocore_can__gifts') }} as g
    inner join {{ ref('pocore_ftr__gift_flags') }} as f
        on f.gift_id = g.gift_id
    where g.is_kpi_eligible

),

-- Each anchor joined to the donor's gifts in the longest window after it.
outcomes as (

    select
        a.person_id,
        a.anchor_date,
        {%- for w in windows %}
        max(case when q.is_qualifying
                  and q.gift_date <= cast({{ dbt.dateadd('day', w, 'a.anchor_date') }} as date)
                 then 1 else 0 end)                                            as gave_{{ w }}d,
        max(case when q.is_recurring_signup
                  and q.gift_date <= cast({{ dbt.dateadd('day', w, 'a.anchor_date') }} as date)
                 then 1 else 0 end)                                            as started_monthly_{{ w }}d,
        coalesce(sum(case when q.gift_date <= cast({{ dbt.dateadd('day', w, 'a.anchor_date') }} as date)
                          then q.amount end), 0)                               as revenue_uncapped_{{ w }}d
        {%- if w in retained_windows %},
        max(case when q.is_recurring_payment
                  and q.gift_date >= cast({{ dbt.dateadd('day', w - recurring_active_days, 'a.anchor_date') }} as date)
                  and q.gift_date <= cast({{ dbt.dateadd('day', w, 'a.anchor_date') }} as date)
                 then 1 else 0 end)                                            as retained_{{ w }}d
        {%- endif %}
        {%- if not loop.last %},{% endif %}
        {%- endfor %}
    from anchors as a
    left join gifts_flagged as q
        on  q.person_id  = a.person_id
        and q.gift_date > a.anchor_date
        and q.gift_date <= cast({{ dbt.dateadd('day', max_window, 'a.anchor_date') }} as date)
    group by a.person_id, a.anchor_date

)

select
    person_id,
    anchor_date,
    {%- for w in windows %}
    gave_{{ w }}d,
    started_monthly_{{ w }}d,
    {{ pocore_clamp('revenue_uncapped_' ~ w ~ 'd', 0, revenue_cap) }}         as revenue_{{ w }}d,
    revenue_uncapped_{{ w }}d,
    {%- if w in retained_windows %}
    retained_{{ w }}d,
    {%- endif %}
    (cast({{ dbt.dateadd('day', w, 'anchor_date') }} as date) <= {{ as_of_sql }}) as is_complete_{{ w }}d
    {%- if not loop.last %},{% endif %}
    {%- endfor %}
from outcomes
