{#
  pocore_group_at_a_time — ONE GROUP OVER A RANGE OF MONTH-ENDS, each person counted once
  (an example to copy, not a table). The reference for doing the report's "What happened"
  views in SQL or a BI tool, for ANY range (the report itself only offers fixed choices).

  Everyone who was in the group at any month-end from first_month_end to last_month_end, each
  counted ONCE, from their first month-end in that range (their "start"):
    1. tenure        how long they had been in the group at their start (current term)
    2. funnel        how many gave within 30 / 90 / 180 / 365 days of their start
    3. when          the calendar month of their first qualifying gift after their start

  Built only from certified/foundation tables: pocore__person__group__term,
  pocore_foundation__person__month_end. Run it with
      dbt compile -s pocore_group_at_a_time      (then run target/compiled/.../pocore_group_at_a_time.sql)

  Unlike the report, a range mixes starts: a window that hasn't finished for every person yet
  is partial (is_complete_<N>d false), so its count is a floor, not a final number.
#}

{#- ===== edit here ===== -#}
{%- set group_id = 'std_prospect_v1' -%}
{%- set first_month_end = '2025-01-31' -%}
{%- set last_month_end = '2025-12-31' -%}
{#- ===================== -#}

with

pocore__person__group__term as (select * from {{ ref('pocore__person__group__term') }}),

pocore_foundation__person__month_end as (select * from {{ ref('pocore_foundation__person__month_end') }}),

-- each person in the group at some month-end in the range, at their FIRST such month-end
starts as (

    select
        pocore__person__group__term.person_id,
        pocore__person__group__term.joined_month_end,
        pocore__person__group__term.is_joined_before_data,
        min(pocore_foundation__person__month_end.month_end_date)                       as start_month_end
    from pocore__person__group__term
    inner join pocore_foundation__person__month_end
        on  pocore_foundation__person__month_end.person_id = pocore__person__group__term.person_id
        and pocore_foundation__person__month_end.month_end_date >= pocore__person__group__term.joined_month_end
        and (pocore__person__group__term.left_month_end is null
             or pocore_foundation__person__month_end.month_end_date < pocore__person__group__term.left_month_end)
    where pocore__person__group__term.group_id = '{{ group_id }}'
      and pocore_foundation__person__month_end.month_end_date between cast('{{ first_month_end }}' as date) and cast('{{ last_month_end }}' as date)
    group by pocore__person__group__term.person_id, pocore__person__group__term.joined_month_end,
             pocore__person__group__term.is_joined_before_data

),

-- one row per person (a person with two terms inside the range keeps the earlier start)
people as (

    select
        starts.person_id,
        starts.start_month_end,
        starts.is_joined_before_data,
        (extract(year from starts.start_month_end) * 12 + extract(month from starts.start_month_end))
          - (extract(year from starts.joined_month_end) * 12 + extract(month from starts.joined_month_end))  as months_in_group,
        row_number() over (partition by starts.person_id order by starts.start_month_end)                   as start_rank
    from starts

),

outcomes as (

    select
        people.person_id,
        people.months_in_group,
        people.is_joined_before_data,
        pocore_foundation__person__month_end.next_gave_date,
        {%- for w in pocore_engine_config__kpi_windows() %}
        pocore_foundation__person__month_end.gave_{{ w }}d,
        pocore_foundation__person__month_end.is_complete_{{ w }}d{{ ',' if not loop.last }}
        {%- endfor %}
    from people
    inner join pocore_foundation__person__month_end
        on  pocore_foundation__person__month_end.person_id      = people.person_id
        and pocore_foundation__person__month_end.month_end_date = people.start_month_end
    where people.start_rank = 1

)

-- 1. tenure (months in the group at their start; before-data people have been in at least this long)
select 'tenure' as part, cast(months_in_group as {{ dbt.type_string() }}) as bucket, count(*) as people
from outcomes
group by months_in_group

union all

-- 2. funnel (people_with_finished_window: how many of them have had the full N days yet)
{%- for w in pocore_engine_config__kpi_windows() %}
select 'gave within {{ w }} days', 'gave', sum(gave_{{ w }}d) from outcomes
union all
select 'gave within {{ w }} days', 'people_with_finished_window', sum(case when is_complete_{{ w }}d then 1 else 0 end) from outcomes
union all
{%- endfor %}
select 'funnel', 'people', count(*) from outcomes

union all

-- 3. when: calendar month of the first qualifying gift after their start
select 'when they gave', cast(cast({{ dbt.date_trunc('month', 'next_gave_date') }} as date) as {{ dbt.type_string() }}), count(*)
from outcomes
where next_gave_date is not null
group by {{ dbt.date_trunc('month', 'next_gave_date') }}

order by 1, 2
