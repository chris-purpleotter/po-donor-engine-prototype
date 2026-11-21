{#- The engine version the pack checks it is compatible with (keep in step with dbt_project.yml). -#}
{% macro pocore_engine_config__version() %}{{ return('0.5.0') }}{% endmacro %}
