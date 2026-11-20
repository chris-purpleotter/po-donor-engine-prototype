{#
  pocore_admin__reconciliation — the sign-off numbers (SPEC §6.4).
  ONE ROW PER month x gift_category x person_type x eligibility/exclusion_reason x gift_type x refund.

  Every gift in the canonical input is here exactly once (nothing is dropped, including gifts
  after as_of, which are flagged). gifts and net_amount ADD UP across any grouping, so any tool
  can total it however it likes:
    "2025: $4.2M = $3.9M eligible + $180K capital_campaign + $120K event_fmv"
    recurring share by month = recurring gifts / all non-refund gifts
  No distinct-donor counts here: they don't add up across rows (see pocore_admin__health).
#}


with gifts as (

    select
        g.*,
        coalesce(d.person_type, 'unknown')   as person_type
    from {{ ref('pocore_input__gifts') }} as g
    left join {{ ref('pocore_input__people') }} as d
        on d.person_id = g.person_id

)

select
    {{ pocore_fiscal_year('gift_date') }}                          as giving_year,
    cast({{ dbt.date_trunc('month', 'gift_date') }} as date)     as gift_month,
    gift_category,
    person_type,
    is_kpi_eligible,
    exclusion_reason,
    gift_type,
    is_refund,
    (gift_date > {{ pocore_as_of_date() }})                                as is_after_as_of,
    count(*)                                                     as gifts,
    sum(amount)                                                  as net_amount
from gifts
group by
    {{ pocore_fiscal_year('gift_date') }},
    cast({{ dbt.date_trunc('month', 'gift_date') }} as date),
    gift_category, person_type, is_kpi_eligible, exclusion_reason, gift_type, is_refund,
    (gift_date > {{ pocore_as_of_date() }})
