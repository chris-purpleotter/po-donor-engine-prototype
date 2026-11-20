-- depends_on: {{ ref('pocore_foundation__person') }}
-- depends_on: {{ ref('pocore_foundation__person__month_end') }}
-- v0.4.0: the foundation is a STAR. Zero rows = pass.
-- 1. The person DIMENSION holds who the person is, not state; the month_end SNAPSHOT holds state,
--    not who the person is (no copied attributes).
-- 2. The SPAN facts add up: month spans, year spans and the gift fact give the same totals.
-- 3. Lineage: every gift and person has its source record; the default crosswalk has one
--    identity per person with lineage.

{%- set person_cols = [] %}
{%- set month_end_cols = [] %}
{%- if execute %}
    {%- for c in adapter.get_columns_in_relation(ref('pocore_foundation__person')) %}{% do person_cols.append(c.name | lower) %}{% endfor %}
    {%- for c in adapter.get_columns_in_relation(ref('pocore_foundation__person__month_end')) %}{% do month_end_cols.append(c.name | lower) %}{% endfor %}
{%- endif %}

-- 1. shape
{%- set state_on_person = [] %}
{%- for c in ['lifecycle_stage', 'net_giving_lifetime', 'days_since_last_gift', 'rollup_gift_count_100_plus_lifetime', 'as_of_month_end'] if c in person_cols %}{% do state_on_person.append(c) %}{% endfor %}
{%- set attrs_on_month_end = [] %}
{%- for c in ['region', 'acquisition_channel', 'person_type', 'is_deceased', 'attr_is_board_member'] if c in month_end_cols %}{% do attrs_on_month_end.append(c) %}{% endfor %}

select 'shape' as check_name, 'person dimension has state: {{ state_on_person | join(", ") }}' as problem
where {{ state_on_person | length }} > 0
union all
select 'shape', 'month_end snapshot has copied attributes: {{ attrs_on_month_end | join(", ") }}'
where {{ attrs_on_month_end | length }} > 0
union all
select 'shape', 'columns missing: expected lifecycle_stage on month_end and region on person'
where {{ 1 if ('lifecycle_stage' in month_end_cols and 'region' in person_cols) else 0 }} = 0

-- 2. spans tie to the gift fact
union all
select 'spans', 'month spans, year spans and gifts disagree on eligible totals'
from (
    select
        (select sum(amount) from {{ ref('pocore_foundation__person__month_span') }}) as month_amount,
        (select sum(amount) from {{ ref('pocore_foundation__person__year_span') }})  as year_amount,
        (select sum(amount) from {{ ref('pocore_foundation__gift') }} where is_kpi_eligible) as gift_amount,
        (select sum(gifts) from {{ ref('pocore_foundation__person__month_span') }}) as month_gifts,
        (select count(*) from {{ ref('pocore_foundation__gift') }} where is_kpi_eligible and not is_refund) as gift_count
) as totals
where month_amount is distinct from gift_amount
   or year_amount is distinct from gift_amount
   or month_gifts is distinct from gift_count

-- 3. lineage
union all
select 'lineage', 'gift or person without source_record_id'
where exists (select 1 from {{ ref('pocore_foundation__gift') }} where source_record_id is null)
   or exists (select 1 from {{ ref('pocore_foundation__person') }} where source_record_id is null)
union all
select 'lineage', 'default crosswalk is not one identity per person'
where (select count(*) from {{ ref('pocore_foundation__person_identity') }})
   <> (select count(*) from {{ ref('pocore_foundation__person') }} where source_record_id is not null)
