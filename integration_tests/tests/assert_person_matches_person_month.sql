-- pocore_foundation__person must equal pocore_foundation__person__month at the latest month-end, on
-- EVERY column the two tables share (read from the warehouse at build time, not from a list), so
-- they can't drift apart. Zero rows = pass.

{%- set cols = [] %}
{%- if execute %}
    {%- set m_cols = adapter.get_columns_in_relation(ref('pocore_foundation__person__month')) | map(attribute='name') | map('lower') | list %}
    {%- for c in adapter.get_columns_in_relation(ref('pocore_foundation__person')) %}
        {%- if c.name | lower in m_cols and c.name | lower not in ['person_id', 'month_end_date'] %}
            {%- do cols.append(c.name | lower) %}
        {%- endif %}
    {%- endfor %}
{%- endif %}

with latest as (
    select * from {{ ref('pocore_foundation__person__month') }}
    where month_end_date = (select max(month_end_date) from {{ ref('pocore_foundation__person__month') }})
)

select p.person_id, '{{ cols | length }} shared columns checked' as detail
from {{ ref('pocore_foundation__person') }} as p
inner join latest as m on m.person_id = p.person_id
where {% if cols %}{% for c in cols %}p.{{ c }} is distinct from m.{{ c }}{% if not loop.last %}
   or {% endif %}{% endfor %}{% else %}false{% endif %}

union all

-- the guard must actually compare something
select 'no shared columns found', 'check failed' where {{ cols | length }} < 20
