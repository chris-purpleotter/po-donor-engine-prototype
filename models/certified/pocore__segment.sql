{#
  pocore__segment — ONE ROW PER SEGMENT, as of the latest month-end.
  Our opinion on where to focus: how many people are in each segment now, how they normally
  do on the segment's primary KPI, whether a test is worth running, and what a lift is worth.
  Built from foundation (pocore_foundation__person__month / __person__segment__month) via the
  engine's statistics (pocore_mtr__segment_power).
#}
{{ pocore_segment_summary() }}
