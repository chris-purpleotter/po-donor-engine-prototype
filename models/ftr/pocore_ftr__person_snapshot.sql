{#
  pocore_ftr__person_snapshot — one row per person per month-end snapshot date. Every value is computed AS OF that date, from
  KPI-eligible gifts only (SPEC §5, D6). This column list is the menu for segment rules.

  Design (simple on purpose):
    1. snapshot_dates : the last N month-ends up to as_of (dbt.date_spine, portable)
    2. donor_dates    : every donor x every snapshot date after they existed
    3. per_snapshot   : join gifts dated on/before each snapshot; aggregate with plain sums
    4. final select   : D6 flags and lifecycle stage

  Trade-off: each donor's gifts are scanned once per snapshot (fine at nonprofit
  scale). An incremental/windowed version is a later optimization (SPEC §5).

  Vars: as_of (required), snapshot_lookback_months, recurring_active_days.
#}

{%- set lookback_months = var('snapshot_lookback_months') | int -%}
{%- set recurring_active_days = var('recurring_active_days') | int -%}
{%- set as_of_sql = "cast('" ~ var('as_of') ~ "' as date)" -%}
{%- set first_month_sql = dbt.dateadd('month', -(lookback_months - 1), dbt.date_trunc('month', as_of_sql)) -%}
{%- set after_last_month_sql = dbt.dateadd('month', 1, dbt.date_trunc('month', as_of_sql)) -%}

with month_starts as (

    -- One row per month start; the end date is exclusive, so pass the month AFTER as_of.
    {{ dbt.date_spine('month', first_month_sql, after_last_month_sql) }}

),

-- Step 1: snapshot dates = month-ends on or before as_of (never a future date).
snapshot_dates as (

    select cast({{ dbt.last_day('cast(date_month as date)', 'month') }} as date) as snapshot_date
    from month_starts
    where cast({{ dbt.last_day('cast(date_month as date)', 'month') }} as date) <= {{ as_of_sql }}

),

-- Step 2: every donor at every snapshot date after their record existed.
donor_dates as (

    select d.person_id, s.snapshot_date
    from {{ ref('pocore_can__people') }} as d
    cross join snapshot_dates as s
    where d.created_at <= s.snapshot_date

),

-- KPI-eligible gifts, with the reactivation flag from pocore_ftr__gift_flags
-- (a positive gift more than 365 days after the person's previous positive gift).
gifts as (

    select
        g.person_id, g.gift_id, g.gift_date, g.amount, g.gift_type, g.is_refund,
        f.is_reactivation_gift as is_reactivation
    from {{ ref('pocore_can__gifts') }} as g
    inner join {{ ref('pocore_ftr__gift_flags') }} as f on f.gift_id = g.gift_id
    where g.is_kpi_eligible

),

first_gift as (

    select person_id, gift_date as first_gift_date, amount as first_gift_amount
    from (
        select
            person_id, gift_date, amount,
            row_number() over (partition by person_id order by gift_date, gift_id) as rn
        from gifts
        where not is_refund
    ) as ranked
    where rn = 1

),

-- Step 3: everything about each donor's giving up to each snapshot date.
-- Counts use positive gifts; amounts are net of refunds; recency ignores refunds (D6).
per_snapshot as (

    select
        dd.person_id,
        dd.snapshot_date,

        max(case when not g.is_refund then g.gift_date end)                          as last_gift_date,
        max(case when not g.is_refund and g.gift_type = 'recurring' then g.gift_date end) as last_recurring_date,
        max(case when g.is_reactivation then g.gift_date end)                        as last_reactivation_date,

        count(case when not g.is_refund then 1 end)                                  as gift_count_lifetime,
        coalesce(sum(g.amount), 0)                                                   as net_giving_lifetime,

        count(case when not g.is_refund
                    and g.gift_date > {{ dbt.dateadd('month', -12, 'dd.snapshot_date') }} then 1 end) as gift_count_12m,
        coalesce(sum(case when g.gift_date > {{ dbt.dateadd('month', -12, 'dd.snapshot_date') }}
                          then g.amount end), 0)                                     as net_giving_12m,

        coalesce(sum(case when extract(year from g.gift_date) = extract(year from dd.snapshot_date)
                          then g.amount end), 0)                                     as net_giving_ytd,
        count(case when not g.is_refund
                    and extract(year from g.gift_date) = extract(year from dd.snapshot_date) then 1 end) as gift_count_ytd,

        coalesce(sum(case when extract(year from g.gift_date) = extract(year from dd.snapshot_date) - 1
                          then g.amount end), 0)                                     as net_giving_prior_year,
        count(case when not g.is_refund
                    and extract(year from g.gift_date) = extract(year from dd.snapshot_date) - 1 then 1 end) as gift_count_prior_year

    from donor_dates as dd
    left join gifts as g
        on  g.person_id  = dd.person_id
        and g.gift_date <= dd.snapshot_date
    group by dd.person_id, dd.snapshot_date

),

with_days as (

    select
        ps.*,
        case when fg.first_gift_date <= ps.snapshot_date then fg.first_gift_date end   as first_gift_date,
        case when fg.first_gift_date <= ps.snapshot_date then fg.first_gift_amount end as first_gift_amount,
        {{ dbt.datediff('ps.last_gift_date', 'ps.snapshot_date', 'day') }}             as days_since_last_gift,
        case when fg.first_gift_date <= ps.snapshot_date                               -- null until the first gift happens
             then {{ dbt.datediff('fg.first_gift_date', 'ps.snapshot_date', 'day') }} end as days_since_first_gift,
        {{ dbt.datediff('ps.last_recurring_date', 'ps.snapshot_date', 'day') }}        as days_since_last_recurring,
        {{ dbt.datediff('ps.last_reactivation_date', 'ps.snapshot_date', 'day') }}     as days_since_reactivation
    from per_snapshot as ps
    left join first_gift as fg on fg.person_id = ps.person_id

),

-- Step 4: flags (D6).
flagged as (

    select
        w.*,
        (w.days_since_last_recurring is not null
            and w.days_since_last_recurring <= {{ recurring_active_days }})          as is_recurring_active,
        (w.first_gift_date is not null and w.days_since_first_gift <= 90)            as is_new_donor,
        (w.days_since_reactivation is not null and w.days_since_reactivation <= 365) as is_reactivated
    from with_days as w

)

select
    f.person_id,
    f.snapshot_date,

    -- donor attributes (current values, allowed under D7)
    d.created_at,
    d.person_type,
    d.is_deceased,
    d.region,
    d.acquisition_channel,
    d.acquisition_theme,

    -- first gift
    f.first_gift_date,
    f.days_since_first_gift,                                    -- building block: custom "new" rules
    f.first_gift_amount,
    case
        when f.first_gift_amount is null then null
        when f.first_gift_amount < 25    then '<25'
        when f.first_gift_amount < 100   then '25-99'
        when f.first_gift_amount < 250   then '100-249'
        when f.first_gift_amount < 1000  then '250-999'
        else '1000+'
    end                                                         as first_gift_band,
    extract(year from f.first_gift_date)                        as first_gift_year,

    -- recency
    f.last_gift_date,
    extract(year from f.last_gift_date)                         as last_gift_year,
    f.days_since_last_gift,

    -- giving totals
    f.gift_count_12m,
    f.net_giving_12m,
    f.gift_count_lifetime,
    f.net_giving_lifetime,
    f.net_giving_ytd,
    f.net_giving_prior_year,
    (f.gift_count_prior_year > 0 and f.gift_count_ytd = 0)      as gave_prior_year_not_ytd,

    -- flags (and the building block behind the sustainer heuristic)
    f.is_new_donor,
    f.is_reactivated,
    f.is_recurring_active,
    f.days_since_last_recurring,                                -- building block: custom sustainer windows

    -- lifecycle stage (D6: first match wins)
    case
        when f.is_recurring_active          then 'sustainer'
        when f.is_new_donor                 then 'new'
        when f.days_since_last_gift <= 365  then 'active'
        when f.days_since_last_gift <= 730  then 'lapsed'
        when f.last_gift_date is not null   then 'deep_lapsed'
        else 'prospect'
    end                                                         as lifecycle_stage
    {#- Client-chosen donor attributes (SPEC §6.5): usable in segment rules and breakdowns.
        (A Jinja comment, not SQL `--`: the trimmed comma below would otherwise land inside it.) #}
    {%- for c in var('people_extra_columns') %},
    da.attr_{{ c }}
    {%- endfor %}

from flagged as f
inner join {{ ref('pocore_can__people') }} as d
    on d.person_id = f.person_id
left join {{ ref('pocore_can__person_attributes') }} as da
    on da.person_id = f.person_id
