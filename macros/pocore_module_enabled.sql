{#
  Optional modules (SPEC §6.6). A module's models call this in their config:
    {{ config(enabled=pocore_module_enabled('sustainers')) }}
  Client switch (their dbt_project.yml):
    vars: {po_core: {modules: {sustainers: false}}}
  Modules default to on. Unknown module names are an error (catches typos in the var).

  Rule for engine authors: nothing outside a module may ref() a model inside it, or dbt
  fails at parse time when the module is off.

  (Self-contained on purpose: when a client project calls this as
  po_core.pocore_module_enabled(...) in a config() block, other engine macros
  aren't in scope.)
#}

{% macro pocore_module_enabled(module) %}
    {%- set known_modules = ['sustainers', 'pack'] -%}
    {%- set modules = var('modules', {}) or {} -%}
    {%- for m in modules -%}
        {%- if m not in known_modules -%}
            {{ exceptions.raise_compiler_error("po_core: unknown module '" ~ m ~ "' in var 'modules'. Known: " ~ known_modules) }}
        {%- endif -%}
    {%- endfor -%}
    {%- if module not in known_modules -%}
        {{ exceptions.raise_compiler_error("po_core: pocore_module_enabled called with unknown module '" ~ module ~ "'") }}
    {%- endif -%}
    {%- set v = modules.get(module, true) -%}
    {#- tolerate "false"/"true" strings (e.g. from env vars) as well as real booleans -#}
    {{ return(v if (v is sameas true or v is sameas false) else (v | string | lower == 'true')) }}
{% endmacro %}
