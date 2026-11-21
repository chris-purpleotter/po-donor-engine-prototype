{#
  A SQL string literal for a value from config (e.g. a segment label), safe on every warehouse.
      pocore_helpers__string_literal("Donors who've lapsed")
        -> BigQuery: 'Donors who\'ve lapsed'     (BigQuery has no '' escape: it reads two literals)
        -> others:   'Donors who''ve lapsed'     (standard SQL)
  SPEC D10, BigQuery trap 7.
#}

{% macro pocore_helpers__string_literal(value) %}
    {{- return(adapter.dispatch('pocore_helpers__string_literal', 'po_core')(value)) -}}
{% endmacro %}

{% macro default__pocore_helpers__string_literal(value) -%}
    '{{ value | replace("'", "''") }}'
{%- endmacro %}

{% macro bigquery__pocore_helpers__string_literal(value) -%}
    '{{ value | replace("\\", "\\\\") | replace("'", "\\'") }}'
{%- endmacro %}
