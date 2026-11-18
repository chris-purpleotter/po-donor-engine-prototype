{#
  Settings for the Planning Pack export (models/export), from the client's `pack` var, with
  defaults for anything not set. Everything client-specific about the pack lives here, in the
  client's dbt project, so the pack tool itself stays client-agnostic.

    vars:
      po_core:
        pack:
          client_name: "Acme Foundation"
          window_days: 180          # 30, 90, 180 or 365: the cube's outcome window
          holdout_pct: 15           # for the detectable-lift estimate
          min_group_size: 5         # the pack hides groups smaller than this
          dimensions:               # the "Build a population" dropdowns
            - {name: lifecycle_stage, label: "Lifecycle stage"}
            - name: lifetime_giving
              label: "Lifetime giving"
              bands:                # SQL over pocore_foundation__person__month columns; the
                - {label: "$1 - $99", sql: "net_giving_lifetime > 0 and net_giving_lifetime < 100"}
                                    # same SQL goes into the segment rules the pack generates

  Plain dimensions must be columns of pocore_foundation__person__month (attr_* included).
  Keep each to a handful of values: every dimension multiplies the cube's size.
#}

{% macro pocore_pack_settings() %}
    {%- set defaults = {
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
        ]
    } -%}
    {%- set s = {} -%}
    {%- do s.update(defaults) -%}
    {%- do s.update(var('pack', {}) or {}) -%}

    {#- validate, so a typo fails the build instead of producing an odd pack -#}
    {%- if (s.window_days | int) not in pocore_kpi_windows() -%}
        {{ exceptions.raise_compiler_error("po_core: pack.window_days must be one of " ~ pocore_kpi_windows() ~ ", got " ~ s.window_days) }}
    {%- endif -%}
    {%- set seen = [] -%}
    {%- for d in s.dimensions -%}
        {%- if not d.get('name') or not d.get('label') -%}
            {{ exceptions.raise_compiler_error("po_core: every pack dimension needs a name and a label: " ~ d) }}
        {%- endif -%}
        {%- if not modules.re.match('^[a-z_][a-z0-9_]*$', d.name) -%}
            {{ exceptions.raise_compiler_error("po_core: pack dimension name '" ~ d.name ~ "' must be lowercase snake_case") }}
        {%- endif -%}
        {%- if d.name in seen or d.name == 'period' -%}
            {{ exceptions.raise_compiler_error("po_core: pack dimension name '" ~ d.name ~ "' is used twice (or is reserved)") }}
        {%- endif -%}
        {%- do seen.append(d.name) -%}
        {%- for b in d.get('bands', []) -%}
            {%- if not b.get('label') or not b.get('sql') -%}
                {{ exceptions.raise_compiler_error("po_core: every band of pack dimension '" ~ d.name ~ "' needs a label and sql") }}
            {%- endif -%}
        {%- endfor -%}
    {%- endfor -%}
    {{ return(s) }}
{% endmacro %}


{#- The engine version the pack checks it is compatible with (keep in step with dbt_project.yml). -#}
{% macro pocore_version() %}{{ return('0.3.3') }}{% endmacro %}
