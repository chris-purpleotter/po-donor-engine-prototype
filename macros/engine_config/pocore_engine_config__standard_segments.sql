{#
  The engine's standard segments (SPEC §5a). Identical for every client; changing a
  rule means a new _vN id and a MAJOR release (D12). Clients add their own with the
  `segments` var (ids prefixed `cust_`).

  Each segment: id, label, rule (a SQL WHERE condition over pocore_rollup__person__month_end_lookback
  columns), and primary_window_days — the window that matters most for that group,
  used for the headline numbers in the srv summary tables:
    new -> 90 (second gift), lapsed -> 180 (reactivation), others -> 365 (retention).
  primary_kpi (optional, default 'gave'): the KPI those headline numbers use. Sustainers use
  'retained' (still an active sustainer at the end of the window); for everyone else the
  question is whether they gave a qualifying gift.
  The default filter (individuals, not deceased) is added by pocore_group__membership__month.
#}

{% macro pocore_engine_config__standard_segments() %}
    {{ return([
        {'id': 'std_prospect_v1',    'label': 'Prospects (no gifts yet)',               'rule': "lifecycle_stage = 'prospect'",    'primary_window_days': 365},
        {'id': 'std_new_v1',         'label': 'New donors (first gift < 90 days)',      'rule': "lifecycle_stage = 'new'",         'primary_window_days': 90},
        {'id': 'std_active_v1',      'label': 'Active donors (gave in last 12 months)', 'rule': "lifecycle_stage = 'active'",      'primary_window_days': 365},
        {'id': 'std_lapsed_v1',      'label': 'Lapsed donors (13-24 months)',           'rule': "lifecycle_stage = 'lapsed'",      'primary_window_days': 180},
        {'id': 'std_deep_lapsed_v1', 'label': 'Deep lapsed donors (24+ months)',        'rule': "lifecycle_stage = 'deep_lapsed'", 'primary_window_days': 365},
        {'id': 'std_sustainer_v1',   'label': 'Sustainers (active monthly donors)',     'rule': "lifecycle_stage = 'sustainer'",   'primary_window_days': 365, 'primary_kpi': 'retained'}
    ]) }}
{% endmacro %}
