{#
  The fiscal year a date falls in, named by the calendar year the fiscal year ENDS in
  (the common nonprofit convention: FY2026 = Apr 2025 - Mar 2026 when it starts in April).

  var fiscal_year_start_month: 1 = calendar year (default), 4 = April, 7 = July, ...

      pocore_fiscal_year('gift_date')   ->   SQL expression returning an integer year
#}

{% macro pocore_fiscal_year(date_expr) %}
    {%- set start = var('fiscal_year_start_month') | int -%}
    {%- if start == 1 -%}
        extract(year from {{ date_expr }})
    {%- else -%}
        {#- Shift forward so the fiscal year's first month lands in January of its end year. -#}
        extract(year from cast({{ dbt.dateadd('month', 13 - start, date_expr) }} as date))
    {%- endif -%}
{% endmacro %}
