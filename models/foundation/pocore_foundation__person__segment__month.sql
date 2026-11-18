{#
  pocore_foundation__person__segment__month — ONE ROW PER PERSON x SEGMENT x MONTH-END:
  which segments each person was in at each month-end (standard std_* and the client's
  custom cust_* segments). Segments may overlap, so a person can be in several at once.

  Join to pocore_foundation__person__month on (person_id, month_end_date) for the person's
  features and outcomes on that date: that join is how every segment baseline is built.
#}

select
    m.segment_id,
    m.segment_label,
    m.segment_source,
    m.person_id,
    m.snapshot_date as month_end_date
from {{ ref('pocore_seg__membership') }} as m
