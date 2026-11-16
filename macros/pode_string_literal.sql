{#
  A SQL string literal for a value from config (e.g. a segment label), safe on every warehouse.
      pode_string_literal("Donors who've lapsed")
        -> BigQuery: 'Donors who\'ve lapsed'     (BigQuery has no '' escape: it reads two literals)
        -> others:   'Donors who''ve lapsed'     (standard SQL)
  SPEC D10, BigQuery trap 7.
#}

{% macro pode_string_literal(value) %}
    {{- return(adapter.dispatch('pode_string_literal', 'po_donor_engine')(value)) -}}
{% endmacro %}

{% macro default__pode_string_literal(value) -%}
    '{{ value | replace("'", "''") }}'
{%- endmacro %}

{% macro bigquery__pode_string_literal(value) -%}
    '{{ value | replace("\\", "\\\\") | replace("'", "\\'") }}'
{%- endmacro %}
