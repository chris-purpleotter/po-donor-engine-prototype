{#
  pocore__segment__breakdown — ONE ROW PER SEGMENT x BREAKDOWN VALUE, as of the latest
  month-end. The same columns as pocore__segment, split by a person attribute
  (breakdown_by = acquisition_channel, region, first_gift_band, attr_* ...; breakdown_value =
  the value). Filter to ONE breakdown_by: within it the values add up to the segment; across
  breakdown_by values they overlap.
#}
{{ pocore_segment_summary(by_breakdown=true) }}
