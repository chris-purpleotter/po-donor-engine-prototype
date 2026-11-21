{#
  The engine's money type, per warehouse (SPEC D14).

  Why a macro: no single spelling works everywhere.
    - Unqualified `numeric` has a different default precision per warehouse
      (DuckDB 18,3; Snowflake 38,0 = cents dropped).
    - BigQuery rejects parameterized types in CAST (`numeric(18,2)` fails),
      but its plain NUMERIC is fixed at 38 digits / 9 decimal places, so it's
      safe for cents.

  Used in both the canonical model's cast and the contract's data_type.
#}

{% macro pocore_helpers__type_money() %}
    {{ return(adapter.dispatch('pocore_helpers__type_money', 'po_core')()) }}
{% endmacro %}

{% macro default__pocore_helpers__type_money() %}
    {{ return('numeric(18,2)') }}
{% endmacro %}

{% macro bigquery__pocore_helpers__type_money() %}
    {{ return('numeric') }}
{% endmacro %}
