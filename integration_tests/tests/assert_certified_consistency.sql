-- Certified tables must agree with each other and with foundation (DESIGN §6.2). Zero rows = pass.
--   1. pocore__year = sums of pocore__person__year, per fiscal year (movement module)
--   2. pocore_foundation__gift ties exactly to the gifts input (every gift once)
--   3. pocore__group people_in_group = membership rows at the latest month-end
--   4. pocore__cohort__age__breakdown adds up to pocore__cohort__age (cohort module)

with year_check as (
{%- if po_core.pocore_client_config__module_enabled('movement') %}
    select y.fiscal_year
    from {{ ref('pocore__year') }} as y
    left join (
        select
            fiscal_year,
            count(case when gave then 1 end)                          as total_donors,
            count(case when movement_status = 'New' then 1 end)       as new_donors,
            count(case when movement_status = 'Lost' then 1 end)      as lost_donors,
            sum(amount_given)                                         as revenue
        from {{ ref('pocore__person__year') }}
        group by fiscal_year
    ) as p on p.fiscal_year = y.fiscal_year
    where coalesce(p.total_donors, 0) != y.total_donors
       or coalesce(p.new_donors, 0)   != y.new_donors
       or coalesce(p.lost_donors, 0)  != y.lost_donors
       or abs(coalesce(p.revenue, 0) - y.revenue) > 0.001
{%- else %}
    select cast(null as {{ dbt.type_int() }}) as fiscal_year where 1 = 0
{%- endif %}
),

gift_check as (
    select 1 as problem
    from (select count(*) as n, sum(amount) as amt from {{ ref('pocore_foundation__gift') }}) as f
    cross join (select count(*) as n, sum(amount) as amt from {{ ref('pocore_input__gifts') }}) as c
    where f.n != c.n or abs(f.amt - c.amt) > 0.001
),

group_check as (
    select s.group_id
    from {{ ref('pocore__group') }} as s
    left join (
        select group_id, count(*) as n
        from {{ ref('pocore_group__membership__month') }}
        where month_end_date = (select max(month_end_date) from {{ ref('pocore_group__membership__month') }})
        group by group_id
    ) as m on m.group_id = s.group_id
    where coalesce(m.n, 0) != s.people_in_group
)

{%- if po_core.pocore_client_config__module_enabled('cohort') %},

cohort_check as (
    select c.cohort_year, c.age_months
    from {{ ref('pocore__cohort__age') }} as c
    inner join (
        select cohort_year, age_months,
               sum(sustainers_started) as started, sum(sustainers_observed) as observed,
               sum(sustainers_giving) as giving, sum(revenue) as revenue
        from {{ ref('pocore__cohort__age__breakdown') }}
        group by cohort_year, age_months
    ) as b on b.cohort_year = c.cohort_year and b.age_months = c.age_months
    where b.started != c.sustainers_started or b.observed != c.sustainers_observed
       or b.giving != c.sustainers_giving or abs(b.revenue - c.revenue) > 0.001
)
{%- endif %}

-- uncapped revenue can never be below capped revenue
select 'uncapped < capped revenue' as check_name, cast(group_id as {{ dbt.type_string() }}) as detail
from {{ ref('pocore__group__month') }}
where revenue_per_person_uncapped_365d < revenue_per_person_365d - 0.001
   or revenue_per_person_uncapped_90d  < revenue_per_person_90d  - 0.001
union all
select 'year vs person_year' as check_name, cast(fiscal_year as {{ dbt.type_string() }}) as detail from year_check
union all select 'foundation gift vs input', null from gift_check
union all select 'group size vs membership', group_id from group_check
{%- if po_core.pocore_client_config__module_enabled('cohort') %}
union all select 'cohort breakdown vs cohort', cast(cohort_year as {{ dbt.type_string() }}) from cohort_check
{%- endif %}
