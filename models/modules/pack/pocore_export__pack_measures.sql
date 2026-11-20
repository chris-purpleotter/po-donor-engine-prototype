{{ config(enabled=pocore_module_enabled('pack')) }}

{#
  pocore_export__pack_measures — ONE ROW PER MEASURE (a segment's primary_kpi), from
  pocore_measures(): how each one reads in text and whether its windows add up. Supporter
  Insights words its charts from this table, so a new measure needs no change to the pack.
#}

{%- set str = dbt.type_string() -%}

{% for m in pocore_measures() %}
select
    '{{ m.id }}'                                                    as kpi_id,
    {{ loop.index }}                                                as measure_position,
    cast({{ pocore_string_literal(m.name) }} as {{ str }})         as measure_name,
    cast({{ pocore_string_literal(m.phrase) }} as {{ str }})       as phrase,
    {{ 'true' if m.adds_up else 'false' }}                          as adds_up
{% if not loop.last %}union all{% endif %}
{% endfor %}
