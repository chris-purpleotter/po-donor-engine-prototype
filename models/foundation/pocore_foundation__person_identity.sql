{#
  pocore_foundation__person_identity — ONE ROW PER SOURCE RECORD: which person each record in
  each source system belongs to (the identity crosswalk). A person can have several identities
  (a CRM contact, an email-tool contact ...). Trace any person back to their source records,
  or any source record forward to the person: join on person_id.
#}

select
    source_system,
    source_record_id,
    person_id
from {{ ref('pocore_entity__person_identity') }}
