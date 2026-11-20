{#
  pocore__year — ONE ROW PER FISCAL YEAR (the whole file): the donor movement funnel.

    total_donors = new + second_year + continuing + reactivated + reactivated_second_year
    and it balances:  this year's total = last year's total - lost + new + reactivated
      (retained = second_year + continuing + reactivated_second_year)

  Rates:
    new_donor_retention = second_year / last year's new donors
    overall_retention   = retained / last year's total donors
  Flags:
    is_partial_year   the current fiscal year (year to date)
    has_full_history  5+ years of data before it, so New/Reactivated are reliable
                      (early years of any dataset over-count "New")
#}


with person_years as (

    select
        person_id,
        giving_year                         as fiscal_year,
        cohort_year,
        gifts,
        amount_given,
        previous_giving_year,
        donor_status,
        years_lapsed_before_reactivation
    from {{ ref('pocore_movement__person__year') }}

),

bounds as (

    select
        min(fiscal_year)                     as first_year,
        {{ pocore_fiscal_year(pocore_as_of_date()) }}    as current_year
    from person_years

),

-- Every year from the first gift to the current year (including years nobody gave).
years as (

    -- cast: dbt.generate_series yields decimals on some warehouses (BigQuery)
    select cast(b.first_year + (s.generated_number - 1) as {{ dbt.type_int() }}) as fiscal_year,
           b.first_year, b.current_year
    from ({{ dbt.generate_series(200) }}) as s
    cross join bounds as b
    where b.first_year + (s.generated_number - 1) <= b.current_year

),

status_counts as (

    select
        fiscal_year,
        count(*)                                                                   as total_donors,
        count(case when donor_status = 'New' then 1 end)                           as new_donors,
        count(case when donor_status = 'Second year' then 1 end)                   as second_year_donors,
        count(case when donor_status = 'Continuing' then 1 end)                    as continuing_donors,
        count(case when donor_status = 'Reactivated' then 1 end)                   as reactivated_donors,
        count(case when donor_status = 'Reactivated - second year' then 1 end)     as reactivated_second_year_donors,
        sum(amount_given)                                                          as revenue,
        sum(case when donor_status = 'New' then amount_given else 0 end)           as revenue_new,
        sum(case when donor_status <> 'New' then amount_given else 0 end)          as revenue_returning
    from person_years
    group by fiscal_year

),

-- Lost = gave last year, not this year (counted in this year).
lost as (

    select prev.fiscal_year + 1 as fiscal_year, count(*) as lost_donors
    from person_years as prev
    left join person_years as cur
        on  cur.person_id    = prev.person_id
        and cur.fiscal_year = prev.fiscal_year + 1
    where cur.person_id is null
    group by prev.fiscal_year + 1

),

assembled as (

    select
        y.fiscal_year,
        coalesce(c.total_donors, 0)                    as total_donors,
        coalesce(c.new_donors, 0)                      as new_donors,
        coalesce(c.second_year_donors, 0)              as second_year_donors,
        coalesce(c.continuing_donors, 0)               as continuing_donors,
        coalesce(c.reactivated_donors, 0)              as reactivated_donors,
        coalesce(c.reactivated_second_year_donors, 0)  as reactivated_second_year_donors,
        coalesce(l.lost_donors, 0)                     as lost_donors,
        coalesce(c.revenue, 0)                         as revenue,
        coalesce(c.revenue_new, 0)                     as revenue_new,
        coalesce(c.revenue_returning, 0)               as revenue_returning,
        (y.fiscal_year = y.current_year)               as is_partial_year,
        (y.fiscal_year - y.first_year >= 5)            as has_full_history
    from years as y
    left join status_counts as c on c.fiscal_year = y.fiscal_year
    left join lost as l          on l.fiscal_year = y.fiscal_year

)

select
    a.*,
    lag(a.total_donors) over (order by a.fiscal_year)                            as last_year_total_donors,
    -- denominators as columns, so BI tools can pool retention over several years:
    -- sum(second_year_donors) / sum(last_year_new_donors)
    lag(a.new_donors) over (order by a.fiscal_year)                              as last_year_new_donors,
    case when lag(a.new_donors) over (order by a.fiscal_year) > 0
         then cast(a.second_year_donors as {{ dbt.type_float() }})
              / lag(a.new_donors) over (order by a.fiscal_year) end              as new_donor_retention,
    case when lag(a.total_donors) over (order by a.fiscal_year) > 0
         then cast(a.second_year_donors + a.continuing_donors + a.reactivated_second_year_donors as {{ dbt.type_float() }})
              / lag(a.total_donors) over (order by a.fiscal_year) end            as overall_retention
from assembled as a
