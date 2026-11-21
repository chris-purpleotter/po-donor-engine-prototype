{#- Just the ids, in order: ['gave', 'started_monthly', 'retained']. -#}
{% macro pocore_engine_config__measure_ids() %}
    {{ return(pocore_engine_config__measures() | map(attribute='id') | list) }}
{% endmacro %}
