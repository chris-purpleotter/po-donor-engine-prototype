{#
  pocore_foundation__person — ONE ROW PER PERSON: the PERSON DIMENSION of the foundation star.
  Everyone in the `people` contract, with or without gifts.

  Who each person is: contract attributes and the client's attr_* columns, as they are NOW
  (current values, D7), plus where the record came from (lineage). No state and no measures:
  "what was true at a month-end" lives on pocore_foundation__person__month_end; "what happened
  in a month / year" on the _span tables; join on person_id.
#}

with

pocore_entity__person as (select * from {{ ref('pocore_entity__person') }})

select * from pocore_entity__person
