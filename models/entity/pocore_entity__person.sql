{#
  pocore_entity__person — ONE ROW PER PERSON: everyone in the `people` contract, with or without
  gifts. ENTITY layer: one row per thing that exists, with its attributes as they are now
  (contract columns, the client's attr_* columns, lineage), joined once. Everything downstream
  reads people from here, never from pocore_input__*.

  The slot for engine-standard person attributes: if the engine ever derives one for every
  client (an age band from a birth date, a standard region), it is computed here.
#}
select
    people.person_id,
    {%- for c in pocore_columns__person() %}
        {{ "person_attributes." if c.startswith("attr_") else "people." }}{{ c }},
    {%- endfor %}
    people.source_system,
    people.source_record_id
from {{ ref("pocore_input__people") }} as people
left join
    {{ ref("pocore_input__person_attributes") }} as person_attributes
    on person_attributes.person_id = people.person_id
