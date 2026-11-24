{{ config(enabled=pocore_client_config__module_enabled('insights')) }}

{#
  pocore_export__insights_tenure — ONE ROW PER GROUP x MONTH-END x TENURE BAND: how long the
  people in a group at that month-end had been in it (since the start of their current term,
  pocore__person__group__term). For the report's "What happened" tab: "of the prospects at
  Aug 2025, how many had joined in the last month, the last year, 2+ years ago".

  Bands: module__group.tenure_bands_months, e.g. [1, 2, 3, 4, 6, 12, 24] gives
  joined this month / 1 month / 2 months / 3 months / 4-5 months / 6-11 months / 1-2 years / 2+ years.
  Months, not days: groups are checked at month-ends.
  Someone in the group since before the engine's first month-end (is_joined_before_data) has
  been in AT LEAST that long: counted in the top band when that's long enough, else "unknown".
  The bands of one group at one month-end add up to its people_in_group.
#}

{%- set bounds = pocore_client_config__module('group').tenure_bands_months -%}
{%- if bounds | length == 0 or bounds != bounds | sort or bounds[0] < 1 -%}
    {{ exceptions.raise_compiler_error("po_core: module__group.tenure_bands_months must be whole months in increasing order, the first at least 1 (e.g. [1, 2, 3, 4, 6, 12, 24]); got " ~ bounds) }}
{%- endif -%}
{%- set top = bounds[-1] -%}
{#- one label per band: [lower, upper) in months -#}
{%- set bands = [] -%}
{%- set lowers = [0] + bounds[:-1] -%}
{%- for lo in lowers -%}
    {%- set hi = bounds[loop.index0] -%}
    {%- if hi - lo == 1 -%}
        {%- set label = 'joined this month' if lo == 0 else (lo ~ ' month' ~ ('' if lo == 1 else 's')) -%}
    {%- elif lo % 12 == 0 and hi % 12 == 0 and lo > 0 -%}
        {%- set label = (lo // 12) ~ '-' ~ (hi // 12) ~ ' years' -%}
    {%- else -%}
        {%- set label = lo ~ '-' ~ (hi - 1) ~ ' months' -%}
    {%- endif -%}
    {%- do bands.append({'order': loop.index, 'lo': lo, 'hi': hi, 'label': label}) -%}
{%- endfor -%}
{%- set top_label = ((top // 12) ~ '+ years') if top % 12 == 0 else (top ~ '+ months') -%}

with

pocore_group__membership__month as (select * from {{ ref('pocore_group__membership__month') }}),

pocore__person__group__term as (select * from {{ ref('pocore__person__group__term') }}),

-- each member at each month-end, with the term they were in and how many months since it started
members as (

    select
        pocore_group__membership__month.group_id,
        pocore_group__membership__month.month_end_date,
        pocore__person__group__term.is_joined_before_data,
        (extract(year from pocore_group__membership__month.month_end_date) * 12 + extract(month from pocore_group__membership__month.month_end_date))
          - (extract(year from pocore__person__group__term.joined_month_end) * 12 + extract(month from pocore__person__group__term.joined_month_end))
                                                                                    as months_in_group
    from pocore_group__membership__month
    inner join pocore__person__group__term
        on  pocore__person__group__term.person_id = pocore_group__membership__month.person_id
        and pocore__person__group__term.group_id  = pocore_group__membership__month.group_id
        and pocore_group__membership__month.month_end_date >= pocore__person__group__term.joined_month_end
        and (pocore__person__group__term.left_month_end is null
             or pocore_group__membership__month.month_end_date < pocore__person__group__term.left_month_end)

),

banded as (

    select
        group_id,
        month_end_date,
        case
            when months_in_group >= {{ top }} then {{ bands | length + 1 }}
            when is_joined_before_data then {{ bands | length + 2 }}
            {%- for band in bands %}
            when months_in_group < {{ band.hi }} then {{ band.order }}
            {%- endfor %}
        end                                                                         as band_order
    from members

)

select
    group_id,
    month_end_date,
    band_order,
    case band_order
        {%- for band in bands %}
        when {{ band.order }} then '{{ band.label }}'
        {%- endfor %}
        when {{ bands | length + 1 }} then '{{ top_label }}'
        else 'unknown (before our data)'
    end                                                                             as band_label,
    count(*)                                                                        as people
from banded
group by group_id, month_end_date, band_order
