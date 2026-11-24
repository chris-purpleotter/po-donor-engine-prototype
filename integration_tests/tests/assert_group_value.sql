-- Group value columns are consistent with their definitions. Zero rows = pass.
--   value_per_point          = people_in_group x 0.01 x revenue_per_extra_donor
--   value_of_detectable_lift = extra_donors_at_detectable_lift x revenue_per_extra_donor
--   extra_donors_at_detectable_lift = people_in_group x detectable_lift
-- Checked on every group row (configured, split and set groups).
-- Also: every row is as of the latest month-end (2026-09-30), and a group with nobody in
-- it now shows 0 donors, not a stale count (std_new_v1 is empty at 2026-09-30; it last had
-- a member at 2025-11-30).

{%- for m in ['pocore__group'] %}
select '{{ m }}' as model, group_id
from {{ ref(m) }}
where abs(value_per_point - people_in_group * 0.01 * revenue_per_extra_donor) > 0.001
   or abs(extra_donors_at_detectable_lift - people_in_group * detectable_lift) > 0.001
   or abs(value_of_detectable_lift - extra_donors_at_detectable_lift * revenue_per_extra_donor) > 0.001
   or (revenue_per_extra_donor is not null and value_per_point is null)
{% if not loop.last %}union all{% endif %}
{%- endfor %}

union all
select 'stale month_end_date' as model, group_id
from {{ ref('pocore__group') }}
where month_end_date != cast('2026-09-30' as date)
union all
select 'std_new_v1 should be 0 now', group_id
from {{ ref('pocore__group') }}
where group_id = 'std_new_v1' and people_in_group != 0
