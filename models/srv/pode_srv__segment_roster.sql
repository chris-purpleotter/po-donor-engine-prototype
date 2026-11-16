{#
  pode_srv__segment_roster — ONE ROW PER SEGMENT x DONOR, as of the latest snapshot.
  "Who is in this segment right now?" — the list someone acts on (mailing, calls,
  CRM tag). Counting rows for one segment = counting its donors. A donor can appear in
  several segments (custom segments may overlap).
#}

with latest as (

    select max(snapshot_date) as snapshot_date
    from {{ ref('pode_ftr__donor_snapshot') }}

)

select
    m.segment_id,
    m.segment_label,
    m.segment_source,
    s.donor_id,
    s.snapshot_date,
    s.lifecycle_stage,
    s.acquisition_channel,
    s.region,
    s.first_gift_date,
    s.first_gift_band,
    s.last_gift_date,
    s.days_since_last_gift,
    s.gift_count_lifetime,
    s.net_giving_lifetime,
    s.net_giving_12m,
    s.is_recurring_active,
    s.is_reactivated
    {%- for c in var('donors_extra_columns') %},
    s.attr_{{ c }}
    {%- endfor %}
from {{ ref('pode_seg__membership') }} as m
inner join latest as l
    on m.snapshot_date = l.snapshot_date
inner join {{ ref('pode_ftr__donor_snapshot') }} as s
    on  s.donor_id   = m.donor_id
    and s.snapshot_date = m.snapshot_date
