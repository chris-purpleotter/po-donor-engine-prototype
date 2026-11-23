{#
  pocore__cohort__year — ONE ROW PER FIRST-GIFT COHORT x FISCAL YEAR.
  cohort_type is always 'first_gift' here (sustainer cohorts: pocore__cohort__age).
  Follows each group of donors (cohort_year = year of their first-ever gift) through the
  following years: how many still gave, and with which annual status.

    cohort_size        donors acquired in cohort_year
    total_donors       cohort members who gave in fiscal_year
                       = new + second_year + continuing + reactivated + reactivated_second_year
    pct_of_cohort      total_donors / cohort_size: the cohort's retention curve
    years_since_acquisition  0 = the acquisition year

  "New" after year 0 = cohort members back after a 5+ year gap (they keep their cohort).
  Each row is one cohort-year; don't add total_donors across years (the same donor gives
  in several years).
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

-- (Named differently from its column: BigQuery reads `select current_year from current_year`
-- as the whole row, not the column.)
bounds as (
    select {{ pocore_helpers__fiscal_year(pocore_client_config__as_of_date()) }} as current_year
),

cohort_sizes as (

    select cohort_year, count(distinct person_id) as cohort_size
    from person_years
    group by cohort_year

),

-- Every cohort x every year from its acquisition to now (including years nobody gave).
cohort_years as (

    select
        cohort_sizes.cohort_year,
        cast(cohort_sizes.cohort_year + (series.generated_number - 1) as {{ dbt.type_int() }}) as fiscal_year,
        cohort_sizes.cohort_size,
        bounds.current_year
    from cohort_sizes
    cross join ({{ dbt.generate_series(200) }}) as series
    cross join bounds
    where cohort_sizes.cohort_year + (series.generated_number - 1) <= bounds.current_year

),

status_counts as (

    select
        cohort_year,
        fiscal_year,
        count(*)                                                                   as total_donors,
        count(case when donor_status = 'New' then 1 end)                           as new_donors,
        count(case when donor_status = 'Second year' then 1 end)                   as second_year_donors,
        count(case when donor_status = 'Continuing' then 1 end)                    as continuing_donors,
        count(case when donor_status = 'Reactivated' then 1 end)                   as reactivated_donors,
        count(case when donor_status = 'Reactivated - second year' then 1 end)     as reactivated_second_year_donors,
        sum(amount_given)                                                          as revenue
    from person_years
    group by cohort_year, fiscal_year

)

select
    'first_gift'                                                        as cohort_type,
    cohort_years.cohort_year,
    cohort_years.fiscal_year,
    cohort_years.fiscal_year - cohort_years.cohort_year                                     as years_since_acquisition,
    cohort_years.cohort_size,
    coalesce(status_counts.total_donors, 0)                                         as total_donors,
    coalesce(status_counts.new_donors, 0)                                           as new_donors,
    coalesce(status_counts.second_year_donors, 0)                                   as second_year_donors,
    coalesce(status_counts.continuing_donors, 0)                                    as continuing_donors,
    coalesce(status_counts.reactivated_donors, 0)                                   as reactivated_donors,
    coalesce(status_counts.reactivated_second_year_donors, 0)                       as reactivated_second_year_donors,
    cast(coalesce(status_counts.total_donors, 0) as {{ dbt.type_float() }}) / cohort_years.cohort_size as pct_of_cohort,
    coalesce(status_counts.revenue, 0)                                              as revenue,
    (cohort_years.fiscal_year = cohort_years.current_year)                                  as is_partial_year
from cohort_years
left join status_counts
    on  status_counts.cohort_year = cohort_years.cohort_year
    and status_counts.fiscal_year = cohort_years.fiscal_year
