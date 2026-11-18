{#
  The engine's standard segments (SPEC §5a). Identical for every client; changing a
  rule means a new _vN id and a MAJOR release (D12). Clients add their own with the
  `segments` var (ids prefixed `cust_`).

  Each segment: id, label, rule (a SQL WHERE condition over pocore_ftr__person_snapshot
  columns), and primary_window_days — the window that matters most for that group,
  used for the headline numbers in the srv summary tables:
    new -> 90 (second gift), lapsed -> 180 (reactivation), others -> 365 (retention).
  primary_kpi (optional, default 'gave'): the KPI those headline numbers use. Sustainers use
  'retained' (still an active sustainer at the end of the window); for everyone else the
  question is whether they gave a qualifying gift.
  The default filter (individuals, not deceased) is added by pocore_seg__membership.
#}

{% macro pocore_standard_segments() %}
    {{ return([
        {'id': 'std_prospect_v1',    'label': 'Prospects (no gifts yet)',               'rule': "lifecycle_stage = 'prospect'",    'primary_window_days': 365},
        {'id': 'std_new_v1',         'label': 'New donors (first gift < 90 days)',      'rule': "lifecycle_stage = 'new'",         'primary_window_days': 90},
        {'id': 'std_active_v1',      'label': 'Active donors (gave in last 12 months)', 'rule': "lifecycle_stage = 'active'",      'primary_window_days': 365},
        {'id': 'std_lapsed_v1',      'label': 'Lapsed donors (13-24 months)',           'rule': "lifecycle_stage = 'lapsed'",      'primary_window_days': 180},
        {'id': 'std_deep_lapsed_v1', 'label': 'Deep lapsed donors (24+ months)',        'rule': "lifecycle_stage = 'deep_lapsed'", 'primary_window_days': 365},
        {'id': 'std_sustainer_v1',   'label': 'Sustainers (active monthly donors)',     'rule': "lifecycle_stage = 'sustainer'",   'primary_window_days': 365, 'primary_kpi': 'retained'}
    ]) }}
{% endmacro %}


{#
  Every segment the engine builds: standard + the client's custom `segments` var.
  Custom segments may set primary_window_days (otherwise summary_default_window_days) and
  primary_kpi ('gave', 'retained' or 'started_monthly'; otherwise 'gave').
#}
{#
  standard_splits (client var): break down STANDARD segments without redefining them, e.g.
      standard_splits:
        std_lapsed_v1: acquisition_channel
        std_active_v1: attr_age_group
  adds "Lapsed donors (13-24 months) — Web" etc. (custom segments use split_by directly).
#}
{% macro pocore_all_segments() %}
    {%- set out = [] -%}
    {%- set standard = pocore_standard_segments() -%}
    {%- set standard_splits = var('standard_splits', {}) or {} -%}
    {%- set standard_ids = standard | map(attribute='id') | list -%}
    {%- for sid in standard_splits -%}
        {%- if sid not in standard_ids -%}
            {{ exceptions.raise_compiler_error("po_core: standard_splits names '" ~ sid ~ "', which is not a standard segment (" ~ standard_ids | join(', ') ~ "). For a custom segment, put split_by on the segment itself.") }}
        {%- endif -%}
    {%- endfor -%}
    {%- for s in standard + var('segments', []) -%}
        {%- do out.append({
            'id': s.id,
            'label': s.label,
            'rule': s.rule,
            'primary_window_days': s.get('primary_window_days', var('summary_default_window_days')),
            'primary_kpi': s.get('primary_kpi', 'gave'),
            'split_by': standard_splits.get(s.id) if s.id in standard_ids else s.get('split_by')
        }) -%}
        {%- if out[-1].primary_kpi not in ['gave', 'retained', 'started_monthly'] -%}
            {{ exceptions.raise_compiler_error("po_core: segment " ~ s.id ~ " primary_kpi must be 'gave', 'retained' or 'started_monthly', got '" ~ out[-1].primary_kpi ~ "'") }}
        {%- endif -%}
    {%- endfor -%}
    {{ return(out) }}
{% endmacro %}
