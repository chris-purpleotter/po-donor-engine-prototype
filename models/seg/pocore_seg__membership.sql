{#
  pocore_seg__membership — who is in which segment at each snapshot date (SPEC §5a).
  One row per segment_id x person_id x snapshot_date. Segments may overlap (except within a set).

  Everything is a segment. Three ways to define them, all in config:
    1. a segment     a named, versioned filter on pocore_ftr__person_snapshot
                     (standard: pocore_standard_segments(); custom: the client's `segments` var)
    2. split_by      on a segment: ALSO one segment per value of that column
                     ("Lapsed — Web", "Lapsed — Face to Face" ...), segment_id = <id>__<value>.
                     Use low-cardinality columns only (channel, region, age group ...).
    3. a set         the client's `segment_sets` var: listed segments in priority order, each
                     person in the FIRST one they match, so the set's populations don't overlap;
                     include_remainder adds "<set>__remainder" (everyone else in the population).
                     segment_id = <set id>__<segment id>.
  Every row gets the default population filter (individuals, not deceased), and every rule is
  wrapped in brackets so an `or` inside it can't escape.

  Descriptive columns (carried through to the certified tables):
    parent_segment_id  the configured segment a split/set row comes from (its KPI and window
                       are used); the segment itself for plain rows; null for a set's remainder
    split_by, split_value   set for split rows
    segment_set_id     set for set rows
#}

{%- set custom = var('segments', []) -%}
{%- set segments = pocore_all_segments() -%}
{%- set sets = var('segment_sets', []) -%}
{%- set str = dbt.type_string() -%}

{#- Validate naming at compile time: fail loudly instead of producing odd segments. -#}
{%- set seen = [] -%}
{%- for s in segments -%}
    {%- if s.id in seen -%}
        {{ exceptions.raise_compiler_error("po_core: duplicate segment id '" ~ s.id ~ "'") }}
    {%- endif -%}
    {%- do seen.append(s.id) -%}
    {%- if not modules.re.match('^[a-z0-9_]+_v[0-9]+$', s.id) -%}
        {{ exceptions.raise_compiler_error("po_core: segment id '" ~ s.id ~ "' must be lowercase snake_case ending in _v<N>") }}
    {%- endif -%}
{%- endfor -%}
{%- for s in custom -%}
    {%- if not s.id.startswith('cust_') -%}
        {{ exceptions.raise_compiler_error("po_core: custom segment id '" ~ s.id ~ "' must start with cust_") }}
    {%- endif -%}
{%- endfor -%}
{%- set by_id = {} -%}
{%- for s in segments -%}{%- do by_id.update({s.id: s}) -%}{%- endfor -%}
{%- for st in sets -%}
    {%- if not modules.re.match('^set_[a-z0-9_]+_v[0-9]+$', st.id) -%}
        {{ exceptions.raise_compiler_error("po_core: segment set id '" ~ st.id ~ "' must look like set_<name>_v<N>") }}
    {%- endif -%}
    {%- for sid in st.segments -%}
        {%- if sid not in by_id -%}
            {{ exceptions.raise_compiler_error("po_core: segment set '" ~ st.id ~ "' lists unknown segment '" ~ sid ~ "'") }}
        {%- endif -%}
    {%- endfor -%}
{%- endfor -%}

{%- if var('baseline_breakdowns', none) is not none -%}
    {{ exceptions.raise_compiler_error("po_core: var 'baseline_breakdowns' was removed in v0.3.0. Use split_by on a segment instead (e.g. split_by: acquisition_channel) to get one segment per value.") }}
{%- endif -%}

{%- set population = "person_type = 'individual' and not is_deceased" -%}

with snapshot as (
    select * from {{ ref('pocore_ftr__person_snapshot') }}
    where {{ population }}
)

{% for s in segments %}
{% if not loop.first %}union all{% endif %}
select
    '{{ s.id }}'                                                as segment_id,
    {{ pocore_string_literal(s.label) }}                        as segment_label,
    '{{ "standard" if s.id.startswith("std_") else "custom" }}' as segment_source,
    '{{ s.id }}'                                                as parent_segment_id,
    cast(null as {{ str }})                                     as split_by,
    cast(null as {{ str }})                                     as split_value,
    cast(null as {{ str }})                                     as segment_set_id,
    person_id,
    snapshot_date
from snapshot
where ({{ s.rule }})
{%- if s.split_by %}
{%- set value_sql = "coalesce(cast(" ~ s.split_by ~ " as " ~ str ~ "), 'unknown')" %}
union all
select
    {{ dbt.concat(["'" ~ s.id ~ "__'", "lower(replace(" ~ value_sql ~ ", ' ', '_'))"]) }} as segment_id,
    {{ dbt.concat([pocore_string_literal(s.label ~ ' — '), value_sql]) }}           as segment_label,
    '{{ "standard" if s.id.startswith("std_") else "custom" }}' as segment_source,
    '{{ s.id }}'                                                as parent_segment_id,
    '{{ s.split_by }}'                                          as split_by,
    {{ value_sql }}                                             as split_value,
    cast(null as {{ str }})                                     as segment_set_id,
    person_id,
    snapshot_date
from snapshot
where ({{ s.rule }})
{%- endif %}
{% endfor %}

{%- for st in sets %}
union all
select
    {{ dbt.concat(["'" ~ st.id ~ "__'", "chosen"]) }}           as segment_id,
    -- numbered in priority order, so "2. Lapsed" reads as "lapsed, not already in 1."
    case chosen
        {%- for sid in st.segments %}
        when '{{ sid }}' then {{ pocore_string_literal(loop.index ~ '. ' ~ by_id[sid].label) }}
        {%- endfor %}
        else {{ pocore_string_literal((st.segments | length + 1) ~ '. ' ~ st.get('remainder_label', 'Everyone else')) }}
    end                                                         as segment_label,
    'set'                                                       as segment_source,
    case when chosen = 'remainder' then cast(null as {{ str }}) else chosen end as parent_segment_id,
    cast(null as {{ str }})                                     as split_by,
    cast(null as {{ str }})                                     as split_value,
    '{{ st.id }}'                                               as segment_set_id,
    person_id,
    snapshot_date
from (
    select
        person_id,
        snapshot_date,
        case
            {%- for sid in st.segments %}
            when ({{ by_id[sid].rule }}) then '{{ sid }}'
            {%- endfor %}
            {%- if st.get('include_remainder', false) %}
            else 'remainder'
            {%- endif %}
        end as chosen
    from snapshot
) as assigned
where chosen is not null
{%- endfor %}
