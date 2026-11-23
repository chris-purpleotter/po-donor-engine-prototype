{#
  pocore_group__segment — ONE ROW PER SEGMENT (configured, split and set segments alike) that has
  had members: the SEGMENT DIMENSION. Join pocore_group__membership__month on segment_id.
  The segment's headline measure and window are on pocore__segment (certified).
#}

select distinct
    segment_id,
    segment_label,
    segment_source,
    parent_segment_id,
    split_by,
    split_value,
    segment_set_id
from {{ ref('pocore_group__membership__month') }}
