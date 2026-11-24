{#
  pocore_rollup__person__month_end_lookback — one row per person per month-end snapshot date. Every value is computed AS OF that date, from
  KPI-eligible gifts only (SPEC §5, D6). This column list is the menu for group rules.

  Design (simple on purpose):
    1. snapshot_dates : the last N month-ends up to as_of (dbt.date_spine, portable)
    2. donor_dates    : every donor x every snapshot date after they existed
    3. per_snapshot   : join gifts dated on/before each snapshot; aggregate with plain sums
    4. final select   : D6 flags and lifecycle stage

  Trade-off: each donor's gifts are scanned once per snapshot (fine at nonprofit
  scale). An incremental/windowed version is a later optimization (SPEC §5).

  Gifts come ONLY from pocore_event__gift (the gift's columns + the engine's definitions),
  never from pocore_input__gifts. Custom rollups (var `rollups`, macro pocore_client_config__rollups) are
  generated into the same pass over gifts as rollup_* columns.

  Vars: as_of (required), snapshot_lookback_months, recurring_active_days, rollups.
#}
{%- set lookback_months = var("snapshot_lookback_months") | int -%}
{%- set recurring_active_days = var("recurring_active_days") | int -%}
{%- set rollups = pocore_client_config__rollups() -%}
{%- set first_month_sql = dbt.dateadd(
    "month",
    -(lookback_months - 1),
    dbt.date_trunc("month", pocore_client_config__as_of_date()),
) -%}
{%- set after_last_month_sql = dbt.dateadd(
    "month", 1, dbt.date_trunc("month", pocore_client_config__as_of_date())
) -%}

with
    -- Inputs: people from the entity layer, gifts from the event layer (never input)
    pocore_entity__person as (select * from {{ ref("pocore_entity__person") }}),

    pocore_event__gift as (select * from {{ ref("pocore_event__gift") }}),

    month_starts as (

        {{ dbt.date_spine("month", first_month_sql, after_last_month_sql) }}

    ),

    -- Step 1: snapshot dates = month-ends on or before as_of (never a future date).
    snapshot_dates as (

        select
            cast(
                {{ dbt.last_day("cast(date_month as date)", "month") }} as date
            ) as snapshot_date
        from month_starts
        where
            cast({{ dbt.last_day("cast(date_month as date)", "month") }} as date)
            <= {{ pocore_client_config__as_of_date() }}

    ),

    -- Step 2: every donor at every snapshot date after their record existed.
    donor_dates as (

        select pocore_entity__person.person_id, snapshot_dates.snapshot_date
        from pocore_entity__person
        cross join snapshot_dates
        where pocore_entity__person.created_at <= snapshot_dates.snapshot_date

    ),

    -- KPI-eligible gifts (refunds included: amounts are net of them), with the engine's
    -- definitions, plus one true/false column per custom rollup's `where`.
    gifts as (

        select
            pocore_event__gift.*
            {%- for r in rollups %}{% if r.where %},
            ({{ r.where }}) as rollup_match_{{ loop.index }}
            {%- endif %}{% endfor %}
        from pocore_event__gift
        where pocore_event__gift.is_kpi_eligible

    ),

    first_gift as (

        select person_id, gift_date as first_gift_date, amount as first_gift_amount
        from gifts
        where is_first_gift

    ),

    -- Step 3: everything about each donor's giving up to each snapshot date.
    -- Counts use positive gifts; amounts are net of refunds; recency ignores refunds
    -- (D6).
    per_snapshot as (

        select
            donor_dates.person_id,
            donor_dates.snapshot_date,

            max(
                case when not gifts.is_refund then gifts.gift_date end
            ) as last_gift_date,
            max(
                case
                    when gifts.is_recurring_payment
                    then gifts.gift_date
                end
            ) as last_recurring_date,
            max(
                case when gifts.is_reactivation_gift then gifts.gift_date end
            ) as last_reactivation_date,
            count(
                case when gifts.is_reactivation_gift then 1 end
            ) as reactivations_lifetime,

            -- largest and latest gift (refunds ignored)
            max(case when not gifts.is_refund then gifts.amount end) as largest_gift_lifetime,
            max(
                case
                    when
                        not gifts.is_refund
                        and gifts.gift_date
                        > {{ dbt.dateadd("month", -12, "donor_dates.snapshot_date") }}
                    then gifts.amount
                end
            ) as largest_gift_12m,
            max(
                case when not gifts.is_refund then gifts.gift_number end
            ) as last_gift_number,

            count(case when not gifts.is_refund then 1 end) as gift_count_lifetime,
            coalesce(sum(gifts.amount), 0) as net_giving_lifetime,

            count(
                case
                    when
                        not gifts.is_refund
                        and gifts.gift_date
                        > {{ dbt.dateadd("month", -12, "donor_dates.snapshot_date") }}
                    then 1
                end
            ) as gift_count_12m,
            coalesce(
                sum(
                    case
                        when
                            gifts.gift_date
                            > {{ dbt.dateadd("month", -12, "donor_dates.snapshot_date") }}
                        then gifts.amount
                    end
                ),
                0
            ) as net_giving_12m,

            coalesce(
                sum(
                    case
                        when
                            extract(year from gifts.gift_date)
                            = extract(year from donor_dates.snapshot_date)
                        then gifts.amount
                    end
                ),
                0
            ) as net_giving_ytd,
            count(
                case
                    when
                        not gifts.is_refund
                        and extract(year from gifts.gift_date)
                        = extract(year from donor_dates.snapshot_date)
                    then 1
                end
            ) as gift_count_ytd,

            coalesce(
                sum(
                    case
                        when
                            extract(year from gifts.gift_date)
                            = extract(year from donor_dates.snapshot_date) - 1
                        then gifts.amount
                    end
                ),
                0
            ) as net_giving_prior_year,
            count(
                case
                    when
                        not gifts.is_refund
                        and extract(year from gifts.gift_date)
                        = extract(year from donor_dates.snapshot_date) - 1
                    then 1
                end
            ) as gift_count_prior_year

            {#- Custom rollups (var `rollups`): one column each, SQL from macro pocore_sql__rollup.
                (A Jinja comment, not SQL `--`: the comma below would otherwise land inside it.) #}
            {%- for r in rollups %},
            {{ pocore_sql__rollup(r, "gifts.rollup_match_" ~ loop.index) }} as {{ r.name }}
            {%- endfor %}

        from donor_dates
        left join
            gifts
            on gifts.person_id = donor_dates.person_id
            and gifts.gift_date <= donor_dates.snapshot_date
        group by donor_dates.person_id, donor_dates.snapshot_date

    ),

    with_days as (

        select
            per_snapshot.*,
            case
                when first_gift.first_gift_date <= per_snapshot.snapshot_date
                then first_gift.first_gift_date
            end as first_gift_date,
            case
                when first_gift.first_gift_date <= per_snapshot.snapshot_date
                then first_gift.first_gift_amount
            end as first_gift_amount,
            last_gift.amount as last_gift_amount,
            {{ dbt.datediff("per_snapshot.last_gift_date", "per_snapshot.snapshot_date", "day") }}
            as days_since_last_gift,
            case
                when first_gift.first_gift_date <= per_snapshot.snapshot_date  -- null until the first gift happens
                then {{ dbt.datediff("first_gift.first_gift_date", "per_snapshot.snapshot_date", "day") }}
            end as days_since_first_gift,
            {{ dbt.datediff("per_snapshot.last_recurring_date", "per_snapshot.snapshot_date", "day") }}
            as days_since_last_recurring,
            {{ dbt.datediff("per_snapshot.last_reactivation_date", "per_snapshot.snapshot_date", "day") }}
            as days_since_reactivation
        from per_snapshot
        left join first_gift on first_gift.person_id = per_snapshot.person_id
        left join
            gifts as last_gift
            on last_gift.person_id = per_snapshot.person_id
            and last_gift.gift_number = per_snapshot.last_gift_number

    ),

    -- Step 4: flags (D6).
    flagged as (

        select
            with_days.*,
            (
                with_days.days_since_last_recurring is not null
                and with_days.days_since_last_recurring <= {{ recurring_active_days }}
            ) as is_recurring_active,
            (
                with_days.first_gift_date is not null
                and with_days.days_since_first_gift <= 90
            ) as is_new_donor,
            (
                with_days.days_since_reactivation is not null
                and with_days.days_since_reactivation <= {{ pocore_engine_config__active_days() }}
            ) as is_reactivated
        from with_days

    )

select
    flagged.person_id,
    flagged.snapshot_date,

    -- donor attributes (current values, allowed under D7)
    pocore_entity__person.created_at,
    pocore_entity__person.person_type,
    pocore_entity__person.is_deceased,
    pocore_entity__person.region,
    pocore_entity__person.acquisition_channel,
    pocore_entity__person.acquisition_theme,

    -- first gift
    flagged.first_gift_date,
    flagged.days_since_first_gift,  -- building block: custom "new" rules
    flagged.first_gift_amount,
    case
        when flagged.first_gift_amount is null
        then null
        when flagged.first_gift_amount < 25
        then '<25'
        when flagged.first_gift_amount < 100
        then '25-99'
        when flagged.first_gift_amount < 250
        then '100-249'
        when flagged.first_gift_amount < 1000
        then '250-999'
        else '1000+'
    end as first_gift_band,
    extract(year from flagged.first_gift_date) as first_gift_year,

    -- recency
    flagged.last_gift_date,
    extract(year from flagged.last_gift_date) as last_gift_year,
    flagged.days_since_last_gift,

    -- giving totals
    flagged.gift_count_12m,
    flagged.net_giving_12m,
    flagged.gift_count_lifetime,
    flagged.net_giving_lifetime,
    flagged.net_giving_ytd,
    flagged.net_giving_prior_year,

    -- largest and latest gift (refunds ignored)
    flagged.largest_gift_lifetime,
    flagged.largest_gift_12m,
    flagged.last_gift_amount,
    (
        flagged.gift_count_prior_year > 0 and flagged.gift_count_ytd = 0
    ) as gave_prior_year_not_ytd,

    -- flags (and the building block behind the sustainer heuristic)
    flagged.is_new_donor,
    flagged.is_reactivated,
    flagged.is_recurring_active,
    flagged.days_since_last_recurring,  -- building block: custom sustainer windows
    flagged.days_since_reactivation,  -- days since the latest comeback (null: never)
    flagged.reactivations_lifetime,  -- comebacks after a 12+ month gap, to date

    -- lifecycle stage (D6: first match wins). Labels: pocore_engine_config__lifecycle_stages().
    -- 365 = pocore_engine_config__active_days(): active within 12 months, lapsed the 12 months after
    -- that.
    case
        when flagged.is_recurring_active
        then 'sustainer'
        when flagged.is_new_donor
        then 'new'
        when flagged.days_since_last_gift <= {{ pocore_engine_config__active_days() }}
        then 'active'
        when flagged.days_since_last_gift <= {{ 2 * pocore_engine_config__active_days() }}
        then 'lapsed'
        when flagged.last_gift_date is not null
        then 'deep_lapsed'
        else 'prospect'
    end as lifecycle_stage
    {#- Client-chosen donor attributes (SPEC §6.5): usable in group rules and breakdowns.
        (A Jinja comment, not SQL `--`: the trimmed comma below would otherwise land inside it.) #}
    {%- for c in var("people_extra_columns") %}, pocore_entity__person.attr_{{ c }} {%- endfor %}
    {#- Custom rollups (var `rollups`, macro pocore_client_config__rollups). #}
    {%- for r in rollups %}, flagged.{{ r.name }} {%- endfor %}

from flagged
inner join pocore_entity__person on pocore_entity__person.person_id = flagged.person_id
