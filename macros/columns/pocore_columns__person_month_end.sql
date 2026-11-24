{#
  The looking-back columns of pocore_foundation__person__month_end: what was true about each
  person AS OF a month-end, worked out from their gifts up to that date.

  Built from config, so you never edit this for a client:
    - the engine's standard columns (fixed list below, calculated in
      pocore_rollup__person__month_end_lookback)
    - plus one rollup_* column per entry in the client's `rollups` var

  Edit this only when the ENGINE gains a new standard column for every client: calculate it
  in pocore_rollup__person__month_end_lookback, then add its name here.
  Used by: pocore_foundation__person__month_end and the group module (group rules can use
  these; the looking-AHEAD outcome columns are deliberately not in this list, so rules can't peek).
#}
{% macro pocore_columns__person_month_end() %}
    {%- set columns = [
        'lifecycle_stage', 'is_new_donor', 'is_reactivated', 'is_recurring_active', 'gave_prior_year_not_ytd',
        'first_gift_date', 'first_gift_amount', 'first_gift_band', 'first_gift_year',
        'last_gift_date', 'last_gift_year',
        'days_since_first_gift', 'days_since_last_gift', 'days_since_last_recurring',
        'days_since_reactivation', 'reactivations_lifetime',
        'gift_count_12m', 'net_giving_12m', 'gift_count_lifetime', 'net_giving_lifetime',
        'net_giving_ytd', 'net_giving_prior_year',
        'largest_gift_lifetime', 'largest_gift_12m', 'last_gift_amount'
    ] -%}
    {%- for rollup in pocore_client_config__rollups() -%}
        {%- do columns.append(rollup.name) -%}
    {%- endfor -%}
    {{ return(columns) }}
{% endmacro %}
