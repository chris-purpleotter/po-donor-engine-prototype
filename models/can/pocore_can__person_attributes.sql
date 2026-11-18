{#
  Client-chosen extra donor columns (SPEC §6.5), passed through from the same conform
  model as pocore_can__people and renamed attr_<name>.

  Not contracted: the column list is the client's choice (var `people_extra_columns`).
  Values pass through as-is (no casting). They flow into pocore_ftr__person_snapshot, so they
  can be used in segment rules and baseline breakdowns.

  D7 applies: current values only, so only attributes that DON'T change because of giving
  (board member, volunteer, wealth rating, ...). Never donor status / major-donor flags.
#}

{%- set extra = var('people_extra_columns') -%}

select
    cast(person_id as {{ dbt.type_string() }}) as person_id
    {%- for c in extra %},
    {{ c }} as attr_{{ c }}
    {%- endfor %}
from {{ pocore_input_model('people') }}
