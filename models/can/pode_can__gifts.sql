-- Contract gate for gifts (SPEC §6.2).
-- Conform (client side) does the standardizing; this model only selects the
-- contract columns with exact types. A missing column or wrong type fails here,
-- and `dbt build` skips everything downstream.
--
-- pode_input_model('gifts'): resolves var('gifts_model') (default 'gifts') to the
-- client's model via ref(project_name, ...), so dbt builds it first.

select
    cast(gift_id               as {{ dbt.type_string() }})  as gift_id,
    cast(donor_id              as {{ dbt.type_string() }})  as donor_id,
    cast(gift_date             as date)                     as gift_date,
    cast(amount                as {{ pode_type_money() }})  as amount,   -- per-warehouse money type (see macro)
    cast(gift_type             as {{ dbt.type_string() }})  as gift_type,
    cast(recurring_schedule_id as {{ dbt.type_string() }})  as recurring_schedule_id,
    cast(is_refund             as boolean)                  as is_refund,
    cast(gift_category         as {{ dbt.type_string() }})  as gift_category,
    cast(is_kpi_eligible       as boolean)                  as is_kpi_eligible,
    cast(exclusion_reason      as {{ dbt.type_string() }})  as exclusion_reason
from {{ pode_input_model('gifts') }}
