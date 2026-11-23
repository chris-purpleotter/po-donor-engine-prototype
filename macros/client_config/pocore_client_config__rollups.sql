{#
  Custom rollups (client var `rollups`): extra person-level columns built from a row-level
  source, as of each month-end, so segment rules and report dropdowns can use gift facts.

      rollups:
        - {source: gift, agg: count, label: 100_plus, where: "amount >= 100", window: lifetime}
        - {source: gift, agg: sum, column: amount, label: emergency, where: "gift_category = 'emergency'", window: 12m}
        - {source: gift, agg: max, column: amount, window: 12m}

  Column name, built by the engine:  rollup_{source}_{agg}[_{column}][_{label}]_{window}
      -> rollup_gift_count_100_plus_lifetime, rollup_gift_sum_amount_emergency_12m, rollup_gift_max_amount_12m
  Change the definition and the name changes with it, so a segment rule using the old name
  fails loudly instead of silently meaning something else. The one exception: changing a
  `where` but keeping its `label`. Change the label too (like bumping a segment's _v1).

    source  the row-level model: gift (pocore_event__gift; eligible gifts only)
    agg     count | sum | max | min | any (true/false) | days_since (days since the latest match)
    column  the gift column to sum / max / min (required for those, not allowed otherwise)
    where   optional SQL over that source's columns; needs a `label` (the name can't come from SQL)
    window  lifetime | ytd | <N>m (months) | <N>d (days), counted back from each month-end

  Refunds follow the engine's rule (D6): `sum` is net of refunds; every other agg ignores them.
  Peeking is impossible: only gifts on or before each month-end are ever seen.

  Returns the validated list, each with its `name` added. The SQL for each one comes from
  macro pocore_sql__rollup, used in pocore_rollup__person__month_end_lookback.
#}
{% macro pocore_client_config__rollups() %}
    {%- set sources = ['gift'] -%}
    {%- set aggs = ['count', 'sum', 'max', 'min', 'any', 'days_since'] -%}
    {%- set needs_column = ['sum', 'max', 'min'] -%}
    {%- set snake = '^[a-z][a-z0-9_]*$' -%}
    {%- set out = [] -%}
    {%- set names = [] -%}
    {%- for r in var('rollups', []) or [] -%}
        {%- set where_txt = r.get('where') -%}
        {%- set label = r.get('label') -%}
        {%- set column = r.get('column') -%}
        {%- set window = r.get('window') | string -%}
        {%- if r.get('source') not in sources -%}
            {{ exceptions.raise_compiler_error("po_core: rollup " ~ r ~ ": source must be one of " ~ sources | join(', ')) }}
        {%- endif -%}
        {%- if r.get('agg') not in aggs -%}
            {{ exceptions.raise_compiler_error("po_core: rollup " ~ r ~ ": agg must be one of " ~ aggs | join(', ')) }}
        {%- endif -%}
        {%- if r.agg in needs_column and not column -%}
            {{ exceptions.raise_compiler_error("po_core: rollup " ~ r ~ ": agg '" ~ r.agg ~ "' needs a column (e.g. column: amount)") }}
        {%- endif -%}
        {%- if r.agg not in needs_column and column -%}
            {{ exceptions.raise_compiler_error("po_core: rollup " ~ r ~ ": agg '" ~ r.agg ~ "' doesn't take a column") }}
        {%- endif -%}
        {%- if column and not modules.re.match(snake, column) -%}
            {{ exceptions.raise_compiler_error("po_core: rollup " ~ r ~ ": column must be a plain column name") }}
        {%- endif -%}
        {%- if where_txt and not label -%}
            {{ exceptions.raise_compiler_error("po_core: rollup " ~ r ~ ": a `where` needs a `label` (it becomes part of the column name)") }}
        {%- endif -%}
        {%- if label and not modules.re.match('^[a-z0-9][a-z0-9_]*$', label | string) -%}
            {{ exceptions.raise_compiler_error("po_core: rollup " ~ r ~ ": label must be lowercase snake_case, e.g. 100_plus or emergency") }}
        {%- endif -%}
        {%- if not modules.re.match('^(lifetime|ytd|[1-9][0-9]*[md])$', window) -%}
            {{ exceptions.raise_compiler_error("po_core: rollup " ~ r ~ ": window must be lifetime, ytd, <N>m or <N>d (e.g. 12m, 90d)") }}
        {%- endif -%}
        {%- set parts = ['rollup', r.source, r.agg] -%}
        {%- if column -%}{%- do parts.append(column) -%}{%- endif -%}
        {%- if label -%}{%- do parts.append(label | string) -%}{%- endif -%}
        {%- do parts.append(window) -%}
        {%- set name = parts | join('_') -%}
        {%- if name in names -%}
            {{ exceptions.raise_compiler_error("po_core: two rollups both produce the column " ~ name ~ "; give one a different label") }}
        {%- endif -%}
        {%- do names.append(name) -%}
        {%- do out.append({'name': name, 'source': r.source, 'agg': r.agg, 'column': column,
                           'where': where_txt, 'window': window}) -%}
    {%- endfor -%}
    {{ return(out) }}
{% endmacro %}
