-- Contract gate for donors (SPEC §6.1).
-- Includes zero-gift contacts (prospects). Same pattern as pocore_can__gifts:
-- explicit columns, exact types, upstream resolved by pocore_input_model('people').

select
    cast(person_id            as {{ dbt.type_string() }}) as person_id,
    cast(created_at          as date)                    as created_at,
    cast(region              as {{ dbt.type_string() }}) as region,
    cast(acquisition_channel as {{ dbt.type_string() }}) as acquisition_channel,
    cast(acquisition_theme   as {{ dbt.type_string() }}) as acquisition_theme,
    cast(person_type          as {{ dbt.type_string() }}) as person_type,
    cast(is_deceased         as boolean)                 as is_deceased
from {{ pocore_input_model('people') }}
