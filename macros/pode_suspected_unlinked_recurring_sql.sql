{#
  Gifts that look like recurring payments but arrived as one_time (schedule linking broken).
  Returns gift_id, donor_id, gift_date, amount, pattern ('partial' | 'full').
    partial: same donor + amount as one of their RECURRING gifts, ~1 month apart
    full:    3+ one_time gifts of the identical amount at ~monthly intervals
  Used by the pode_suspected_unlinked_recurring test (warn) and pode_srv__project_health.
#}

{% macro pode_suspected_unlinked_recurring_sql(gifts_relation) %}
with gifts as (

    select gift_id, donor_id, gift_date, amount, gift_type
    from {{ gifts_relation }}
    where not is_refund

),

-- Partial pattern: same donor + amount as one of their RECURRING gifts, ~1 month apart.
partial_break as (

    select distinct
        o.gift_id, o.donor_id, o.gift_date, o.amount,
        'partial' as pattern
    from gifts as o
    inner join gifts as r
        on  r.donor_id  = o.donor_id
        and r.amount    = o.amount
        and r.gift_type = 'recurring'
        and abs({{ dbt.datediff('r.gift_date', 'o.gift_date', 'day') }}) between 25 and 35
    where o.gift_type = 'one_time'

),

-- Full pattern: 3+ one_time gifts of the identical amount at ~monthly intervals.
one_time_gaps as (

    select
        gift_id, donor_id, gift_date, amount,
        {{ dbt.datediff(
            'lag(gift_date) over (partition by donor_id, amount order by gift_date, gift_id)',
            'gift_date', 'day') }} as days_since_prev_same_amount
    from gifts
    where gift_type = 'one_time'

),

monthly_runs as (

    -- 2+ monthly gaps = 3+ gifts on a monthly rhythm
    select donor_id, amount
    from one_time_gaps
    where days_since_prev_same_amount between 25 and 35
    group by donor_id, amount
    having count(*) >= 2

),

full_break as (

    select g.gift_id, g.donor_id, g.gift_date, g.amount, 'full' as pattern
    from one_time_gaps as g
    inner join monthly_runs as m
        on m.donor_id = g.donor_id and m.amount = g.amount

)

select * from partial_break
union all
select * from full_break
{% endmacro %}
