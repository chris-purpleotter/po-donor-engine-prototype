-- Hand-calculated stage transitions (as_of = 2026-09-30). Zero rows = pass.
--
-- 12 months, 2025-09-30 -> 2026-09-30 (the latest complete 12-month pair):
--   'new' at 2025-09-30 = {D04} only (first gift 2025-09-01, 29 days; D10's first gift
--   2025-06-01 is 121 days -> active). At 2026-09-30 D04 is 394 days -> lapsed.
--   => new -> lapsed: donors 1, from_stage_donors 1, share 1.0, is_latest
-- 3 months, 2026-06-30 -> 2026-09-30 (the latest complete 3-month pair):
--   'prospect' at 2026-06-30 = {D05, D07} (no gifts yet; D08 is an organization, D09 deceased).
--   D05 starts monthly giving 2026-07-01 -> sustainer; D07 still has no gifts -> prospect.
--   => prospect -> sustainer 1 and prospect -> prospect 1, from_stage_donors 2, share 0.5 each
-- Month-end arithmetic: 2026-06-30 + 3 months must land on 2026-09-30 (not 09-30 by luck of
-- day 30: also checked via a February start, 2026-02-28 + 3 -> 2026-05-31).

with t as (
    select * from {{ ref('pode_srv__stage_transitions') }}
),

expected as (
    select cast('2025-09-30' as date) as from_date, 12 as horizon_months, 'new' as from_stage, 'lapsed' as to_stage,
           1 as donors, 1 as from_stage_donors, 1.0 as share, true as is_latest
    union all select cast('2026-06-30' as date), 3, 'prospect', 'sustainer', 1, 2, 0.5, true
    union all select cast('2026-06-30' as date), 3, 'prospect', 'prospect',  1, 2, 0.5, true
)

select e.from_date, e.horizon_months, e.from_stage, e.to_stage, 'wrong or missing' as problem
from expected as e
left join t
    on  t.from_date = e.from_date and t.horizon_months = e.horizon_months
    and t.from_stage = e.from_stage and t.to_stage = e.to_stage
where t.from_date is null
   or t.donors != e.donors
   or t.from_stage_donors != e.from_stage_donors
   or abs(t.share - e.share) > 0.0001
   or t.is_latest != e.is_latest

union all
-- every to_date is the month-end exactly horizon_months after from_date
select from_date, horizon_months, from_stage, to_stage, 'bad to_date'
from t
where to_date != cast({{ dbt.dateadd('day', -1, dbt.dateadd('month', 'horizon_months + 1', dbt.date_trunc('month', 'from_date'))) }} as date)
   or (from_date = cast('2026-02-28' as date) and horizon_months = 3 and to_date != cast('2026-05-31' as date))

union all
-- shares for one from_stage add up to 1
select from_date, horizon_months, from_stage, null, 'shares != 1'
from t
group by from_date, horizon_months, from_stage
having abs(sum(share) - 1) > 0.0001
