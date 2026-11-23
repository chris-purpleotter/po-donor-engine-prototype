{{ config(enabled=pocore_client_config__module_enabled('insights')) }}

{#
  pocore_export__insights_dimensions — the "Build a population" dropdowns, in order.
  ONE ROW PER DIMENSION (plain columns: band_label/band_sql null) or PER BAND (banded ones).
  band_sql is the exact SQL the report puts into the segment rules it generates, so a tracked
  segment contains exactly the people someone saw in the report.
#}

{%- set s = pocore_client_config__insights_settings() -%}
{%- set str = dbt.type_string() -%}

{% for d in s.dimensions %}
{%- set dpos = loop.index %}
{%- if not loop.first %}
union all
{%- endif %}
{%- if d.bands %}
{%- for b in d.bands %}
{%- if not loop.first %}
union all
{%- endif %}
select
    '{{ d.name }}'                                                  as dimension,
    cast({{ pocore_helpers__string_literal(d.label) }} as {{ str }})        as label,
    {{ dpos }}                                                      as dimension_position,
    cast({{ pocore_helpers__string_literal(b.label) }} as {{ str }})        as band_label,
    cast({{ pocore_helpers__string_literal(b.sql) }} as {{ str }})          as band_sql,
    {{ loop.index }}                                                as band_position
{%- endfor %}
{%- else %}
select
    '{{ d.name }}'                                                  as dimension,
    cast({{ pocore_helpers__string_literal(d.label) }} as {{ str }})        as label,
    {{ dpos }}                                                      as dimension_position,
    cast(null as {{ str }})                                         as band_label,
    cast(null as {{ str }})                                         as band_sql,
    cast(null as {{ dbt.type_int() }})                              as band_position
{%- endif %}
{% endfor %}
