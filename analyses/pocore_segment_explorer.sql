{#
  pocore_segment_explorer — AD-HOC EXPLORATION on foundation (an example to copy, not a table).

  The certified tables are our standard view (pocore__segment, pocore__segment__breakdown).
  This query is the dynamic version: put ANY combination of filters in `filters`, and get the
  same headline numbers the engine computes for a segment:
    people_now          people matching the filters at the latest month-end
    rate_recent         share who achieved the KPI within the window, pooled over the last 3
                        month-ends whose window has finished (today's normal)
    rate_same_season    the same, for month-ends 11-13 months before the latest (planning baseline)
    revenue_per_extra_donor  revenue among people who succeeded minus among those who didn't
                        (recent months, person-weighted)
    value_per_point     people_now x 0.01 x revenue_per_extra_donor
    detectable_lift     smallest lift a test with holdout_pct held out could reliably detect:
                        2.8016 x sqrt(p(1-p) x (1/n_treated + 1/n_holdout))
                        (2.8016 = z for 95% confidence two-sided + z for 80% power)

  It works on any warehouse: dbt compiles it for yours. Run it with
      dbt compile -s pocore_segment_explorer      (then run target/compiled/.../pocore_segment_explorer.sql)
  or copy it into the client project's analyses/ and edit freely.

  Close to, not identical to, the certified numbers: the engine's detectable lift also allows
  for month-to-month swings in the rate (pooled variance), so it is slightly more cautious.
  When a filter set proves worth tracking, make it a custom segment: then it gets history,
  a roster, flows and (later) experiment readouts, and everyone uses the same definition.
#}

{#- ===== edit here ===== -#}
{%- set filters -%}
    lifecycle_stage = 'lapsed'
    and acquisition_channel = 'Face to Face'
{%- endset -%}
{%- set kpi = 'gave' -%}             {#- gave, or retained (windows 90/180/365 only) -#}
{%- set window_days = 180 -%}        {#- 30, 90, 180, 365 -#}
{%- set holdout_pct = 15 -%}
{#- ===================== -#}

with people_months as (

    select
        month_end_date,
        person_id,
        {{ kpi }}_{{ window_days }}d               as success,
        revenue_{{ window_days }}d                 as revenue,
        is_complete_{{ window_days }}d             as is_complete
    from {{ ref('pocore_foundation__person__month_end') }}
    where person_type = 'individual'               -- the engine's default segment filter
      and not is_deceased
      and ({{ filters }})

),

latest as (

    select max(month_end_date) as latest_month_end
    from {{ ref('pocore_foundation__person__month_end') }}

),

-- One row per month-end: how many matched, how many succeeded, revenue by outcome.
monthly as (

    select
        month_end_date,
        count(*)                                                        as n,
        sum(success)                                                    as successes,
        avg(case when success = 1 then cast(revenue as {{ dbt.type_float() }}) end)
          - coalesce(avg(case when success = 0 then cast(revenue as {{ dbt.type_float() }}) end), 0)
                                                                        as revenue_gap,
        min(case when is_complete then 1 else 0 end)                    as is_complete
    from people_months
    group by month_end_date

),

ranked as (

    select
        m.*,
        row_number() over (order by m.month_end_date desc)              as recency_rank
    from monthly as m
    where m.is_complete = 1

),

summary as (

    select
        (select count(*) from people_months as p cross join latest as l
          where p.month_end_date = l.latest_month_end)                   as people_now,
        (select cast(sum(successes) as {{ dbt.type_float() }}) / nullif(sum(n), 0)
           from ranked where recency_rank <= 3)                          as rate_recent,
        (select sum(revenue_gap * n) / nullif(sum(case when revenue_gap is not null then n end), 0)
           from ranked where recency_rank <= 3)                          as revenue_per_extra_donor,
        (select cast(sum(successes) as {{ dbt.type_float() }}) / nullif(sum(n), 0)
           from ranked as r cross join latest as l
          where r.month_end_date
                between cast({{ dbt.dateadd('month', -13, dbt.date_trunc('month', 'l.latest_month_end')) }} as date)
                    and cast({{ dbt.dateadd('month', -10, dbt.date_trunc('month', 'l.latest_month_end')) }} as date)
        )                                                                as rate_same_season

)

select
    people_now,
    '{{ kpi }}'                                                          as kpi,
    {{ window_days }}                                                    as window_days,
    rate_recent,
    rate_same_season,
    coalesce(rate_same_season, rate_recent)                              as rate_planning,
    revenue_per_extra_donor,
    people_now * 0.01 * revenue_per_extra_donor                          as value_per_point,
    {{ holdout_pct }}                                                    as holdout_pct,
    -- undefined (null) when nobody is in the group or the rate is exactly 0 or 1
    case when people_now > 0
              and coalesce(rate_same_season, rate_recent) > 0
              and coalesce(rate_same_season, rate_recent) < 1 then
        2.8016 * sqrt(coalesce(rate_same_season, rate_recent) * (1 - coalesce(rate_same_season, rate_recent))
                      * (1.0 / (people_now * (100 - {{ holdout_pct }}) / 100.0)
                         + 1.0 / (people_now * {{ holdout_pct }} / 100.0)))
    end                                                                  as detectable_lift
from summary
