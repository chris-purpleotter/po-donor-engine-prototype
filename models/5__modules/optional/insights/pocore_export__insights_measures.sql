{{ config(enabled=pocore_client_config__module_enabled('insights')) }}

{#
  pocore_export__insights_measures — ONE ROW PER MEASURE (a group's primary_kpi), from
  pocore_engine_config__measures(): how each one reads in text and whether its windows add up. Supporter
  Insights words its charts from this table, so a new measure needs no change to the report.
#}

{%- set str = dbt.type_string() -%}

{% for m in pocore_engine_config__measures() %}
select
    '{{ m.id }}'                                                    as kpi_id,
    {{ loop.index }}                                                as measure_position,
    cast({{ pocore_helpers__string_literal(m.name) }} as {{ str }})         as measure_name,
    cast({{ pocore_helpers__string_literal(m.phrase) }} as {{ str }})       as phrase,
    {{ 'true' if m.adds_up else 'false' }}                          as adds_up
{% if not loop.last %}union all{% endif %}
{% endfor %}
