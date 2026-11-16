{#
  pode_seg__membership — who is in which segment at each snapshot date (SPEC §5a).
  One row per segment_id x donor_id x snapshot_date. Segments may overlap.

  A segment = a named, versioned filter on pode_ftr__donor_snapshot:
    standard segments come from pode_standard_segments(),
    custom segments from the client's `segments` var.
  Every rule gets the default filter (individuals, not deceased) and is wrapped in
  brackets so an `or` inside a rule can't escape it.
#}

{%- set custom = var('segments', []) -%}
{%- set segments = pode_all_segments() -%}

{#- Validate naming at compile time: fail loudly instead of producing odd segments. -#}
{%- set seen = [] -%}
{%- for s in segments -%}
    {%- if s.id in seen -%}
        {{ exceptions.raise_compiler_error("po_donor_engine: duplicate segment id '" ~ s.id ~ "'") }}
    {%- endif -%}
    {%- do seen.append(s.id) -%}
    {%- if not modules.re.match('^[a-z0-9_]+_v[0-9]+$', s.id) -%}
        {{ exceptions.raise_compiler_error("po_donor_engine: segment id '" ~ s.id ~ "' must be lowercase snake_case ending in _v<N>") }}
    {%- endif -%}
{%- endfor -%}
{%- for s in custom -%}
    {%- if not s.id.startswith('cust_') -%}
        {{ exceptions.raise_compiler_error("po_donor_engine: custom segment id '" ~ s.id ~ "' must start with cust_") }}
    {%- endif -%}
{%- endfor -%}

{% for s in segments %}
select
    '{{ s.id }}'                                           as segment_id,
    {{ pode_string_literal(s.label) }}                     as segment_label,
    '{{ "standard" if s.id.startswith("std_") else "custom" }}' as segment_source,
    donor_id,
    snapshot_date
from {{ ref('pode_ftr__donor_snapshot') }}
where ({{ s.rule }})
  and donor_type = 'individual'
  and not is_deceased
{% if not loop.last %}
union all
{% endif %}
{% endfor %}
