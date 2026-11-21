{#
  The SQL for ONE custom rollup (one item of pocore_client_config__rollups()), used inside the roll-up step of
  pocore_rollup__person__month_end_lookback, where each person x month-end row (`donor_dates`) is
  joined to that person's gifts on or before the month-end (`gifts`). Returns e.g.

      count(case when gifts.rollup_match_1 and not gifts.is_refund then 1 end)

    r             the rollup: agg, column, where, window (see pocore_client_config__rollups)
    match_column  the true/false column on `gifts` that holds the rollup's `where` result
                  (computed once per gift in the model's `gifts` CTE)

  Step 1. The conditions a gift must meet, joined with `and`:
    - the rollup's `where`   -> match_column (only if the rollup has a `where`)
    - refunds (D6)           -> ignored, unless agg is `sum` (sums are net of refunds)
    - the window             -> ytd: same calendar year as the month-end
                                <N>m / <N>d: within the N months / days before the month-end
                                lifetime: no condition
    With no conditions at all: `gifts.gift_id is not null`. A person with no gifts still gets
    one row from the left join, with every gift column null; this keeps that row from
    counting as a gift (count 0, not 1).

  Step 2. Wrap the conditions in the aggregate:
    count       how many gifts match
    any         true if at least one matches
    sum         total of `column` over matching gifts (0 if none)
    max / min   largest / smallest `column` among matching gifts (null if none)
    days_since  days from the latest matching gift to the month-end (null if none)
#}
{% macro pocore_sql__rollup(r, match_column) %}
    {#- Step 1: conditions -#}
    {%- set conditions = [] -%}
    {%- if r.where -%}
        {%- do conditions.append(match_column) -%}
    {%- endif -%}
    {%- if r.agg != 'sum' -%}
        {%- do conditions.append("not gifts.is_refund") -%}
    {%- endif -%}
    {%- if r.window == 'ytd' -%}
        {%- do conditions.append("extract(year from gifts.gift_date) = extract(year from donor_dates.snapshot_date)") -%}
    {%- elif r.window.endswith('m') -%}
        {%- set months = r.window[:-1] | int -%}
        {%- do conditions.append("gifts.gift_date > " ~ dbt.dateadd("month", -months, "donor_dates.snapshot_date")) -%}
    {%- elif r.window.endswith('d') -%}
        {%- set days = r.window[:-1] | int -%}
        {%- do conditions.append("gifts.gift_date > " ~ dbt.dateadd("day", -days, "donor_dates.snapshot_date")) -%}
    {%- endif -%}
    {%- set cond = conditions | join(" and ") if conditions else "gifts.gift_id is not null" -%}

    {#- Step 2: the aggregate -#}
    {%- if r.agg == 'count' -%}
        {%- set sql = "count(case when " ~ cond ~ " then 1 end)" -%}
    {%- elif r.agg == 'any' -%}
        {%- set sql = "(count(case when " ~ cond ~ " then 1 end) > 0)" -%}
    {%- elif r.agg == 'sum' -%}
        {%- set sql = "coalesce(sum(case when " ~ cond ~ " then gifts." ~ r.column ~ " end), 0)" -%}
    {%- elif r.agg in ('max', 'min') -%}
        {%- set sql = r.agg ~ "(case when " ~ cond ~ " then gifts." ~ r.column ~ " end)" -%}
    {%- elif r.agg == 'days_since' -%}
        {%- set sql = dbt.datediff("max(case when " ~ cond ~ " then gifts.gift_date end)", "donor_dates.snapshot_date", "day") -%}
    {%- endif -%}
    {{ return(sql) }}
{% endmacro %}
