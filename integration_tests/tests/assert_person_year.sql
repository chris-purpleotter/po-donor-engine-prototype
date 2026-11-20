-- Hand-calculated person x year rows (as_of = 2026-09-30, calendar fiscal year). Zero rows = pass.
-- D04: only gift 2025-09-01.
--   FY2025: gave, New. Stage at 2025-12-31 (the year's last month-end): 121 days -> active.
--   FY2026 (partial, stage_date = latest month-end 2026-09-30): no gift -> Lost (gave last year).
--     Stage then: 394 days -> lapsed. Stage 12 months earlier (2025-09-30): 29 days -> new.
--     So D04 is the journey "new -> lapsed" over the last year.

with expected as (
    select 'D04' as person_id, 2025 as fiscal_year, true as gave, 'New' as movement_status,
           cast('2025-12-31' as date) as stage_date, 'active' as stage, cast(null as {{ dbt.type_string() }}) as stage_1y_ago_check
    union all
    select 'D04', 2026, false, 'Lost', cast('2026-09-30' as date), 'lapsed', 'new'
)

select e.person_id, e.fiscal_year, 'wrong or missing' as problem
from expected as e
left join {{ ref('pocore__person__year') }} as a
    on a.person_id = e.person_id and a.fiscal_year = e.fiscal_year
where a.person_id is null
   or a.gave is distinct from e.gave
   or a.movement_status is distinct from e.movement_status
   or a.stage_date is distinct from e.stage_date
   or a.stage is distinct from e.stage
   or (e.stage_1y_ago_check is not null and coalesce(a.stage_1y_ago, '') != e.stage_1y_ago_check)
   or a.is_partial_year is distinct from (e.fiscal_year = 2026)
