{#
  Clamp a value to [low, high], identically on every warehouse (D10 trap 8).

      {{ pocore_helpers__clamp('revenue_uncapped_90d', 0, 1000) }}

  Why not least()/greatest(): their NULL handling differs by warehouse (BigQuery, Snowflake and
  Databricks return NULL if ANY argument is NULL; Postgres, Redshift and DuckDB ignore NULLs),
  and SQL Server only has them from 2022. A plain CASE behaves the same everywhere: a NULL
  input stays NULL. Pass `none` for low or high to leave that side open.
#}

{% macro pocore_helpers__clamp(expr, low=none, high=none) %}
    {%- if low is none and high is none -%}
        {{ exceptions.raise_compiler_error("po_core: pocore_helpers__clamp needs at least one of low / high") }}
    {%- endif -%}
    case
        {%- if low is not none %}
        when {{ expr }} < {{ low }} then {{ low }}
        {%- endif %}
        {%- if high is not none %}
        when {{ expr }} > {{ high }} then {{ high }}
        {%- endif %}
        else {{ expr }}
    end
{%- endmacro %}
