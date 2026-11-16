{#
  Standard-normal quantile (z) for a probability (SPEC D11).
  SQL has no inverse-normal function and dbt Jinja has no math module, so common
  quantiles are listed here. An unsupported value fails the build clearly; add a row.

      pode_z(0.975) -> 1.959964   (two-sided alpha = 0.05)
      pode_z(0.8)   -> 0.841621   (power = 0.8)
#}

{% macro pode_z(probability) %}
    {%- set table = {
        '0.800': 0.841621, '0.850': 1.036433, '0.900': 1.281552,
        '0.950': 1.644854, '0.975': 1.959964, '0.990': 2.326348, '0.995': 2.575829
    } -%}
    {%- set key = '%.3f' | format(probability | float) -%}
    {%- if key not in table -%}
        {{ exceptions.raise_compiler_error("po_donor_engine: no z-value for probability " ~ key ~ " (supported: " ~ (table.keys() | list | sort | join(', ')) ~ "). Add it to macros/pode_z.sql.") }}
    {%- endif -%}
    {{ return(table[key]) }}
{% endmacro %}
