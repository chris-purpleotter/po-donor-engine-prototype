{#
  pocore_foundation__person__year_span — ONE ROW PER PERSON x FISCAL YEAR with KPI-eligible
  activity. A SPAN: counts and sums of gifts inside the fiscal year, so every column adds up
  freely, across people and years. Join pocore_foundation__person on person_id for who they are.
#}

select * from {{ ref('pocore_rollup__person__year_span') }}
