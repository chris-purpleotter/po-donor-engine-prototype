{#
  pode_srv__stage_transitions — the donor journey as stage-to-stage moves.
  ONE ROW PER from_date x horizon_months x from_stage x to_stage (combinations that occur).

  For every donor at a month-end (from_date): their lifecycle stage then, and N months later
  (to_date). "Of last year's new donors, 30% are active now, 50% lapsed, 20% sustainers."

    donors              donors who made this move
    from_stage_donors   all donors in from_stage at from_date (the denominator)
    share               donors / from_stage_donors (shares for one from_stage add up to 1)
    from/to_stage_order journey order (prospect 1, new 2, active 3, sustainer 4, lapsed 5,
                        deep_lapsed 6), for sorting in BI tools
    is_latest           the most recent from_date with a complete horizon: filter on it for
                        an always-current "last N months" view

  Pool across from_dates with sum(donors) / sum(from_stage_donors), never an average of share.
  Same population as segments: individuals, not deceased. Prospects are included, so
  prospect -> new is acquisition. 'new' lasts 90 days by definition, so over 12+ months
  nobody stays new: new -> active is the healthy path.
  Horizons: var transition_horizons_months. Only from_dates whose to_date has happened.
#}

{%- set horizons = var('transition_horizons_months') -%}
{#- journey order, so BI tools can sort stages sensibly instead of alphabetically -#}
{%- set stage_order = ['prospect', 'new', 'active', 'sustainer', 'lapsed', 'deep_lapsed'] -%}

with snapshot as (

    select donor_id, snapshot_date, lifecycle_stage
    from {{ ref('pode_ftr__donor_snapshot') }}
    where donor_type = 'individual'
      and not is_deceased

),

horizons as (
    {%- for h in horizons %}
    select {{ h }} as horizon_months {% if not loop.last %}union all{% endif %}
    {%- endfor %}
),

moves as (

    select
        f.snapshot_date                     as from_date,
        t.snapshot_date                     as to_date,
        h.horizon_months,
        f.lifecycle_stage                   as from_stage,
        t.lifecycle_stage                   as to_stage,
        f.donor_id
    from snapshot as f
    cross join horizons as h
    inner join snapshot as t
        on  t.donor_id = f.donor_id
        -- month-end + N months, as a month-end (plain dateadd turns Feb 28 + 1 month into Mar 28)
        and t.snapshot_date = cast({{ dbt.dateadd('day', -1,
                dbt.dateadd('month', 'h.horizon_months + 1', dbt.date_trunc('month', 'f.snapshot_date'))) }} as date)

),

counts as (

    select from_date, to_date, horizon_months, from_stage, to_stage, count(*) as donors
    from moves
    group by from_date, to_date, horizon_months, from_stage, to_stage

)

select
    from_date,
    to_date,
    horizon_months,
    from_stage,
    to_stage,
    case from_stage{% for st in stage_order %} when '{{ st }}' then {{ loop.index }}{% endfor %} end as from_stage_order,
    case to_stage{% for st in stage_order %} when '{{ st }}' then {{ loop.index }}{% endfor %} end   as to_stage_order,
    donors,
    sum(donors) over (partition by from_date, horizon_months, from_stage)          as from_stage_donors,
    cast(donors as {{ dbt.type_float() }})
        / sum(donors) over (partition by from_date, horizon_months, from_stage)    as share,
    (from_date = max(from_date) over (partition by horizon_months))                as is_latest
from counts
