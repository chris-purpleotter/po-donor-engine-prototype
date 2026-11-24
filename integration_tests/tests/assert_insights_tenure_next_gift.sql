-- The tenure bands of a group at a month-end add up to its people; "when they gave" months 1-12
-- add up to how many of them gave within 365 days, and never fall outside 1-12.
-- Any row returned is a failure.

with

pocore_export__insights_tenure as (select * from {{ ref('pocore_export__insights_tenure') }}),

pocore_export__insights_next_gift as (select * from {{ ref('pocore_export__insights_next_gift') }}),

pocore__group__month as (select * from {{ ref('pocore__group__month') }}),

pocore_group__membership__month as (select * from {{ ref('pocore_group__membership__month') }}),

pocore_foundation__person__month_end as (select * from {{ ref('pocore_foundation__person__month_end') }}),

tenure_totals as (
    select group_id, month_end_date, sum(people) as people
    from pocore_export__insights_tenure
    group by group_id, month_end_date
),

tenure_mismatch as (
    select pocore__group__month.group_id, cast(pocore__group__month.month_end_date as {{ dbt.type_string() }}) as detail,
           'tenure bands do not add up to people_in_group' as problem
    from pocore__group__month
    left join tenure_totals
        on tenure_totals.group_id = pocore__group__month.group_id and tenure_totals.month_end_date = pocore__group__month.month_end_date
    where coalesce(tenure_totals.people, 0) <> pocore__group__month.people_in_group
),

gave_365 as (
    select pocore_group__membership__month.group_id, pocore_group__membership__month.month_end_date,
           sum(pocore_foundation__person__month_end.gave_365d) as people
    from pocore_group__membership__month
    inner join pocore_foundation__person__month_end
        on  pocore_foundation__person__month_end.person_id      = pocore_group__membership__month.person_id
        and pocore_foundation__person__month_end.month_end_date = pocore_group__membership__month.month_end_date
    group by pocore_group__membership__month.group_id, pocore_group__membership__month.month_end_date
),

next_gift_totals as (
    select group_id, month_end_date, sum(people) as people
    from pocore_export__insights_next_gift
    group by group_id, month_end_date
),

next_gift_mismatch as (
    select gave_365.group_id, cast(gave_365.month_end_date as {{ dbt.type_string() }}) as detail,
           'when-they-gave months do not add up to gave_365d' as problem
    from gave_365
    left join next_gift_totals
        on next_gift_totals.group_id = gave_365.group_id and next_gift_totals.month_end_date = gave_365.month_end_date
    where coalesce(next_gift_totals.people, 0) <> gave_365.people
),

next_gift_range as (
    select group_id, cast(month_end_date as {{ dbt.type_string() }}) as detail, 'months_after outside 1-12' as problem
    from pocore_export__insights_next_gift
    where months_after < 1 or months_after > 12
)

select * from tenure_mismatch
union all select * from next_gift_mismatch
union all select * from next_gift_range
