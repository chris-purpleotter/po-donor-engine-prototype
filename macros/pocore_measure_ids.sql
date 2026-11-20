{#- Just the ids, in order: ['gave', 'started_monthly', 'retained']. -#}
{% macro pocore_measure_ids() %}
    {{ return(pocore_measures() | map(attribute='id') | list) }}
{% endmacro %}
