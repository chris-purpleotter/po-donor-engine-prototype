{#
  pode_ftr__kpi_outcomes — what each donor did AFTER each anchor date (SPEC §4).
  One row per donor x anchor_date (anchors = snapshot dates; later also experiment
  launch dates). Wide: one column per KPI x window, generated from `kpi_windows_days`.

  KPIs (per-donor; rate or capped mean — the KPI rule):
    gave_Nd     1 if a QUALIFYING gift arrives in (anchor, anchor + N days], else 0.
                Qualifying = non-refund eligible gift that is one-time, OR the first
                payment of a recurring schedule (a new sign-up). Routine recurring
                payments don't count; upgrades don't count (day one).
    revenue_Nd  net eligible giving in the window, floored at 0 and capped at
                `revenue_cap`. revenue_uncapped_Nd kept for descriptive use.
    retained_Nd 1 if the donor is still an active sustainer on day anchor + N: a recurring
                payment in the `recurring_active_days` (45) days up to and including that day.
                The same rule that puts donors in the sustainer segment (D6). The headline
                KPI for sustainers, where "gave a qualifying gift" is the wrong question.
                Needs N > recurring_active_days (only gifts after the anchor are looked at).
    is_complete_Nd  the whole window has elapsed by as_of. Incomplete windows are
                    partial and must never be treated as final.
#}

{%- set windows = var('kpi_windows_days') -%}
{%- set max_window = windows | max -%}
{%- set revenue_cap = var('revenue_cap') -%}
{%- set recurring_active_days = var('recurring_active_days') | int -%}
{%- if windows | min <= recurring_active_days -%}
    {{ exceptions.raise_compiler_error("po_donor_engine: every kpi_windows_days must be > recurring_active_days (" ~ recurring_active_days ~ ") for the retained KPI") }}
{%- endif -%}
{%- set as_of_sql = "cast('" ~ var('as_of') ~ "' as date)" -%}

with anchors as (

    select donor_id, snapshot_date as anchor_date
    from {{ ref('pode_ftr__donor_snapshot') }}

),

gifts as (

    select donor_id, gift_id, gift_date, amount, gift_type, recurring_schedule_id, is_refund
    from {{ ref('pode_can__gifts') }}
    where is_kpi_eligible

),

-- First payment of each recurring schedule = the sign-up.
schedule_starts as (

    select recurring_schedule_id, min(gift_date) as first_payment_date
    from gifts
    where gift_type = 'recurring' and not is_refund
    group by recurring_schedule_id

),

gifts_flagged as (

    select
        g.*,
        (not g.is_refund
            and (g.gift_type = 'one_time' or g.gift_date = s.first_payment_date)) as is_qualifying,
        (not g.is_refund and g.gift_type = 'recurring')                         as is_recurring_payment
    from gifts as g
    left join schedule_starts as s
        on s.recurring_schedule_id = g.recurring_schedule_id

),

-- Each anchor joined to the donor's gifts in the longest window after it.
outcomes as (

    select
        a.donor_id,
        a.anchor_date,
        {%- for w in windows %}
        max(case when q.is_qualifying
                  and q.gift_date <= cast({{ dbt.dateadd('day', w, 'a.anchor_date') }} as date)
                 then 1 else 0 end)                                            as gave_{{ w }}d,
        coalesce(sum(case when q.gift_date <= cast({{ dbt.dateadd('day', w, 'a.anchor_date') }} as date)
                          then q.amount end), 0)                               as revenue_uncapped_{{ w }}d,
        max(case when q.is_recurring_payment
                  and q.gift_date >= cast({{ dbt.dateadd('day', w - recurring_active_days, 'a.anchor_date') }} as date)
                  and q.gift_date <= cast({{ dbt.dateadd('day', w, 'a.anchor_date') }} as date)
                 then 1 else 0 end)                                            as retained_{{ w }}d
        {%- if not loop.last %},{% endif %}
        {%- endfor %}
    from anchors as a
    left join gifts_flagged as q
        on  q.donor_id  = a.donor_id
        and q.gift_date > a.anchor_date
        and q.gift_date <= cast({{ dbt.dateadd('day', max_window, 'a.anchor_date') }} as date)
    group by a.donor_id, a.anchor_date

)

select
    donor_id,
    anchor_date,
    {%- for w in windows %}
    gave_{{ w }}d,
    least(greatest(revenue_uncapped_{{ w }}d, 0), {{ revenue_cap }})            as revenue_{{ w }}d,
    revenue_uncapped_{{ w }}d,
    retained_{{ w }}d,
    (cast({{ dbt.dateadd('day', w, 'anchor_date') }} as date) <= {{ as_of_sql }}) as is_complete_{{ w }}d
    {%- if not loop.last %},{% endif %}
    {%- endfor %}
from outcomes
