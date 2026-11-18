{{ config(enabled=pocore_module_enabled('pack')) }}

{#
  pocore_export__pack_settings — ONE ROW PER SETTING (key, value) for the Planning Pack:
  the client's pack var (with defaults), plus the engine version and as_of, so the pack tool
  reads everything from the warehouse and needs no config of its own.
#}

{%- set s = pocore_pack_settings() -%}
{%- set rows = [
    ('client_name', s.client_name),
    ('window_days', s.window_days),
    ('holdout_pct', s.holdout_pct),
    ('min_group_size', s.min_group_size),
    ('engine_version', pocore_version()),
    ('as_of', var('as_of')),
] -%}

{% for k, v in rows %}
select
    '{{ k }}'                                                       as setting,
    cast({{ pocore_string_literal(v | string) }} as {{ dbt.type_string() }}) as value
{% if not loop.last %}union all{% endif %}
{% endfor %}
