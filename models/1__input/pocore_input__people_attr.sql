{#
  Client-chosen extra donor columns (SPEC §6.5), passed through from the same conform
  model as pocore_input__people and renamed attr_<name>.

  Not contracted: the column list is the client's choice (var `people_extra_columns`).
  Values pass through as-is (no casting). They flow into pocore_rollup__person__month_end_lookback, so they
  can be used in group rules and baseline breakdowns.

  D7 applies: current values only, so only attributes that DON'T change because of giving
  (board member, volunteer, wealth rating, ...). Never donor status / major-donor flags.
#}
{%- set extra = var("people_extra_columns") -%}

select
    cast(person_id as {{ dbt.type_string() }}) as person_id
    {%- for c in extra %}, {{ c }} as attr_{{ c }} {%- endfor %}
from {{ pocore_client_config__input_model("people") }}
