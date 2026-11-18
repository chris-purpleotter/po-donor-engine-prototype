-- Fake client's conform model: raw CRM-style opportunities -> canonical gifts.
-- Shows the D1 pattern: conform LABELS every revenue row; it never drops revenue.
-- (Pledges and lost opportunities aren't revenue, so they never enter gifts.)

with raw as (

    select * from {{ ref('raw_gifts') }}
    where StageName in ('Closed Won', 'Refunded')     -- this client's revenue stages

),

labelled as (

    select
        Id                                                   as gift_id,
        ContactId                                            as person_id,
        cast(CloseDate as date)                              as gift_date,
        case when RecordType = 'Refund'
             then -abs(Amount) else Amount end               as amount,
        case when RecurringDonationId is not null
             then 'recurring' else 'one_time' end            as gift_type,
        RecurringDonationId                                  as recurring_schedule_id,
        (RecordType = 'Refund')                              as is_refund,
        case RecordType
            when 'Grant'    then 'grant'
            when 'Matching' then 'matching'
            else 'cash'
        end                                                  as gift_category,
        CampaignCode                                         as campaign_code
    from raw

)

select
    gift_id,
    person_id,
    gift_date,
    amount,
    gift_type,
    recurring_schedule_id,
    is_refund,
    gift_category,

    -- Engine default + this client's rule. coalesce() matters: campaign_code is
    -- often null, and `null != 'X'` is NULL (not true), which would fail not_null.
    {{ po_core.pocore_default_kpi_eligible('gift_category') }}
        and coalesce(campaign_code, '') != 'CAPITAL-2026'    as is_kpi_eligible,

    case
        when not {{ po_core.pocore_default_kpi_eligible('gift_category') }}
            then 'category_' || gift_category
        when campaign_code = 'CAPITAL-2026'
            then 'capital_campaign'
    end                                                      as exclusion_reason,

    -- extra (non-contract) column, brought through via gifts_extra_columns
    campaign_code

from labelled
