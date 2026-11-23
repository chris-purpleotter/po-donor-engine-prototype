{#
  Is an OPTIONAL module on? A module's models call this in their config:
    {{ config(enabled=pocore_client_config__module_enabled('cohort')) }}
  Client switch (their dbt_project.yml), keeping the rest of the module's settings in place:
    vars: {po_core: {module__cohort: {enabled: false}}}
  Optional modules default to on. The required module (group) has no switch.

  Rule for engine authors: nothing outside a module may ref() a model inside it, or dbt
  fails at parse time when the module is off.

  (Self-contained on purpose: when a client project calls this as
  po_core.pocore_client_config__module_enabled(...) in a config() block, other engine macros
  aren't in scope. Settings are validated by pocore_client_config__module.)
#}

{% macro pocore_client_config__module_enabled(module) %}
    {%- if module not in ['movement', 'cohort', 'insights'] -%}
        {{ exceptions.raise_compiler_error("po_core: pocore_client_config__module_enabled called with '" ~ module ~ "'; optional modules: movement, cohort, insights") }}
    {%- endif -%}
    {%- set v = (var('module__' ~ module, {}) or {}).get('enabled', true) -%}
    {#- tolerate "false"/"true" strings (e.g. from env vars) as well as real booleans -#}
    {{ return(v if (v is sameas true or v is sameas false) else (v | string | lower == 'true')) }}
{% endmacro %}
