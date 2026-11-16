-- Hand-calculated retained KPI (as_of = 2026-09-30, recurring_active_days = 45). Zero rows = pass.
-- retained_Nd = a recurring payment in [anchor + N - 45, anchor + N].
-- D05 recurring payments: 2026-07-01, 2026-08-01, 2026-09-01.
--   @ 2026-03-31, 90d: ends 06-29, looks at [05-15, 06-29]  -> none          -> 0
--   @ 2026-04-30, 90d: ends 07-29, looks at [06-14, 07-29]  -> 07-01         -> 1
--   @ 2026-05-31, 90d: ends 08-29, looks at [07-15, 08-29]  -> 08-01         -> 1
--   @ 2026-06-30, 90d: ends 09-28, looks at [08-14, 09-28]  -> 09-01         -> 1
--   @ 2026-03-31, 180d: ends 09-27, looks at [08-13, 09-27] -> 09-01         -> 1
--   @ 2026-05-31, 180d: ends 11-27, looks at [10-13, 11-27] -> none          -> 0 (window not complete)
-- D01 @ 2024-09-30: one-time gift only -> never retained.
-- Also: every summary row uses 'retained' for sustainers and 'gave' for everyone else.

with expected as (
    select 'D05' as donor_id, cast('2026-03-31' as date) as anchor_date, 0 as retained_90d, 1 as retained_180d union all
    select 'D05', cast('2026-04-30' as date), 1, 0 union all
    select 'D05', cast('2026-05-31' as date), 1, 0 union all
    select 'D05', cast('2026-06-30' as date), 1, 0 union all
    select 'D01', cast('2024-09-30' as date), 0, 0
),

wrong_outcomes as (
    select e.donor_id, cast(e.anchor_date as {{ dbt.type_string() }}) as detail
    from expected as e
    left join {{ ref('pode_ftr__kpi_outcomes') }} as a
        on a.donor_id = e.donor_id and a.anchor_date = e.anchor_date
    where a.donor_id is null
       or a.retained_90d  != e.retained_90d
       or a.retained_180d != e.retained_180d
),

wrong_summary_kpi as (
    select segment_id as donor_id, primary_kpi as detail
    from {{ ref('pode_srv__segment_summary') }}
    where (segment_id = 'std_sustainer_v1') != (primary_kpi = 'retained')
)

select * from wrong_outcomes
union all
select * from wrong_summary_kpi
