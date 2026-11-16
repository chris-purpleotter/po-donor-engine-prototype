-- Segment value columns are consistent with their definitions. Zero rows = pass.
--   value_per_point          = donors_at_snapshot x 0.01 x revenue_per_extra_donor
--   value_of_detectable_lift = extra_donors_at_detectable_lift x revenue_per_extra_donor
--   extra_donors_at_detectable_lift = donors_at_snapshot x detectable_lift
-- Checked on both summary tables (whole segments and slices).
-- Also: every row is as of the latest month-end (2026-09-30), and a segment with nobody in
-- it now shows 0 donors, not a stale count (std_new_v1 is empty at 2026-09-30; it last had
-- a member at 2025-11-30).

{%- for m in ['pode_srv__segment_summary', 'pode_srv__segment_summary_by_slice'] %}
select '{{ m }}' as model, segment_id
from {{ ref(m) }}
where abs(value_per_point - donors_at_snapshot * 0.01 * revenue_per_extra_donor) > 0.001
   or abs(extra_donors_at_detectable_lift - donors_at_snapshot * detectable_lift) > 0.001
   or abs(value_of_detectable_lift - extra_donors_at_detectable_lift * revenue_per_extra_donor) > 0.001
   or (revenue_per_extra_donor is not null and value_per_point is null)
{% if not loop.last %}union all{% endif %}
{%- endfor %}

union all
select 'stale snapshot_date' as model, segment_id
from {{ ref('pode_srv__segment_summary') }}
where snapshot_date != cast('2026-09-30' as date)
union all
select 'std_new_v1 should be 0 now', segment_id
from {{ ref('pode_srv__segment_summary') }}
where segment_id = 'std_new_v1' and donors_at_snapshot != 0
