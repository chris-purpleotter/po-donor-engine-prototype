{# The given columns together identify each row exactly once (portable; no dbt-utils). #}
{% test pocore_unique_combination(model, columns) %}
select {{ columns | join(', ') }}, count(*) as row_count
from {{ model }}
group by {{ columns | join(', ') }}
having count(*) > 1
{% endtest %}
