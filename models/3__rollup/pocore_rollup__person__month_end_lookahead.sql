{#
  pocore_rollup__person__month_end_lookahead — what each person did AFTER each month-end (SPEC §4).
  One row per person x anchor_date (anchors = the month-end snapshot dates). Experiment
  readouts will use the same windows anchored on the client's assigned_date, in their own
  model (DESIGN §9.6), not as extra rows here. Wide: one column per KPI x window. Windows are FIXED by the engine
  (pocore_engine_config__kpi_windows(): 30/90/180/365; retained only 90/180/365), so every client gets
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

{%- set windows = pocore_engine_config__kpi_windows() -%}
{%- set retained_windows = pocore_engine_config__kpi_windows('retained') -%}
{%- set max_window = windows | max -%}
{%- set revenue_cap = var('revenue_cap') -%}
{%- if revenue_cap is none -%}
    {{ exceptions.raise_compiler_error("po_core: revenue_cap must be a number (it caps per-person revenue so outliers don't swamp means); null is not allowed") }}
{%- endif -%}
{%- set recurring_active_days = var('recurring_active_days') | int -%}

with

pocore_rollup__person__month_end_lookback as (select * from {{ ref('pocore_rollup__person__month_end_lookback') }}),

pocore_event__gift as (select * from {{ ref('pocore_event__gift') }}),

anchors as (

    select person_id, snapshot_date as anchor_date
    from pocore_rollup__person__month_end_lookback

),

-- Eligible gifts with the engine's gift-level definitions (pocore_event__gift).
gifts_flagged as (

    select
        person_id, gift_id, gift_date, amount,
        is_qualifying,
        is_recurring_payment,
        is_first_recurring_payment
    from pocore_event__gift
    where is_kpi_eligible

),

-- Each anchor joined to the donor's gifts in the longest window after it.
outcomes as (

    select
        anchors.person_id,
        anchors.anchor_date,
        {%- for w in windows %}
        max(case when gifts_flagged.is_qualifying
                  and gifts_flagged.gift_date <= cast({{ dbt.dateadd('day', w, 'anchors.anchor_date') }} as date)
                 then 1 else 0 end)                                            as gave_{{ w }}d,
        max(case when gifts_flagged.is_first_recurring_payment
                  and gifts_flagged.gift_date <= cast({{ dbt.dateadd('day', w, 'anchors.anchor_date') }} as date)
                 then 1 else 0 end)                                            as started_monthly_{{ w }}d,
        coalesce(sum(case when gifts_flagged.gift_date <= cast({{ dbt.dateadd('day', w, 'anchors.anchor_date') }} as date)
                          then gifts_flagged.amount end), 0)                               as revenue_uncapped_{{ w }}d
        {%- if w in retained_windows %},
        max(case when gifts_flagged.is_recurring_payment
                  and gifts_flagged.gift_date >= cast({{ dbt.dateadd('day', w - recurring_active_days, 'anchors.anchor_date') }} as date)
                  and gifts_flagged.gift_date <= cast({{ dbt.dateadd('day', w, 'anchors.anchor_date') }} as date)
                 then 1 else 0 end)                                            as retained_{{ w }}d
        {%- endif %}
        {%- if not loop.last %},{% endif %}
        {%- endfor %}
    from anchors
    left join gifts_flagged
        on  gifts_flagged.person_id  = anchors.person_id
        and gifts_flagged.gift_date > anchors.anchor_date
        and gifts_flagged.gift_date <= cast({{ dbt.dateadd('day', max_window, 'anchors.anchor_date') }} as date)
    group by anchors.person_id, anchors.anchor_date

)

select
    person_id,
    anchor_date,
    {%- for w in windows %}
    gave_{{ w }}d,
    started_monthly_{{ w }}d,
    {{ pocore_helpers__clamp('revenue_uncapped_' ~ w ~ 'd', 0, revenue_cap) }}         as revenue_{{ w }}d,
    revenue_uncapped_{{ w }}d,
    {%- if w in retained_windows %}
    retained_{{ w }}d,
    {%- endif %}
    (cast({{ dbt.dateadd('day', w, 'anchor_date') }} as date) <= {{ pocore_client_config__as_of_date() }}) as is_complete_{{ w }}d
    {%- if not loop.last %},{% endif %}
    {%- endfor %}
from outcomes
