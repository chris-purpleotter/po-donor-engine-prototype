{#
  Each configured group's primary window and KPI, as SQL rows (group_id, primary_window_days,
  primary_kpi). Split and set groups use their parent's: join on
  coalesce(parent_group_id, '__remainder__'). Shared by pocore__group and
  pocore__group__month, so both always agree on a group's headline measure.
#}
{% macro pocore_sql__primary_choices() %}
    {% for s in pocore_client_config__all_groups() %}
    select '{{ s.id }}' as group_id, {{ s.primary_window_days }} as primary_window_days, '{{ s.primary_kpi }}' as primary_kpi
    union all
    {% endfor %}
    -- a set's remainder ("everyone else") has no parent group: default window and KPI
    select '__remainder__', {{ pocore_client_config__module('group').summary_default_window_days }}, 'gave'
{% endmacro %}
