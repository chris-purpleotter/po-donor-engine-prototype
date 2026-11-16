{#
  Client-chosen extra donor columns (SPEC §6.5), passed through from the same conform
  model as pode_can__donors and renamed attr_<name>.

  Not contracted: the column list is the client's choice (var `donors_extra_columns`).
  Values pass through as-is (no casting). They flow into pode_ftr__donor_snapshot, so they
  can be used in segment rules and baseline breakdowns.

  D7 applies: current values only, so only attributes that DON'T change because of giving
  (board member, volunteer, wealth rating, ...). Never donor status / major-donor flags.
#}

{%- set extra = var('donors_extra_columns') -%}

select
    cast(donor_id as {{ dbt.type_string() }}) as donor_id
    {%- for c in extra %},
    {{ c }} as attr_{{ c }}
    {%- endfor %}
from {{ pode_input_model('donors') }}
