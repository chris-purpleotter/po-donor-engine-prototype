{#
  pode_srv__segment_summary_by_slice — ONE ROW PER SEGMENT x SLICE, as of today.
  Same columns as pode_srv__segment_summary, split by a donor attribute (slice_by =
  acquisition_channel, region, first_gift_band, attr_*). Pick ONE slice_by at a time:
  within one slice_by the slices add up to the segment; across slice_by values they overlap.
#}
{{ pode_segment_summary(by_slice=true) }}
