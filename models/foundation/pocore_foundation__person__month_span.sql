{#
  pocore_foundation__person__month_span — ONE ROW PER PERSON x CALENDAR MONTH with KPI-eligible
  activity. A SPAN: counts and sums of gifts inside the month, so every column adds up freely,
  across people and months. Join pocore_foundation__person on person_id for who they are.
#}

select * from {{ ref('pocore_rollup__person__month_span') }}
