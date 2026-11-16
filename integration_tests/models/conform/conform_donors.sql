-- Fake client's conform model: raw CRM-style donors -> canonical shape.
-- In a real client this is where the per-client translation work lives.

select
    Id                                   as donor_id,       -- household grain (D2)
    cast(CreatedDate as date)            as created_at,
    MailingState                         as region,
    LeadSource                           as acquisition_channel,
    Theme                                as acquisition_theme,
    case RecordType
        when 'Organization' then 'organization'
        else 'individual'
    end                                  as donor_type,
    coalesce(Deceased, false)            as is_deceased,
    -- extra (non-contract) column, brought through via donors_extra_columns
    coalesce(BoardMember, false)         as is_board_member,
    -- optional cost data: turns on CPA and LTV:CPA in pode_srv__sustainer_ltv
    cast(AcquisitionCost as double)      as acquisition_cost
from {{ ref('raw_donors') }}
