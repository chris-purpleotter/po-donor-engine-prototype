{#
  The as-of date as SQL text: cast('2026-10-31' as date). Everything the engine builds is "as
  of" this date (var as_of, set by the client or the PO_AS_OF env var): no gift after it is
  seen, and an outcome window only counts as complete once it has ended by then.

  Returns SQL TEXT, not a date value, so it can go straight into SQL or into dbt's date macros:
      where gift_date <= {{ pocore_client_config__as_of_date() }}
      {{ dbt.dateadd('day', 1, pocore_client_config__as_of_date()) }}
  (`~` joins strings in Jinja: "cast('" ~ '2026-10-31' ~ "' as date)".)
#}
{% macro pocore_client_config__as_of_date() %}
    {{ return("cast('" ~ var('as_of') ~ "' as date)") }}
{% endmacro %}
