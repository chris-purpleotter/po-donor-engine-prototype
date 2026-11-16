{#
  Client-chosen extra gift columns (SPEC §6.5), passed through from the same conform
  model as pode_can__gifts and renamed attr_<name> (e.g. campaign_code, payment_method).

  Not contracted: the column list is the client's choice (var `gifts_extra_columns`).
  Day one: available for gift-level analysis. Turning them into donor-level features
  ("gave to the spring appeal") is a later step.
#}

{%- set extra = var('gifts_extra_columns') -%}

select
    cast(gift_id as {{ dbt.type_string() }}) as gift_id
    {%- for c in extra %},
    {{ c }} as attr_{{ c }}
    {%- endfor %}
from {{ pode_input_model('gifts') }}
