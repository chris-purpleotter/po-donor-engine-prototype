-- Contract gate for donors (SPEC §6.1).
-- Includes zero-gift contacts (prospects). Same pattern as pode_can__gifts:
-- explicit columns, exact types, upstream resolved by pode_input_model('donors').

select
    cast(donor_id            as {{ dbt.type_string() }}) as donor_id,
    cast(created_at          as date)                    as created_at,
    cast(region              as {{ dbt.type_string() }}) as region,
    cast(acquisition_channel as {{ dbt.type_string() }}) as acquisition_channel,
    cast(acquisition_theme   as {{ dbt.type_string() }}) as acquisition_theme,
    cast(donor_type          as {{ dbt.type_string() }}) as donor_type,
    cast(is_deceased         as boolean)                 as is_deceased
from {{ pode_input_model('donors') }}
