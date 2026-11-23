{#
  Gifts that look like recurring payments but arrived as one_time (schedule linking broken).
  Returns gift_id, person_id, gift_date, amount, pattern ('partial' | 'full').
    partial: same donor + amount as one of their RECURRING gifts, ~1 month apart
    full:    3+ one_time gifts of the identical amount at ~monthly intervals
  Used by the pocore_suspected_unlinked_recurring test (warn) and pocore_admin__health.
#}

{% macro pocore_sql__suspected_unlinked_recurring(gifts_relation) %}
with gifts as (

    select gift_id, person_id, gift_date, amount, gift_type
    from {{ gifts_relation }}
    where not is_refund

),

-- Partial pattern: same donor + amount as one of their RECURRING gifts, ~1 month apart.
partial_break as (

    select distinct
        one_time.gift_id, one_time.person_id, one_time.gift_date, one_time.amount,
        'partial' as pattern
    from gifts as one_time
    inner join gifts as recurring
        on  recurring.person_id  = one_time.person_id
        and recurring.amount    = one_time.amount
        and recurring.gift_type = 'recurring'
        and abs({{ dbt.datediff('recurring.gift_date', 'one_time.gift_date', 'day') }}) between 25 and 35
    where one_time.gift_type = 'one_time'

),

-- Full pattern: 3+ one_time gifts of the identical amount at ~monthly intervals.
one_time_gaps as (

    select
        gift_id, person_id, gift_date, amount,
        {{ dbt.datediff(
            'lag(gift_date) over (partition by person_id, amount order by gift_date, gift_id)',
            'gift_date', 'day') }} as days_since_prev_same_amount
    from gifts
    where gift_type = 'one_time'

),

monthly_runs as (

    -- 2+ monthly gaps = 3+ gifts on a monthly rhythm
    select person_id, amount
    from one_time_gaps
    where days_since_prev_same_amount between 25 and 35
    group by person_id, amount
    having count(*) >= 2

),

full_break as (

    select one_time_gaps.gift_id, one_time_gaps.person_id, one_time_gaps.gift_date, one_time_gaps.amount, 'full' as pattern
    from one_time_gaps
    inner join monthly_runs
        on monthly_runs.person_id = one_time_gaps.person_id and monthly_runs.amount = one_time_gaps.amount

)

select * from partial_break
union all
select * from full_break
{% endmacro %}
