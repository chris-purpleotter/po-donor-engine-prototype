{#
  pocore_entity__person — ONE ROW PER PERSON: everyone in the `people` contract, with or without
  gifts. ENTITY layer: one row per thing that exists, with its attributes as they are now
  (contract columns, the client's attr_* columns, lineage), joined once. Everything downstream
  reads people from here, never from pocore_input__*.

  The slot for engine-standard person attributes: if the engine ever derives one for every
  client (an age band from a birth date, a standard region), it is computed here.
#}
with

pocore_input__people as (select * from {{ ref('pocore_input__people') }}),

pocore_input__people_attr as (select * from {{ ref('pocore_input__people_attr') }})

select
    pocore_input__people.person_id,
    {%- for c in pocore_columns__person() %}
        {{ "pocore_input__people_attr." if c.startswith("attr_") else "pocore_input__people." }}{{ c }},
    {%- endfor %}
    pocore_input__people.source_system,
    pocore_input__people.source_record_id
from pocore_input__people
left join
    pocore_input__people_attr
    on pocore_input__people_attr.person_id = pocore_input__people.person_id
