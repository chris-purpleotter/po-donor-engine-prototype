-- Terms (pocore__person__group__term) agree with the monthly flows, never overlap, and
-- next_gave_date agrees with gave_<N>d. Any row returned is a failure.

with

pocore__person__group__term as (select * from {{ ref('pocore__person__group__term') }}),

pocore__group__month as (select * from {{ ref('pocore__group__month') }}),

pocore_foundation__person__month_end as (select * from {{ ref('pocore_foundation__person__month_end') }}),

joins as (
    select group_id, joined_month_end as month_end_date, count(*) as terms_joining
    from pocore__person__group__term
    where not is_joined_before_data
    group by group_id, joined_month_end
),

leaves as (
    select group_id, left_month_end as month_end_date, count(*) as terms_leaving
    from pocore__person__group__term
    where left_month_end is not null
    group by group_id, left_month_end
),

flows_mismatch as (
    select pocore__group__month.group_id, cast(pocore__group__month.month_end_date as {{ dbt.type_string() }}) as detail,
           'terms joining/leaving differ from people_entering/people_leaving' as problem
    from pocore__group__month
    left join joins
        on joins.group_id = pocore__group__month.group_id and joins.month_end_date = pocore__group__month.month_end_date
    left join leaves
        on leaves.group_id = pocore__group__month.group_id and leaves.month_end_date = pocore__group__month.month_end_date
    where pocore__group__month.people_entering is not null
      and (coalesce(joins.terms_joining, 0) <> pocore__group__month.people_entering
           or coalesce(leaves.terms_leaving, 0) <> pocore__group__month.people_leaving)
),

next_term as (
    select
        person_id, group_id, term_number, left_month_end,
        lead(joined_month_end) over (partition by person_id, group_id order by term_number) as next_joined_month_end
    from pocore__person__group__term
),

overlapping_terms as (
    select group_id, cast(person_id as {{ dbt.type_string() }}) as detail,
           'a term starts before the previous one ended' as problem
    from next_term
    where next_joined_month_end is not null
      and (left_month_end is null or next_joined_month_end < left_month_end)
),

next_gave as (
    select 'foundation' as group_id, cast(person_id as {{ dbt.type_string() }}) as detail,
           'gave_<N>d disagrees with next_gave_date' as problem
    from pocore_foundation__person__month_end
    where {% for w in po_core.pocore_engine_config__kpi_windows() %}
          gave_{{ w }}d <> case when next_gave_date <= cast({{ dbt.dateadd('day', w, 'month_end_date') }} as date) then 1 else 0 end
          {%- if not loop.last %} or {% endif %}
          {%- endfor %}
)

select * from flows_mismatch
union all select * from overlapping_terms
union all select * from next_gave
