-- Contract gate for donors (SPEC §6.1).
-- Includes zero-gift contacts (prospects). Same pattern as pocore_input__gifts:
-- explicit columns, exact types, upstream resolved by pocore_client_config__input_model('people').
select
    cast(person_id as {{ dbt.type_string() }}) as person_id,
    cast(created_at as date) as created_at,
    cast(region as {{ dbt.type_string() }}) as region,
    cast(acquisition_channel as {{ dbt.type_string() }}) as acquisition_channel,
    cast(acquisition_theme as {{ dbt.type_string() }}) as acquisition_theme,
    cast(person_type as {{ dbt.type_string() }}) as person_type,
    cast(is_deceased as boolean) as is_deceased,
    -- lineage (v0.4.0): where this person record came from, e.g. 'salesforce' /
    -- '0035e00000AbCdE'
    cast(source_system as {{ dbt.type_string() }}) as source_system,
    cast(source_record_id as {{ dbt.type_string() }}) as source_record_id
from {{ pocore_client_config__input_model("people") }}
