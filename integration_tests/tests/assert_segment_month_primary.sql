-- v0.3.7: pocore__segment__month's "group's own measure" columns pick the right measure column,
-- and agree with pocore__segment on each group's measure and window. Written out by hand (not
-- with the engine's loops) so it checks the logic independently. Zero rows = pass.

with m as (
    select * from {{ ref('pocore__segment__month') }}
),

s as (
    select segment_id, primary_kpi, outcome_window_days from {{ ref('pocore__segment') }}
),

-- same measure and window as the group summary (every group in pocore__segment)
summary_mismatch as (
    select distinct m.segment_id, 'primary_kpi / window differs from pocore__segment' as problem
    from m
    inner join s on s.segment_id = m.segment_id
    where m.primary_kpi is distinct from s.primary_kpi
       or m.primary_window_days is distinct from s.outcome_window_days
),

missing as (
    select distinct segment_id, 'primary_kpi is null' as problem
    from m
    where primary_kpi is null or primary_window_days is null
),

-- each window picks the column for the group's measure
wrong_pick as (
    select distinct segment_id, 'primary_*_<N>d picks the wrong column' as problem
    from m
    where primary_count_30d is distinct from case primary_kpi when 'gave' then gave_count_30d when 'started_monthly' then started_monthly_count_30d end
       or primary_count_90d is distinct from case primary_kpi when 'gave' then gave_count_90d when 'started_monthly' then started_monthly_count_90d when 'retained' then retained_count_90d end
       or primary_count_365d is distinct from case primary_kpi when 'gave' then gave_count_365d when 'started_monthly' then started_monthly_count_365d when 'retained' then retained_count_365d end
       or primary_rate_180d is distinct from case primary_kpi when 'gave' then gave_rate_180d when 'started_monthly' then started_monthly_rate_180d when 'retained' then retained_rate_180d end
),

-- the headline columns are the group's own window
wrong_headline as (
    select distinct segment_id, 'primary_rate / count / complete not at the group''s window' as problem
    from m
    where primary_rate is distinct from case primary_window_days when 30 then primary_rate_30d when 90 then primary_rate_90d when 180 then primary_rate_180d when 365 then primary_rate_365d end
       or primary_count is distinct from case primary_window_days when 30 then primary_count_30d when 90 then primary_count_90d when 180 then primary_count_180d when 365 then primary_count_365d end
       or is_primary_complete is distinct from case primary_window_days when 30 then is_complete_30d when 90 then is_complete_90d when 180 then is_complete_180d when 365 then is_complete_365d end
)

select * from summary_mismatch
union all select * from missing
union all select * from wrong_pick
union all select * from wrong_headline
