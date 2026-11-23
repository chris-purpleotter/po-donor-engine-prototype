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


with

pocore_movement__person__year as (select * from {{ ref('pocore_movement__person__year') }}),

person_years as (

    select
        person_id,
        giving_year                         as fiscal_year,
        cohort_year,
        gifts,
        amount_given,
        previous_giving_year,
        donor_status,
        years_lapsed_before_reactivation
    from pocore_movement__person__year

),

bounds as (

    select
        min(fiscal_year)                     as first_year,
        {{ pocore_helpers__fiscal_year(pocore_client_config__as_of_date()) }}    as current_year
    from person_years

),

-- Every year from the first gift to the current year (including years nobody gave).
years as (

    -- cast: dbt.generate_series yields decimals on some warehouses (BigQuery)
    select cast(bounds.first_year + (series.generated_number - 1) as {{ dbt.type_int() }}) as fiscal_year,
           bounds.first_year, bounds.current_year
    from ({{ dbt.generate_series(200) }}) as series
    cross join bounds
    where bounds.first_year + (series.generated_number - 1) <= bounds.current_year

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

    select last_year.fiscal_year + 1 as fiscal_year, count(*) as lost_donors
    from person_years as last_year
    left join person_years as this_year
        on  this_year.person_id    = last_year.person_id
        and this_year.fiscal_year = last_year.fiscal_year + 1
    where this_year.person_id is null
    group by last_year.fiscal_year + 1

),

assembled as (

    select
        years.fiscal_year,
        coalesce(status_counts.total_donors, 0)                    as total_donors,
        coalesce(status_counts.new_donors, 0)                      as new_donors,
        coalesce(status_counts.second_year_donors, 0)              as second_year_donors,
        coalesce(status_counts.continuing_donors, 0)               as continuing_donors,
        coalesce(status_counts.reactivated_donors, 0)              as reactivated_donors,
        coalesce(status_counts.reactivated_second_year_donors, 0)  as reactivated_second_year_donors,
        coalesce(lost.lost_donors, 0)                     as lost_donors,
        coalesce(status_counts.revenue, 0)                         as revenue,
        coalesce(status_counts.revenue_new, 0)                     as revenue_new,
        coalesce(status_counts.revenue_returning, 0)               as revenue_returning,
        (years.fiscal_year = years.current_year)               as is_partial_year,
        (years.fiscal_year - years.first_year >= 5)            as has_full_history
    from years
    left join status_counts on status_counts.fiscal_year = years.fiscal_year
    left join lost          on lost.fiscal_year = years.fiscal_year

)

select
    assembled.*,
    lag(assembled.total_donors) over (order by assembled.fiscal_year)                            as last_year_total_donors,
    -- denominators as columns, so BI tools can pool retention over several years:
    -- sum(second_year_donors) / sum(last_year_new_donors)
    lag(assembled.new_donors) over (order by assembled.fiscal_year)                              as last_year_new_donors,
    case when lag(assembled.new_donors) over (order by assembled.fiscal_year) > 0
         then cast(assembled.second_year_donors as {{ dbt.type_float() }})
              / lag(assembled.new_donors) over (order by assembled.fiscal_year) end              as new_donor_retention,
    case when lag(assembled.total_donors) over (order by assembled.fiscal_year) > 0
         then cast(assembled.second_year_donors + assembled.continuing_donors + assembled.reactivated_second_year_donors as {{ dbt.type_float() }})
              / lag(assembled.total_donors) over (order by assembled.fiscal_year) end            as overall_retention
from assembled
