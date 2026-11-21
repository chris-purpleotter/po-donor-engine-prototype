-- The identity crosswalk (v0.4.0): one row per source record -> person_id.
-- Resolving identities (which CRM contact and which email-tool contact are the same
-- person) is
-- conform's job; this model makes the result part of the contract so every row can be
-- traced.
-- var person_identities_model set:  the client's crosswalk (source_system,
-- source_record_id, person_id)
-- not set:                          one identity per person, from the people
-- contract's lineage columns
{% if var("person_identities_model", none) %}
    select
        cast(source_system as {{ dbt.type_string() }}) as source_system,
        cast(source_record_id as {{ dbt.type_string() }}) as source_record_id,
        cast(person_id as {{ dbt.type_string() }}) as person_id
    from {{ pocore_client_config__input_model("person_identities") }}
{% else %}
    select source_system, source_record_id, person_id
    from {{ ref("pocore_input__people") }}
    where source_system is not null and source_record_id is not null
{% endif %}
