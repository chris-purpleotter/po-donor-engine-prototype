{#
  pode_srv__project_health — ONE ROW PER CHECK (per year for finance_match).
  Things that are ALLOWED (they pass the dbt tests) but need a human look: sign-off totals,
  stale or patchy loads, broken recurring linking, segments that select nobody.
  The dbt tests stop the build on broken data; this table doesn't repeat them.

    status   ok | warn | info (info = context, no threshold)
    value    the measured number;  threshold = where 'warn' starts (null for info)
  Every row also carries the run context (as_of, fiscal year start, modules on), so a
  screenshot says which settings produced it.
#}

{%- set as_of_sql = "cast('" ~ var('as_of') ~ "' as date)" -%}
{%- set float = dbt.type_float() -%}
{%- set str = dbt.type_string() -%}
{%- set lookback = var('snapshot_lookback_months') | int -%}
{%- set finance_model = var('finance_totals_model', none) -%}
{%- set tolerance = var('finance_tolerance_pct') | float -%}
{%- set modules_on = [] -%}
{#- keep in step with the known modules in pode_module_enabled -#}
{%- for m in ['sustainers'] -%}
    {%- if pode_module_enabled(m) %}{% do modules_on.append(m) %}{% endif -%}
{%- endfor -%}
{#- latest COMPLETE month: the month that ends on or before as_of -#}
{%- set last_complete_month_sql = "cast(" ~ dbt.dateadd('month', -1, dbt.date_trunc('month', dbt.dateadd('day', 1, as_of_sql))) ~ " as date)" -%}

with gifts as (
    select * from {{ ref('pode_can__gifts') }}
),

gifts_to_as_of as (
    select * from gifts where gift_date <= {{ as_of_sql }}
),

monthly as (
    select
        cast({{ dbt.date_trunc('month', 'gift_date') }} as date)                       as gift_month,
        count(*)                                                                         as gifts,
        count(case when not is_refund then 1 end)                                        as real_gifts,
        count(case when not is_refund and gift_type = 'recurring' then 1 end)            as recurring_gifts
    from gifts_to_as_of
    group by cast({{ dbt.date_trunc('month', 'gift_date') }} as date)
),

-- Months in the lookback, from the first gift month on (earlier months aren't "gaps").
month_spine as (
    select cast({{ dbt.dateadd('month', '-(cast(s.generated_number as ' ~ dbt.type_int() ~ ') - 1)', dbt.date_trunc('month', as_of_sql)) }} as date) as gift_month
    from ({{ dbt.generate_series(lookback) }}) as s
),

empty_months as (
    select count(*) as n
    from month_spine as s
    left join monthly as m on m.gift_month = s.gift_month
    where m.gift_month is null
      and s.gift_month >= (select min(gift_month) from monthly)
),

recurring_share as (
    select
        max(case when gift_month = {{ last_complete_month_sql }}
                 then cast(recurring_gifts as {{ float }}) / nullif(real_gifts, 0) end)        as latest_share,
        cast(sum(case when gift_month <  {{ last_complete_month_sql }}
                       and gift_month >= cast({{ dbt.dateadd('month', -12, last_complete_month_sql) }} as date)
                      then recurring_gifts end) as {{ float }})
          / nullif(sum(case when gift_month <  {{ last_complete_month_sql }}
                             and gift_month >= cast({{ dbt.dateadd('month', -12, last_complete_month_sql) }} as date)
                            then real_gifts end), 0)                                          as prior_12m_share
    from monthly
),

unlinked as (
    select count(distinct gift_id) as n
    from ({{ pode_suspected_unlinked_recurring_sql(ref('pode_can__gifts')) }}) as u
),

last_12m as (
    select
        sum(amount)                                                                      as net_all,
        sum(case when is_kpi_eligible then amount end)                                   as net_eligible,
        count(distinct case when is_kpi_eligible and not is_refund then donor_id end)    as active_donors
    from gifts_to_as_of
    where gift_date > cast({{ dbt.dateadd('month', -12, as_of_sql) }} as date)
),

latest_members as (
    select segment_id, count(*) as n
    from {{ ref('pode_seg__membership') }}
    where snapshot_date = (select max(snapshot_date) from {{ ref('pode_seg__membership') }})
    group by segment_id
),

all_segments as (
    {%- for s in pode_all_segments() %}
    select '{{ s.id }}' as segment_id {% if not loop.last %}union all{% endif %}
    {%- endfor %}
),

empty_segments as (
    select
        count(*)                                                                         as n,
        {{ dbt.listagg('a.segment_id', "', '", 'order by a.segment_id') }}               as ids
    from all_segments as a
    left join latest_members as m on m.segment_id = a.segment_id
    where m.segment_id is null
),

{%- if finance_model %}
engine_by_year as (
    select {{ pode_fiscal_year('gift_date') }} as giving_year, sum(amount) as engine_net
    from gifts
    group by {{ pode_fiscal_year('gift_date') }}
),

finance as (
    select
        f.giving_year,
        cast(f.finance_revenue as {{ float }})                                           as finance_revenue,
        cast(coalesce(e.engine_net, 0) as {{ float }})                                   as engine_net
    from {{ ref(project_name, finance_model) }} as f
    left join engine_by_year as e
        on e.giving_year = f.giving_year
),
{%- endif %}

checks as (

    select 'data_freshness' as check_id, 'all' as scope,
           'Days between the latest gift (on or before as_of) and as_of' as description,
           cast({{ dbt.datediff('max(gift_date)', as_of_sql, 'day') }} as {{ float }}) as value,
           cast(45 as {{ float }}) as threshold,
           case when {{ dbt.datediff('max(gift_date)', as_of_sql, 'day') }} > 45 then 'warn' else 'ok' end as status,
           'latest gift ' || cast(max(gift_date) as {{ str }}) as detail
    from gifts_to_as_of

    union all
    select 'gifts_after_as_of', 'all',
           'Gifts dated after as_of (in reconciliation, ignored by every metric)',
           cast(count(*) as {{ float }}), cast(null as {{ float }}), 'info',
           cast(null as {{ str }})
    from gifts where gift_date > {{ as_of_sql }}

    union all
    select 'months_without_gifts', 'all',
           'Months in the lookback (from the first gift on) with no gifts at all',
           cast(n as {{ float }}), cast(0 as {{ float }}),
           case when n > 0 then 'warn' else 'ok' end,
           cast(null as {{ str }})
    from empty_months

    union all
    select 'recurring_share_drop', 'all',
           'Recurring share of gifts in the latest complete month, relative to the 12 months before (1 = same)',
           latest_share / nullif(prior_12m_share, 0), cast(0.5 as {{ float }}),
           case when prior_12m_share is null or prior_12m_share = 0 then 'info'
                when coalesce(latest_share, 0) / prior_12m_share < 0.5 then 'warn'
                else 'ok' end,
           case when prior_12m_share is null or prior_12m_share = 0 then 'no recurring giving in the prior 12 months'
                else 'latest ' || cast(round(cast(latest_share as numeric), 3) as {{ str }})
                     || ' vs prior ' || cast(round(cast(prior_12m_share as numeric), 3) as {{ str }}) end
    from recurring_share

    union all
    select 'suspected_unlinked_recurring', 'all',
           'One-time gifts that look like monthly payments (schedule linking may be broken)',
           cast(n as {{ float }}), cast(0 as {{ float }}),
           case when n > 0 then 'warn' else 'ok' end,
           cast(null as {{ str }})
    from unlinked

    union all
    select 'eligible_share_12m', 'all',
           'KPI-eligible share of net revenue, last 12 months',
           cast(net_eligible as {{ float }}) / nullif(cast(net_all as {{ float }}), 0),
           cast(null as {{ float }}), 'info', cast(null as {{ str }})
    from last_12m

    union all
    select 'active_donors_12m', 'all',
           'Donors with a real KPI-eligible gift in the last 12 months',
           cast(active_donors as {{ float }}), cast(null as {{ float }}), 'info', cast(null as {{ str }})
    from last_12m

    union all
    select 'donors_total', 'all', 'Donors in the canonical input',
           cast(count(*) as {{ float }}), cast(null as {{ float }}), 'info', cast(null as {{ str }})
    from {{ ref('pode_can__donors') }}

    union all
    select 'gifts_total', 'all', 'Gifts in the canonical input (all dates)',
           cast(count(*) as {{ float }}), cast(null as {{ float }}), 'info', cast(null as {{ str }})
    from gifts

    union all
    select 'empty_segments', 'all',
           'Segments with no donors at the latest month-end',
           cast(n as {{ float }}), cast(0 as {{ float }}),
           case when n > 0 then 'warn' else 'ok' end,
           ids
    from empty_segments

    union all
    {%- if finance_model %}
    select 'finance_match', cast(giving_year as {{ str }}),
           'Engine net revenue (all gifts) vs finance-reported revenue, % difference',
           100 * (engine_net - finance_revenue) / nullif(finance_revenue, 0),
           cast({{ tolerance }} as {{ float }}),
           case when abs(100 * (engine_net - finance_revenue) / nullif(finance_revenue, 0)) > {{ tolerance }}
                then 'warn' else 'ok' end,
           'engine ' || cast(round(cast(engine_net as numeric), 0) as {{ str }})
               || ' vs finance ' || cast(round(cast(finance_revenue as numeric), 0) as {{ str }})
    from finance
    {%- else %}
    select 'finance_match', 'all',
           'Engine net revenue vs finance-reported revenue',
           cast(null as {{ float }}), cast(null as {{ float }}), 'info',
           'not supplied: set var finance_totals_model to a (giving_year, finance_revenue) model or seed'
    {%- endif %}

)

select
    checks.*,
    {{ as_of_sql }}                                                     as as_of,
    {{ var('fiscal_year_start_month') }}                                as fiscal_year_start_month,
    '{{ modules_on | join(", ") }}'                                     as modules_on
from checks
