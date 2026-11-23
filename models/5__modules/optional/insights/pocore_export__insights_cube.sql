{{ config(enabled=pocore_client_config__module_enabled('insights')) }}

{#
  pocore_export__insights_cube — Supporter Insights' "Build a population" data.
  ONE ROW PER PERIOD x COMBINATION OF DIMENSION VALUES (the client's insights.dimensions).
  Counts and sums only: no person ids, no names. The report re-sums these rows in the browser
  for whatever values someone ticks.

    period        now          the latest month-end: who is in the population today
                  recent       the last 3 month-ends whose outcome window has finished
                  same_season  month-ends 11-13 months before the latest (window finished)
    people        person-months in the cell (for 'now': people)
    gave          of them, how many gave within insights.window_days
    revenue_givers / revenue_nongivers   capped window revenue of those who did / didn't

  Population: individuals, not deceased (the same as segments). Built from foundation.
#}

{%- set s = pocore_client_config__insights_settings() -%}
{%- set w = s.window_days | int -%}
{%- set str = dbt.type_string() -%}
{%- set flt = dbt.type_float() -%}

with

pocore_foundation__person__month_end as (select * from {{ ref('pocore_foundation__person__month_end') }}),

pocore_foundation__person as (select * from {{ ref('pocore_foundation__person') }}),

latest as (

    select max(month_end_date) as latest_month_end
    from pocore_foundation__person__month_end

),

base as (

    -- the month-end snapshot plus who the person is (the dropdowns can use either)
    select
        pocore_foundation__person__month_end.*,
        {%- for c in pocore_columns__person() %}
        person.{{ c }},
        {%- endfor %}
        {{ dbt.datediff('pocore_foundation__person__month_end.month_end_date', 'latest.latest_month_end', 'month') }} as months_back
    from pocore_foundation__person__month_end
    inner join pocore_foundation__person as person
        on person.person_id = pocore_foundation__person__month_end.person_id
    cross join latest
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

    select 'now' as period, base.* from base where base.months_back = 0
    union all
    select 'recent' as period, base.* from base
    where base.month_end_date in (select month_end_date from recent_months)
    union all
    select 'same_season' as period, base.* from base
    where base.months_back between 11 and 13 and base.is_complete_{{ w }}d

),

-- Each dimension's value per row, computed once so the grouping uses plain columns.
dimmed as (

    select
        period,
        {%- for d in s.dimensions %}
        {%- if d.bands %}
        case
            {%- for b in d.bands %}
            when {{ b.sql }} then {{ pocore_helpers__string_literal(b.label) }}
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
