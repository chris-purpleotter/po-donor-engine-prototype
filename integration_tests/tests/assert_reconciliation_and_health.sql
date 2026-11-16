-- Hand-calculated reconciliation and project health (as_of = 2026-09-30). Zero rows = pass.
--
-- Canonical gifts (conform keeps Closed Won + Refunded): 15 gifts, nothing dropped.
--   2024 net = G002 75 + G004 100                                         = 175
--   2025 net = G005 150 + G006 40 + G010 60 + G011 -60 + G012 10000 + G015 250 = 10440
--   excluded: category_grant 10000 (G012, 2025); capital_campaign 5000 (G014, 2026)
-- Finance seed: 2024 = 175 (0% -> ok); 2025 = 10000 (engine +4.4% -> warn).
-- Health:
--   data_freshness      latest gift 2026-09-01 -> 29 days -> ok
--   gifts_total 15, donors_total 10, gifts_after_as_of 0
--   suspected_unlinked_recurring 0 -> ok
--   recurring_share_drop  Sep 2026: 1 of 1 recurring = 1.0;
--                         Sep 2025-Aug 2026: 2 of 5 real gifts recurring = 0.4 -> 2.5 -> ok
--   active_donors_12m   eligible real gifts after 2025-09-30: D03 (G005), D05 (G007-9) -> 2
--   eligible_share_12m  window net 150 + 60 + 5000 = 5210; eligible 210 -> 0.0403
--   empty_segments      std_new_v1 only (no first gift in the last 90 days) -> 1, warn

with recon as (
    select * from {{ ref('pode_srv__reconciliation') }}
),

health as (
    select * from {{ ref('pode_srv__project_health') }}
),

recon_checks as (
    select 'recon gifts total' as check_name, cast(sum(gifts) as double) as actual, 15.0 as expected from recon
    union all select 'recon 2024 net', sum(net_amount), 175.0 from recon where giving_year = 2024
    union all select 'recon 2025 net', sum(net_amount), 10440.0 from recon where giving_year = 2025
    union all select 'recon category_grant', sum(net_amount), 10000.0 from recon where exclusion_reason = 'category_grant'
    union all select 'recon capital_campaign', sum(net_amount), 5000.0 from recon where exclusion_reason = 'capital_campaign'
),

health_checks as (
    select check_id || ':' || scope as check_name, value as actual,
           case check_id || ':' || scope
               when 'data_freshness:all'               then 29
               when 'gifts_total:all'                  then 15
               when 'donors_total:all'                 then 10
               when 'gifts_after_as_of:all'            then 0
               when 'suspected_unlinked_recurring:all' then 0
               when 'recurring_share_drop:all'         then 2.5
               when 'active_donors_12m:all'            then 2
               when 'eligible_share_12m:all'           then 210.0 / 5210
               when 'empty_segments:all'               then 1
               when 'finance_match:2024'               then 0
               when 'finance_match:2025'               then 4.4
           end as expected
    from health
    where check_id != 'months_without_gifts'
),

status_checks as (
    select check_id || ':' || scope || ' status=' || status as check_name, 0.0 as actual, 1.0 as expected
    from health
    where (check_id || ':' || scope) in ('finance_match:2025', 'empty_segments:all', 'months_without_gifts:all') and status != 'warn'
       or (check_id || ':' || scope) in ('finance_match:2024', 'data_freshness:all', 'recurring_share_drop:all') and status != 'ok'
       or (check_id = 'empty_segments' and detail != 'std_new_v1')
)

select * from recon_checks where actual is null or abs(actual - expected) > 0.001
union all
select * from health_checks where expected is null or actual is null or abs(actual - expected) > 0.001
union all
select * from status_checks
