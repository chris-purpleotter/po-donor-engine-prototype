{{ config(enabled=po_core.pocore_client_config__module_enabled('insights')) }}

-- v0.3.6: the engine's single lists (pocore_engine_config__lifecycle_stages, pocore_engine_config__measures) cover everything
-- the engine actually produces, so the report never shows a raw id or an unworded measure.
-- Zero rows = pass.

with stage_bands as (
    select band_sql from {{ ref('pocore_export__insights_dimensions') }} where dimension = 'lifecycle_stage'
),

measures as (
    select * from {{ ref('pocore_export__insights_measures') }}
),

-- every stage the snapshot produces has a label (a band in the Lifecycle stage dropdown)
unlabelled_stages as (
    select distinct p.lifecycle_stage as item, 'stage has no label in pocore_engine_config__lifecycle_stages' as problem
    from {{ ref('pocore_foundation__person__month_end') }} as p
    left join stage_bands as b on b.band_sql = concat('lifecycle_stage = ''', p.lifecycle_stage, '''')
    where b.band_sql is null
),

-- every group's measure is in the measures list
unknown_measures as (
    select distinct s.primary_kpi as item, 'primary_kpi missing from pocore_engine_config__measures' as problem
    from {{ ref('pocore__segment') }} as s
    left join measures as m on m.kpi_id = s.primary_kpi
    where m.kpi_id is null
),

-- each measure is worded, and adds_up is right for the ones we know
bad_measures as (
    select kpi_id as item, 'measure wording or adds_up wrong' as problem
    from measures
    where phrase not like '%{days}%'
       or measure_name is null
       or (kpi_id in ('gave', 'started_monthly') and not adds_up)
       or (kpi_id = 'retained' and adds_up)
)

select * from unlabelled_stages
union all select * from unknown_measures
union all select * from bad_measures
