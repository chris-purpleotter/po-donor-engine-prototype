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

{%- set as_of_sql = "cast('" ~ var('as_of') ~ "' as date)" -%}

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
    from {{ ref('pocore_mtr__person_giving_year') }}

),

-- (Named differently from its column: BigQuery reads `select current_year from current_year`
-- as the whole row, not the column.)
bounds as (
    select {{ pocore_fiscal_year(as_of_sql) }} as current_year
),

cohort_sizes as (

    select cohort_year, count(distinct person_id) as cohort_size
    from person_years
    group by cohort_year

),

-- Every cohort x every year from its acquisition to now (including years nobody gave).
cohort_years as (

    select
        c.cohort_year,
        cast(c.cohort_year + (s.generated_number - 1) as {{ dbt.type_int() }}) as fiscal_year,
        c.cohort_size,
        b.current_year
    from cohort_sizes as c
    cross join ({{ dbt.generate_series(200) }}) as s
    cross join bounds as b
    where c.cohort_year + (s.generated_number - 1) <= b.current_year

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
    cy.cohort_year,
    cy.fiscal_year,
    cy.fiscal_year - cy.cohort_year                                     as years_since_acquisition,
    cy.cohort_size,
    coalesce(s.total_donors, 0)                                         as total_donors,
    coalesce(s.new_donors, 0)                                           as new_donors,
    coalesce(s.second_year_donors, 0)                                   as second_year_donors,
    coalesce(s.continuing_donors, 0)                                    as continuing_donors,
    coalesce(s.reactivated_donors, 0)                                   as reactivated_donors,
    coalesce(s.reactivated_second_year_donors, 0)                       as reactivated_second_year_donors,
    cast(coalesce(s.total_donors, 0) as {{ dbt.type_float() }}) / cy.cohort_size as pct_of_cohort,
    coalesce(s.revenue, 0)                                              as revenue,
    (cy.fiscal_year = cy.current_year)                                  as is_partial_year
from cohort_years as cy
left join status_counts as s
    on  s.cohort_year = cy.cohort_year
    and s.fiscal_year = cy.fiscal_year
