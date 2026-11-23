-- depends_on: {{ ref('pocore_foundation__person') }}
-- depends_on: {{ ref('pocore_foundation__person__month_end') }}
-- v0.4.0: the foundation is a STAR. Zero rows = pass.
-- 1. The person DIMENSION holds who the person is, not state; the month_end SNAPSHOT holds state,
--    not who the person is (no copied attributes).
-- 2. The CALENDAR covers every fact's date and has exactly one latest month-end.
-- 3. Lineage: every gift and person has its source record.

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

-- 2. the calendar covers every fact's date, with one latest month-end
union all
select 'calendar', 'a gift date or month-end is missing from the calendar'
where exists (select 1 from {{ ref('pocore_foundation__gift') }} as gift
              left join {{ ref('pocore_foundation__date') }} as calendar on calendar.date_day = gift.gift_date
              where calendar.date_day is null and gift.gift_date <= (select max(date_day) from {{ ref('pocore_foundation__date') }}))
   or exists (select 1 from {{ ref('pocore_foundation__person__month_end') }} as month_end
              left join {{ ref('pocore_foundation__date') }} as calendar on calendar.date_day = month_end.month_end_date
              where calendar.date_day is null)
union all
select 'calendar', 'not exactly one latest month-end'
where (select count(*) from {{ ref('pocore_foundation__date') }} where is_latest_month_end) <> 1

-- 3. lineage
union all
select 'lineage', 'gift or person without source_record_id'
where exists (select 1 from {{ ref('pocore_foundation__gift') }} where source_record_id is null)
   or exists (select 1 from {{ ref('pocore_foundation__person') }} where source_record_id is null)
