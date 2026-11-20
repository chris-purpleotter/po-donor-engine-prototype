{#
  pocore_foundation__person — ONE ROW PER PERSON: the PERSON DIMENSION of the foundation star.
  Everyone in the `people` contract, with or without gifts.

  Who each person is: contract attributes and the client's attr_* columns, as they are NOW
  (current values, D7), plus where the record came from (lineage). No state and no measures:
  "what was true at a month-end" lives on pocore_foundation__person__month_end; "what happened
  in a month / year" on the _span tables; join on person_id.
#}

select
    people.person_id,
    {%- for c in pocore_snapshot_columns('attributes') %}
    {{ 'person_attributes.' if c.startswith('attr_') else 'people.' }}{{ c }},
    {%- endfor %}
    people.source_system,
    people.source_record_id
from {{ ref('pocore_input__people') }} as people
left join {{ ref('pocore_input__person_attributes') }} as person_attributes
    on person_attributes.person_id = people.person_id
