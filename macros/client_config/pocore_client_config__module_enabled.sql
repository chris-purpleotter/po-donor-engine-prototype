{#
  Optional modules (SPEC §6.6). A module's models call this in their config:
    {{ config(enabled=pocore_client_config__module_enabled('cohort')) }}
  Client switch (their dbt_project.yml):
    vars: {po_core: {modules: {cohort: false}}}
  Modules default to on. Unknown module names are an error (catches typos in the var).

  Rule for engine authors: nothing outside a module may ref() a model inside it, or dbt
  fails at parse time when the module is off.

  (Self-contained on purpose: when a client project calls this as
  po_core.pocore_client_config__module_enabled(...) in a config() block, other engine macros
  aren't in scope.)
#}

{% macro pocore_client_config__module_enabled(module) %}
    {%- set known_modules = ['cohort', 'insights'] -%}
    {%- set modules = var('modules', {}) or {} -%}
    {%- for m in modules -%}
        {%- if m not in known_modules -%}
            {{ exceptions.raise_compiler_error("po_core: unknown module '" ~ m ~ "' in var 'modules'. Only optional modules can be switched off: " ~ known_modules | join(', ')) }}
        {%- endif -%}
    {%- endfor -%}
    {%- if module not in known_modules -%}
        {{ exceptions.raise_compiler_error("po_core: pocore_client_config__module_enabled called with unknown module '" ~ module ~ "'") }}
    {%- endif -%}
    {%- set v = modules.get(module, true) -%}
    {#- tolerate "false"/"true" strings (e.g. from env vars) as well as real booleans -#}
    {{ return(v if (v is sameas true or v is sameas false) else (v | string | lower == 'true')) }}
{% endmacro %}
