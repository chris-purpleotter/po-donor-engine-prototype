{#
  pocore__person__year — ONE ROW PER PERSON x FISCAL YEAR (the donor JOURNEY), from the fiscal year the person
  first appears (created or first gift, whichever is earlier) to the current fiscal year.
  Individuals only (the same population as pocore__year and the segments); deceased people
  are kept, because they gave in those years.

  What happened in each person's year, and where they were on their journey:
    gave / gifts / amount_given   that year's KPI-eligible giving (SUMMABLE across years and people)
    movement_status               New / Second year / Continuing / Reactivated /
                                  Reactivated - second year (they gave), Lost (gave last year,
                                  not this year), Not giving (gave before, not last year or
                                  this year), Never given (no gift yet)
    stage                         lifecycle stage at stage_date: the fiscal year's last month-end
                                  (for the current year: the latest month-end)
    stage_1y_ago / _2y_ago / _3y_ago   the stage 12 / 24 / 36 months before stage_date
                                  (null before the snapshot history starts)

  The donor journey (Sankey): filter ONE fiscal_year and count people by stage_1y_ago -> stage.
  Clicking a flow gives the people behind it. Movement: counts by movement_status for one
  year match pocore__year (tested).
#}


with

pocore_foundation__person as (select * from {{ ref('pocore_foundation__person') }}),

pocore_movement__person__year as (select * from {{ ref('pocore_movement__person__year') }}),

pocore_foundation__person__month_end as (select * from {{ ref('pocore_foundation__person__month_end') }}),

people as (

    select person_id, created_at, is_deceased, region, acquisition_channel, acquisition_theme
    from pocore_foundation__person
    where person_type = 'individual'

),

giving as (

    select person_id, giving_year as fiscal_year, cohort_year, gifts, amount_given, donor_status
    from pocore_movement__person__year

),

bounds as (
    select {{ pocore_helpers__fiscal_year(pocore_client_config__as_of_date()) }} as current_year
),

starts as (

    select
        people.person_id,
        case when first_gift_years.first_gift_year is not null
                  and first_gift_years.first_gift_year < {{ pocore_helpers__fiscal_year('people.created_at') }}
             then first_gift_years.first_gift_year
             else {{ pocore_helpers__fiscal_year('people.created_at') }} end              as start_year,
        first_gift_years.first_gift_year                                                   as cohort_year
    from people
    left join (
        select person_id, min(fiscal_year) as first_gift_year
        from giving
        group by person_id
    ) as first_gift_years on first_gift_years.person_id = people.person_id

),

-- Every person x every fiscal year from their start to now.
person_years as (

    select
        starts.person_id,
        starts.cohort_year,
        cast(starts.start_year + (series.generated_number - 1) as {{ dbt.type_int() }}) as fiscal_year,
        bounds.current_year
    from starts
    cross join ({{ dbt.generate_series(200) }}) as series
    cross join bounds
    where starts.start_year + (series.generated_number - 1) <= bounds.current_year

),

-- The month-end that represents each fiscal year: its last month-end in the snapshot history.
year_dates as (

    select {{ pocore_helpers__fiscal_year('month_end_date') }} as fiscal_year, max(month_end_date) as stage_date
    from (select distinct month_end_date from pocore_foundation__person__month_end) as month_ends
    group by {{ pocore_helpers__fiscal_year('month_end_date') }}

),

stages as (

    select person_id, month_end_date, lifecycle_stage
    from pocore_foundation__person__month_end

),

with_giving as (

    select
        person_years.person_id,
        person_years.fiscal_year,
        person_years.cohort_year,
        giving.donor_status,
        coalesce(giving.gifts, 0)                                                    as gifts,
        coalesce(giving.amount_given, 0)                                             as amount_given,
        (giving.person_id is not null)                                               as gave,
        -- did they give last year / ever before this year?
        max(case when giving.person_id is not null then person_years.fiscal_year end) over (
            partition by person_years.person_id order by person_years.fiscal_year
            rows between unbounded preceding and 1 preceding)                   as last_gave_year_before,
        (person_years.fiscal_year = person_years.current_year)                                      as is_partial_year
    from person_years
    left join giving
        on  giving.person_id   = person_years.person_id
        and giving.fiscal_year = person_years.fiscal_year

)

select
    with_giving.person_id,
    with_giving.fiscal_year,
    with_giving.cohort_year,
    people.is_deceased,
    people.region,
    people.acquisition_channel,
    people.acquisition_theme,
    with_giving.gave,
    with_giving.gifts,
    with_giving.amount_given,
    case
        when with_giving.gave                                       then with_giving.donor_status
        when with_giving.last_gave_year_before = with_giving.fiscal_year - 1  then 'Lost'
        when with_giving.last_gave_year_before is not null          then 'Not giving'
        else 'Never given'
    end                                                                         as movement_status,
    year_dates.stage_date,
    stages_now.lifecycle_stage                                                  as stage,
    stages_1y_ago.lifecycle_stage                                             as stage_1y_ago,
    stages_2y_ago.lifecycle_stage                                             as stage_2y_ago,
    stages_3y_ago.lifecycle_stage                                             as stage_3y_ago,
    with_giving.is_partial_year
from with_giving
inner join people
    on people.person_id = with_giving.person_id
left join year_dates
    on year_dates.fiscal_year = with_giving.fiscal_year
left join stages as stages_now
    on stages_now.person_id = with_giving.person_id and stages_now.month_end_date = year_dates.stage_date
{%- for n in [1, 2, 3] %}
-- month-end N years earlier (month-end arithmetic: plain dateadd turns Feb 28 into Feb 28, not Feb 29)
left join stages as stages_{{ n }}y_ago
    on  stages_{{ n }}y_ago.person_id = with_giving.person_id
    and stages_{{ n }}y_ago.month_end_date = cast({{ dbt.dateadd('day', -1,
            dbt.dateadd('month', 1 - 12 * n, dbt.date_trunc('month', 'year_dates.stage_date'))) }} as date)
{%- endfor %}
