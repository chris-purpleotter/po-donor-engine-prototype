{{ config(enabled=po_core.pocore_module_enabled('pack')) }}

-- The Planning Pack export (as_of = 2026-09-30, pack var in dbt_project.yml). Zero rows = pass.
-- Population now (individuals, not deceased): D01-D07, D10 = 8 people.
--   Stage: lapsed 4 (D01, D04, D06, D10), deep_lapsed 1 (D02), active 1 (D03), sustainer 1 (D05), prospect 1 (D07)
--   Lifetime giving: Under $100 = D02 25, D04 40, D05 60, D06 0, D07 0 (5); $100+ = D01 125, D03 250, D10 250 (3)
-- The 'now' cube rows must add up to exactly that, and each combination appears once per period.

with cube as (
    select * from {{ ref('pocore_export__pack_cube') }}
),

expected as (
    select 'stage' as kind, 'lapsed' as value, 4 as people union all
    select 'stage', 'deep_lapsed', 1 union all
    select 'stage', 'active', 1 union all
    select 'stage', 'sustainer', 1 union all
    select 'stage', 'prospect', 1 union all
    select 'band', 'Under $100', 5 union all
    select 'band', '$100+', 3 union all
    select 'total', 'all', 8
),

actual as (
    select 'stage' as kind, lifecycle_stage as value, sum(people) as people from cube where period = 'now' group by lifecycle_stage
    union all
    select 'band', lifetime_giving, sum(people) from cube where period = 'now' group by lifetime_giving
    union all
    select 'total', 'all', sum(people) from cube where period = 'now'
),

counts as (
    select e.kind, e.value, 'now counts' as problem
    from expected as e
    left join actual as a on a.kind = e.kind and a.value = e.value
    where a.people is distinct from e.people
),

dupes as (
    select period as kind, lifecycle_stage as value, 'duplicate combination' as problem
    from cube
    group by period, lifecycle_stage, attr_is_board_member, lifetime_giving
    having count(*) > 1
),

settings as (
    select setting as kind, value, 'setting' as problem
    from {{ ref('pocore_export__pack_settings') }}
    where (setting = 'window_days' and value <> '90')
       or (setting = 'client_name' and value <> 'Integration test (who''s tested)')
       or (setting = 'as_of' and value <> '2026-09-30')
),

dims as (
    select 'dimensions' as kind, cast(count(*) as {{ dbt.type_string() }}) as value, 'expected 4 rows (2 plain + 2 bands)' as problem
    from {{ ref('pocore_export__pack_dimensions') }}
    having count(*) <> 4
)

select * from counts
union all select * from dupes
union all select * from settings
union all select * from dims
