{{ config(enabled=pocore_module_enabled('pack')) }}

{#
  pocore_export__pack_cube — Supporter Insights' "Build a population" data.
  ONE ROW PER PERIOD x COMBINATION OF DIMENSION VALUES (the client's pack.dimensions).
  Counts and sums only: no person ids, no names. The pack re-sums these rows in the browser
  for whatever values someone ticks.

    period        now          the latest month-end: who is in the population today
                  recent       the last 3 month-ends whose outcome window has finished
                  same_season  month-ends 11-13 months before the latest (window finished)
    people        person-months in the cell (for 'now': people)
    gave          of them, how many gave within pack.window_days
    revenue_givers / revenue_nongivers   capped window revenue of those who did / didn't

  Population: individuals, not deceased (the same as segments). Built from foundation.
#}

{%- set s = pocore_pack_settings() -%}
{%- set w = s.window_days | int -%}
{%- set str = dbt.type_string() -%}
{%- set flt = dbt.type_float() -%}

with latest as (

    select max(month_end_date) as latest_month_end
    from {{ ref('pocore_foundation__person__month_end') }}

),

base as (

    -- the month-end snapshot plus who the person is (the dropdowns can use either)
    select
        p.*,
        {%- for c in pocore_snapshot_columns('attributes') %}
        person.{{ c }},
        {%- endfor %}
        {{ dbt.datediff('p.month_end_date', 'l.latest_month_end', 'month') }} as months_back
    from {{ ref('pocore_foundation__person__month_end') }} as p
    inner join {{ ref('pocore_foundation__person') }} as person
        on person.person_id = p.person_id
    cross join latest as l
    where person.person_type = 'individual'
      and not person.is_deceased

),

complete_months as (

    select distinct month_end_date
    from base
    where is_complete_{{ w }}d

),

recent_months as (

    select month_end_date
    from (
        select month_end_date, row_number() over (order by month_end_date desc) as recency_rank
        from complete_months
    ) as ranked
    where recency_rank <= 3

),

tagged as (

    select 'now' as period, b.* from base as b where b.months_back = 0
    union all
    select 'recent' as period, b.* from base as b
    where b.month_end_date in (select month_end_date from recent_months)
    union all
    select 'same_season' as period, b.* from base as b
    where b.months_back between 11 and 13 and b.is_complete_{{ w }}d

),

-- Each dimension's value per row, computed once so the grouping uses plain columns.
dimmed as (

    select
        period,
        {%- for d in s.dimensions %}
        {%- if d.bands %}
        case
            {%- for b in d.bands %}
            when {{ b.sql }} then {{ pocore_string_literal(b.label) }}
            {%- endfor %}
            else 'unknown'
        end                                                         as {{ d.name }},
        {%- else %}
        coalesce(cast({{ d.name }} as {{ str }}), 'unknown')        as {{ d.name }},
        {%- endif %}
        {%- endfor %}
        gave_{{ w }}d                                               as gave,
        revenue_{{ w }}d                                            as revenue
    from tagged

)

select
    period,
    {%- for d in s.dimensions %}
    {{ d.name }},
    {%- endfor %}
    count(*)                                                        as people,
    sum(gave)                                                       as gave,
    cast(sum(case when gave = 1 then revenue else 0 end) as {{ flt }}) as revenue_givers,
    cast(sum(case when gave = 0 then revenue else 0 end) as {{ flt }}) as revenue_nongivers
from dimmed
group by period{% for d in s.dimensions %}, {{ d.name }}{% endfor %}
