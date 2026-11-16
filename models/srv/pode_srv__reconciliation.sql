{#
  pode_srv__reconciliation — the sign-off numbers (SPEC §6.4).
  ONE ROW PER month x gift_category x donor_type x eligibility/exclusion_reason x gift_type x refund.

  Every gift in the canonical input is here exactly once (nothing is dropped, including gifts
  after as_of, which are flagged). gifts and net_amount ADD UP across any grouping, so any tool
  can total it however it likes:
    "2025: $4.2M = $3.9M eligible + $180K capital_campaign + $120K event_fmv"
    recurring share by month = recurring gifts / all non-refund gifts
  No distinct-donor counts here: they don't add up across rows (see pode_srv__project_health).
#}

{%- set as_of_sql = "cast('" ~ var('as_of') ~ "' as date)" -%}

with gifts as (

    select
        g.*,
        coalesce(d.donor_type, 'unknown')   as donor_type
    from {{ ref('pode_can__gifts') }} as g
    left join {{ ref('pode_can__donors') }} as d
        on d.donor_id = g.donor_id

)

select
    {{ pode_fiscal_year('gift_date') }}                          as giving_year,
    cast({{ dbt.date_trunc('month', 'gift_date') }} as date)     as gift_month,
    gift_category,
    donor_type,
    is_kpi_eligible,
    exclusion_reason,
    gift_type,
    is_refund,
    (gift_date > {{ as_of_sql }})                                as is_after_as_of,
    count(*)                                                     as gifts,
    sum(amount)                                                  as net_amount
from gifts
group by
    {{ pode_fiscal_year('gift_date') }},
    cast({{ dbt.date_trunc('month', 'gift_date') }} as date),
    gift_category, donor_type, is_kpi_eligible, exclusion_reason, gift_type, is_refund,
    (gift_date > {{ as_of_sql }})
