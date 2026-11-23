{#- The engine version the report checks it is compatible with (keep in step with dbt_project.yml). -#}
{% macro pocore_engine_config__version() %}{{ return('0.6.0') }}{% endmacro %}
