-- The contract in: what the client's conform hands the engine (layer: can)
-- Two people to follow through every step:
--   D05  a prospect (created 2024-02-20) who starts monthly giving on 2026-07-01 ($20/month)
--   D04  a new donor (one $40 gift on 2025-09-01) who never gives again
-- as_of for the test project = 2026-09-30 (every number is "as of" that date).

-- query: people (the `people` contract: who exists, with or without gifts)
select * from main_pocore_internal.pocore_can__people
where person_id in ('D04', 'D05');

-- query: gifts (the `gifts` contract: one row per gift or refund)
select gift_id, person_id, gift_date, amount, gift_type, recurring_schedule_id, is_refund, is_kpi_eligible
from main_pocore_internal.pocore_can__gifts
where person_id in ('D04', 'D05')
order by person_id, gift_date;
