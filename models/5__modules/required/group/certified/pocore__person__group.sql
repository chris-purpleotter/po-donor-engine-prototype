{#
  pocore__person__group — ONE ROW PER PERSON x GROUP, as of the latest month-end.
  The roster: "who is in this group right now?", the list someone acts on (mailing, calls,
  CRM tag). Counting rows for one group = counting its people. A person can be in several
  groups (custom groups may overlap), so filter to one group before counting.

  Certified (a convenience table): who the person is (pocore_foundation__person) and their state
  at that month-end (pocore_foundation__person__month_end) are repeated for display and filtering.
#}

with

pocore_group__membership__month as (select * from {{ ref('pocore_group__membership__month') }}),

pocore_foundation__person as (select * from {{ ref('pocore_foundation__person') }}),

pocore_foundation__person__month_end as (select * from {{ ref('pocore_foundation__person__month_end') }}),

latest as (

    select max(month_end_date) as month_end_date
    from pocore_group__membership__month

)

select
    membership.person_id,
    membership.group_id,
    membership.group_label,
    membership.group_source,
    membership.parent_group_id,
    membership.split_by,
    membership.split_value,
    membership.group_set_id,
    membership.month_end_date,
    month_end.lifecycle_stage,
    person.acquisition_channel,
    person.region,
    month_end.first_gift_date,
    month_end.first_gift_band,
    month_end.last_gift_date,
    month_end.days_since_last_gift,
    month_end.gift_count_lifetime,
    month_end.net_giving_lifetime,
    month_end.net_giving_12m,
    month_end.is_recurring_active,
    month_end.is_reactivated
    {%- for c in var('people_extra_columns') %},
    person.attr_{{ c }}
    {%- endfor %}
from pocore_group__membership__month as membership
inner join latest
    on membership.month_end_date = latest.month_end_date
inner join pocore_foundation__person as person
    on person.person_id = membership.person_id
inner join pocore_foundation__person__month_end as month_end
    on  month_end.person_id      = membership.person_id
    and month_end.month_end_date = membership.month_end_date
