{{ config(enabled=pode_module_enabled('sustainers')) }}

{#
  pode_srv__sustainer_ltv — ONE ROW PER START COHORT x SLICE.

    start_cohort   fiscal year of the first recurring payment, or 'all'
    slice_by       'all' or 'acquisition_channel';  slice = the channel ('all' when slice_by = 'all')

    sustainers_started        donors whose first recurring payment fell in the cohort
    survival_m<N>             share still giving in month N, among those who have REACHED month N
    sustainers_reached_<N>m   how many starters have reached month N (the base for ltv_<N>m)
    ltv_<N>m                  average recurring revenue per starter through month N
                              = sum over months 1..N of (revenue that month / starters observed that month).
                              Null until at least one starter has reached month N: never extrapolated.

  Cost (only when the client lists acquisition_cost in donors_extra_columns; otherwise null):
    paid_sustainers           starters with acquisition_cost > 0
    acquisition_cost          their total cost
    cost_per_new_sustainer    acquisition_cost / paid_sustainers (CPA; unpaid starters don't dilute it)
    paid_ltv_<N>m             ltv_<N>m over paid starters only
    ltv_to_cpa_<N>m           paid_ltv_<N>m / cost_per_new_sustainer: both sides are paid sustainers.
                              Read it as "N-month revenue returned per $1 of acquisition cost".

  The 'all' cohort mixes years: later months come only from older cohorts.
#}

{%- set survival_months = var('sustainer_survival_months') -%}
{%- set horizons = var('sustainer_ltv_horizons_months') -%}
{%- set has_cost = 'acquisition_cost' in var('donors_extra_columns') -%}
{%- set float = dbt.type_float() -%}

with sustainer_months as (

    select * from {{ ref('pode_mtr__sustainer_month') }}

),

donors as (

    select
        d.donor_id,
        coalesce(d.acquisition_channel, 'unknown')                           as acquisition_channel,
        {%- if has_cost %}
        cast(a.attr_acquisition_cost as {{ float }})                         as acquisition_cost
        {%- else %}
        cast(null as {{ float }})                                            as acquisition_cost
        {%- endif %}
    from {{ ref('pode_can__donors') }} as d
    {%- if has_cost %}
    left join {{ ref('pode_can__donor_attributes') }} as a
        on a.donor_id = d.donor_id
    {%- endif %}

),

tagged as (

    select
        sm.*,
        cast(sm.start_year as {{ dbt.type_string() }})   as start_year_label,
        d.acquisition_channel,
        d.acquisition_cost
    from sustainer_months as sm
    inner join donors as d
        on d.donor_id = sm.donor_id

),

-- Every row counted in four groupings: (cohort | all) x (whole | by channel).
expanded as (
    {%- set groupings = [
        ('start_year_label', "'all'", "'all'"),
        ('start_year_label', "'acquisition_channel'", 'acquisition_channel'),
        ("'all'", "'all'", "'all'"),
        ("'all'", "'acquisition_channel'", 'acquisition_channel'),
    ] %}
    {%- for cohort_sql, slice_by, slice_sql in groupings %}
    {% if not loop.first %}union all{% endif %}
    select {{ cohort_sql }} as start_cohort, {{ slice_by }} as slice_by, {{ slice_sql }} as slice,
           donor_id, month_number, gave, amount, is_observed, acquisition_cost
    from tagged
    {%- endfor %}
),

starters as (

    select
        start_cohort, slice_by, slice,
        count(*)                                                                  as sustainers_started,
        count(case when acquisition_cost > 0 then 1 end)                          as paid_sustainers,
        sum(case when acquisition_cost > 0 then acquisition_cost end)             as acquisition_cost
    from expanded
    where month_number = 1
    group by start_cohort, slice_by, slice

),

month_stats as (

    select
        start_cohort, slice_by, slice, month_number,
        count(*)                                                    as observed,
        count(case when gave then 1 end)                            as gave,
        sum(amount)                                                 as revenue,
        -- the same, paid starters only (for LTV:CPA on a like-for-like basis)
        count(case when acquisition_cost > 0 then 1 end)            as observed_paid,
        sum(case when acquisition_cost > 0 then amount end)         as revenue_paid
    from expanded
    where is_observed
    group by start_cohort, slice_by, slice, month_number

),

curves as (

    select
        start_cohort, slice_by, slice,
        {%- for n in survival_months %}
        max(case when month_number = {{ n }} then cast(gave as {{ float }}) / observed end)   as survival_m{{ n }},
        {%- endfor %}
        {%- for h in horizons %}
        coalesce(max(case when month_number = {{ h }} then observed end), 0)              as sustainers_reached_{{ h }}m,
        -- observation is monotone (reaching month h means months 1..h-1 were reached too),
        -- so month h observed => every term in the sum exists
        case when max(case when month_number = {{ h }} then observed end) > 0
             then sum(case when month_number <= {{ h }} then cast(revenue as {{ float }}) / observed end)
        end                                                                               as ltv_{{ h }}m,
        case when max(case when month_number = {{ h }} then observed_paid end) > 0
             then sum(case when month_number <= {{ h }} and observed_paid > 0
                           then cast(revenue_paid as {{ float }}) / observed_paid end)
        end                                                                               as paid_ltv_{{ h }}m{{ ',' if not loop.last }}
        {%- endfor %}
    from month_stats
    group by start_cohort, slice_by, slice

),

joined as (

    select
        s.start_cohort,
        s.slice_by,
        s.slice,
        s.sustainers_started,
        {%- for n in survival_months %}
        c.survival_m{{ n }},
        {%- endfor %}
        {%- for h in horizons %}
        coalesce(c.sustainers_reached_{{ h }}m, 0)                                    as sustainers_reached_{{ h }}m,
        c.ltv_{{ h }}m,
        {%- endfor %}
        {%- if has_cost %}
        s.paid_sustainers,
        s.acquisition_cost,
        cast(s.acquisition_cost as {{ float }}) / nullif(s.paid_sustainers, 0)       as cost_per_new_sustainer,
        {%- for h in horizons %}
        c.paid_ltv_{{ h }}m{{ ',' if not loop.last }}
        {%- endfor %}
        {%- else %}
        cast(null as {{ dbt.type_int() }})                                           as paid_sustainers,
        cast(null as {{ float }})                                                    as acquisition_cost,
        cast(null as {{ float }})                                                    as cost_per_new_sustainer,
        {%- for h in horizons %}
        cast(null as {{ float }})                                                    as paid_ltv_{{ h }}m{{ ',' if not loop.last }}
        {%- endfor %}
        {%- endif %}
    from starters as s
    left join curves as c
        on  c.start_cohort = s.start_cohort
        and c.slice_by     = s.slice_by
        and c.slice        = s.slice

)

select
    *,
    {%- for h in horizons %}
    paid_ltv_{{ h }}m / nullif(cost_per_new_sustainer, 0)                             as ltv_to_cpa_{{ h }}m{{ ',' if not loop.last }}
    {%- endfor %}
from joined
