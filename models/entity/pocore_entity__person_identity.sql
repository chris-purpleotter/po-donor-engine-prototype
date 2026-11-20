{#
  pocore_entity__person_identity — ONE ROW PER SOURCE RECORD -> the person it belongs to (the
  identity crosswalk), from pocore_input__person_identities. ENTITY layer, so the foundation
  never reads input directly.
#}

select
    source_system,
    source_record_id,
    person_id
from {{ ref('pocore_input__person_identities') }}
