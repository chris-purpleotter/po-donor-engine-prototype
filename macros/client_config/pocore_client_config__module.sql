{#
  A module's settings: the client's `module__<name>` block laid over the engine's defaults below.
  Clients write only what they change; anything left out keeps its default.

      vars:
        po_core:
          module__group:
            groups: [...]
          module__cohort:
            enabled: false            # optional modules only: switch off without deleting the block
          module__insights:
            client_name: "Acme"

  Optional modules (movement, cohort, insights) have `enabled` (default true). The required module
  (group) has no `enabled`: the certified group tables, insights and admin depend on it. A setting
  a module doesn't have (a typo, or `enabled` on group) stops the build and lists the real ones.

      pocore_client_config__module('group').groups      -> the client's groups, or []

  The DEFAULTS below are the only place each module's defaults live:
    group     groups [] custom groups (optionally split_by: <column>); standard_splits {}
              (e.g. {std_lapsed_v1: acquisition_channel}); group_sets [] non-overlapping
              populations, first match wins; test planning: alpha 0.05 (two-sided), power 0.8,
              holdout_grid [10, 15, 20, 30], baseline_lookback_months [12, 24],
              baseline_recent_anchors 3 (normal = last N complete month-ends),
              baseline_instability_threshold 0.25 (recent vs pooled gap that flags is_unstable),
              max_plausible_relative_lift 0.5 (is_testable: lift must be <= +50% relative),
              summary_holdout_pct 15 (must be in holdout_grid), summary_default_window_days 180;
              tenure_bands_months [1, 2, 3, 4, 6, 12, 24] (how long people had been in a group:
              joined that month, 1, 2, 3, 4-5, 6-11 months, 1-2 years, 2+ years before)
    movement  enabled
    cohort    enabled; survival_months [2, 6, 12, 24] ("still giving in month N");
              ltv_horizons_months [12, 24, 60] (cumulative revenue per starter through month N)
    insights  enabled; client_name (default: the client's project name); window_days 180
              (30/90/180/365: the cube's window); holdout_pct 15; min_group_size 5 (smaller
              groups hidden); dimensions (the "Build a group" dropdowns)
#}
{% macro pocore_client_config__module(name) %}
    {%- set defaults = {
        'group': {
            'groups': [],
            'standard_splits': {},
            'group_sets': [],
            'alpha': 0.05,
            'power': 0.8,
            'holdout_grid': [10, 15, 20, 30],
            'baseline_lookback_months': [12, 24],
            'baseline_recent_anchors': 3,
            'baseline_instability_threshold': 0.25,
            'max_plausible_relative_lift': 0.5,
            'summary_holdout_pct': 15,
            'summary_default_window_days': 180,
            'tenure_bands_months': [1, 2, 3, 4, 6, 12, 24],
        },
        'movement': {
            'enabled': true,
        },
        'cohort': {
            'enabled': true,
            'survival_months': [2, 6, 12, 24],
            'ltv_horizons_months': [12, 24, 60],
        },
        'insights': {
            'enabled': true,
            'client_name': project_name,
            'window_days': 180,
            'holdout_pct': 15,
            'min_group_size': 5,
            'dimensions': [
                {'name': 'lifecycle_stage', 'label': 'Lifecycle stage'},
                {'name': 'acquisition_channel', 'label': 'Acquisition channel'},
                {'name': 'region', 'label': 'Region'},
                {'name': 'first_gift_band', 'label': 'First gift'},
                {'name': 'lifetime_giving', 'label': 'Lifetime giving', 'bands': [
                    {'label': '$0 (never given)', 'sql': 'net_giving_lifetime <= 0'},
                    {'label': '$1 - $99', 'sql': 'net_giving_lifetime > 0 and net_giving_lifetime < 100'},
                    {'label': '$100 - $249', 'sql': 'net_giving_lifetime >= 100 and net_giving_lifetime < 250'},
                    {'label': '$250 - $999', 'sql': 'net_giving_lifetime >= 250 and net_giving_lifetime < 1000'},
                    {'label': '$1,000+', 'sql': 'net_giving_lifetime >= 1000'}
                ]}
            ],
        },
    } -%}
    {%- if name not in defaults -%}
        {{ exceptions.raise_compiler_error("po_core: no module '" ~ name ~ "'. Modules: " ~ defaults.keys() | join(', ')) }}
    {%- endif -%}
    {%- set settings = {} -%}
    {%- do settings.update(defaults[name]) -%}
    {%- set client = var('module__' ~ name, {}) or {} -%}
    {%- for key in client -%}
        {%- if key not in defaults[name] -%}
            {{ exceptions.raise_compiler_error("po_core: module__" ~ name ~ " has no setting '" ~ key ~ "'. Settings: " ~ defaults[name].keys() | join(', ')) }}
        {%- endif -%}
    {%- endfor -%}
    {%- do settings.update(client) -%}
    {{ return(settings) }}
{% endmacro %}
