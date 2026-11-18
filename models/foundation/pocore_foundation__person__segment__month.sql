{#
  pocore_foundation__person__segment__month — ONE ROW PER PERSON x SEGMENT x MONTH-END:
  which segments each person was in at each month-end: standard std_*, the client's custom
  cust_* segments, their split_by segments and segment-set segments. Segments may overlap
  (except within one set), so a person can be in several at once.

  Join to pocore_foundation__person__month on (person_id, month_end_date) for the person's
  features and outcomes on that date: that join is how every segment baseline is built.
#}

select
    m.segment_id,
    m.segment_label,
    m.segment_source,
    m.parent_segment_id,
    m.split_by,
    m.split_value,
    m.segment_set_id,
    m.person_id,
    m.snapshot_date as month_end_date
from {{ ref('pocore_seg__membership') }} as m
