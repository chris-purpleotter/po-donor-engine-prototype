{#
  pode_mtr__donor_giving_year — each donor's status in each (fiscal) year they gave.
  One row per donor x giving_year (years with at least one positive KPI-eligible gift).

  Status (statuses add up to all donors who gave that year):
    New                         first gift ever, or 5+ years since the previous gift
    Second year                 new last year, gave again this year
    Continuing                  gave this year and the two years before
    Reactivated                 previous gift 2-4 years ago
    Reactivated - second year   reactivated last year, gave again this year

  Individuals only (consistent with segments). Deceased donors ARE included: they gave
  in those years, and dropping them would rewrite history.
#}

{%- set as_of_sql = "cast('" ~ var('as_of') ~ "' as date)" -%}

with gifts as (

    select g.donor_id, g.gift_date, g.amount, g.is_refund
    from {{ ref('pode_can__gifts') }} as g
    inner join {{ ref('pode_can__donors') }} as d
        on d.donor_id = g.donor_id
    where g.is_kpi_eligible
      and d.donor_type = 'individual'
      and g.gift_date <= {{ as_of_sql }}

),

donor_years as (

    select
        donor_id,
        {{ pode_fiscal_year('gift_date') }}            as giving_year,
        count(case when not is_refund then 1 end)      as gifts,
        sum(amount)                                    as amount_given
    from gifts
    group by 1, 2
    -- a year counts as "gave" only with at least one real (non-refund) gift
    having count(case when not is_refund then 1 end) > 0

),

lagged as (

    select
        *,
        lag(giving_year, 1) over (partition by donor_id order by giving_year) as prev_year,
        lag(giving_year, 2) over (partition by donor_id order by giving_year) as prev_prev_year
    from donor_years

)

select
    donor_id,
    giving_year,
    -- the donor's acquisition cohort: year of their FIRST-EVER gift (never changes,
    -- even if they later count as 'New' again after a 5+ year gap)
    min(giving_year) over (partition by donor_id)                   as cohort_year,
    gifts,
    amount_given,
    prev_year                                                       as previous_giving_year,
    case
        when prev_year is null or giving_year - prev_year >= 5            then 'New'
        when giving_year - prev_year between 2 and 4                      then 'Reactivated'
        -- gave last year too: what was last year's status?
        when prev_prev_year is null or prev_year - prev_prev_year >= 5    then 'Second year'
        when prev_year - prev_prev_year between 2 and 4                   then 'Reactivated - second year'
        else 'Continuing'
    end                                                             as donor_status,
    case when giving_year - prev_year between 2 and 4
         then giving_year - prev_year end                           as years_lapsed_before_reactivation
from lagged
