{#
  Every segment the engine builds: standard + the client's custom `segments` var.
  Custom segments may set primary_window_days (otherwise summary_default_window_days) and
  primary_kpi (any id in pocore_measures(); otherwise 'gave').
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
        {%- if out[-1].primary_kpi not in pocore_measure_ids() -%}
            {{ exceptions.raise_compiler_error("po_core: segment " ~ s.id ~ " primary_kpi must be one of " ~ pocore_measure_ids() | join(', ') ~ ", got '" ~ out[-1].primary_kpi ~ "'") }}
        {%- endif -%}
    {%- endfor -%}
    {{ return(out) }}
{% endmacro %}
