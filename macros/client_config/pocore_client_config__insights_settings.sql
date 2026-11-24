{#
  Settings for the Supporter Insights export (models/5__modules/optional/insights): the client's
  `module__insights` block over the defaults in pocore_client_config__module, then checked. Everything client-specific about the report lives here, in the
  client's dbt project, so the report tool itself stays client-agnostic.

    vars:
      po_core:
        module__insights:
          client_name: "Acme Foundation"
          window_days: 180          # 30, 90, 180 or 365: the cube's outcome window
          holdout_pct: 15           # for the detectable-lift estimate
          min_group_size: 5         # the report hides groups smaller than this
          dimensions:               # the "Build a population" dropdowns
            - {name: lifecycle_stage, label: "Lifecycle stage"}   # bands added automatically (engine stage labels)
            - name: lifetime_giving
              label: "Lifetime giving"
              bands:                # SQL over pocore_foundation__person__month columns; the
                - {label: "$1 - $99", sql: "net_giving_lifetime > 0 and net_giving_lifetime < 100"}
                                    # same SQL goes into the group rules the report generates

  Plain dimensions must be columns of pocore_foundation__person__month (attr_* included).
  Keep each to a handful of values: every dimension multiplies the cube's size.
#}

{% macro pocore_client_config__insights_settings() %}
    {%- set s = pocore_client_config__module('insights') -%}

    {#- lifecycle_stage with no bands of its own gets the engine's stage labels as bands, so the
        dropdown reads "Lapsed (13-24 months)" in lifecycle order, and a picked stage still
        becomes the rule lifecycle_stage = 'lapsed'. -#}
    {%- set dims = [] -%}
    {%- for d in s.dimensions -%}
        {%- if d.get('name') == 'lifecycle_stage' and not d.get('bands') -%}
            {%- set stage_bands = [] -%}
            {%- for st in pocore_engine_config__lifecycle_stages() -%}
                {%- do stage_bands.append({'label': st.label, 'sql': "lifecycle_stage = '" ~ st.id ~ "'"}) -%}
            {%- endfor -%}
            {%- set d2 = {} -%}
            {%- do d2.update(d) -%}
            {%- do d2.update({'bands': stage_bands}) -%}
            {%- do dims.append(d2) -%}
        {%- else -%}
            {%- do dims.append(d) -%}
        {%- endif -%}
    {%- endfor -%}
    {%- do s.update({'dimensions': dims}) -%}

    {#- validate, so a typo fails the build instead of producing an odd report -#}
    {%- if (s.window_days | int) not in pocore_engine_config__kpi_windows() -%}
        {{ exceptions.raise_compiler_error("po_core: insights.window_days must be one of " ~ pocore_engine_config__kpi_windows() ~ ", got " ~ s.window_days) }}
    {%- endif -%}
    {%- set seen = [] -%}
    {%- for d in s.dimensions -%}
        {%- if not d.get('name') or not d.get('label') -%}
            {{ exceptions.raise_compiler_error("po_core: every insights dimension needs a name and a label: " ~ d) }}
        {%- endif -%}
        {%- if not modules.re.match('^[a-z_][a-z0-9_]*$', d.name) -%}
            {{ exceptions.raise_compiler_error("po_core: insights dimension name '" ~ d.name ~ "' must be lowercase snake_case") }}
        {%- endif -%}
        {%- if d.name in seen or d.name == 'period' -%}
            {{ exceptions.raise_compiler_error("po_core: insights dimension name '" ~ d.name ~ "' is used twice (or is reserved)") }}
        {%- endif -%}
        {%- do seen.append(d.name) -%}
        {%- for b in d.get('bands', []) -%}
            {%- if not b.get('label') or not b.get('sql') -%}
                {{ exceptions.raise_compiler_error("po_core: every band of insights dimension '" ~ d.name ~ "' needs a label and sql") }}
            {%- endif -%}
        {%- endfor -%}
    {%- endfor -%}
    {{ return(s) }}
{% endmacro %}
