{#- The engine version the pack checks it is compatible with (keep in step with dbt_project.yml). -#}
{% macro pocore_version() %}{{ return('0.3.8') }}{% endmacro %}
