-- The started_monthly measure (as_of = 2026-09-30). Zero rows = pass.
-- D05 signs up to monthly giving with G007 on 2026-07-01 (G008, G009 are routine payments).
--   From 2026-06-30 the sign-up is 1 day later -> started_monthly_30d = 1.
--   From 2026-05-31 it is 31 days later       -> started_monthly_30d = 0, _90d = 1.
--   From 2026-07-31 the sign-up is in the past -> 0 (routine payments are not sign-ups).
--   D03 only gives one-time gifts             -> never 1.
-- cust_could_go_monthly_v1 is judged on started_monthly over 90 days.

with expected as (
    select 'D05' as person_id, cast('2026-06-30' as date) as month_end_date, 1 as sm30, 1 as sm90 union all
    select 'D05', cast('2026-05-31' as date), 0, 1 union all
    select 'D05', cast('2026-07-31' as date), 0, 0 union all
    select 'D03', cast('2025-12-31' as date), 0, 0
)

select e.person_id, cast(e.month_end_date as {{ dbt.type_string() }}) as detail, 'outcome' as problem
from expected as e
left join {{ ref('pocore_foundation__person__month_end') }} as p
    on p.person_id = e.person_id and p.month_end_date = e.month_end_date
where p.person_id is null
   or p.started_monthly_30d is distinct from e.sm30
   or p.started_monthly_90d is distinct from e.sm90

union all

select gift_id, 'signup flag', 'gift'
from {{ ref('pocore_fact__gift') }}
where gift_id in ('G007', 'G008', 'G009')
  and is_first_recurring_payment is distinct from (gift_id = 'G007')

union all

select segment_id, primary_kpi, 'segment measure'
from {{ ref('pocore__segment') }}
where segment_id = 'cust_could_go_monthly_v1'
  and (primary_kpi is distinct from 'started_monthly' or outcome_window_days is distinct from 90)

union all

select 'cust_could_go_monthly_v1', 'missing', 'segment measure'
where not exists (select 1 from {{ ref('pocore__segment') }} where segment_id = 'cust_could_go_monthly_v1')
