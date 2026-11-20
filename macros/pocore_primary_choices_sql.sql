{#
  Each configured segment's primary window and KPI, as SQL rows (segment_id, primary_window_days,
  primary_kpi). Split and set segments use their parent's: join on
  coalesce(parent_segment_id, '__remainder__'). Shared by pocore__segment and
  pocore__segment__month, so both always agree on a group's headline measure.
#}
{% macro pocore_primary_choices_sql() %}
    {% for s in pocore_all_segments() %}
    select '{{ s.id }}' as segment_id, {{ s.primary_window_days }} as primary_window_days, '{{ s.primary_kpi }}' as primary_kpi
    union all
    {% endfor %}
    -- a set's remainder ("everyone else") has no parent segment: default window and KPI
    select '__remainder__', {{ var('summary_default_window_days') }}, 'gave'
{% endmacro %}
