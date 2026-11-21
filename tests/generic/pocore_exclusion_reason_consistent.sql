{# exclusion_reason is null exactly when the gift is KPI-eligible. #}
{% test pocore_exclusion_reason_consistent(model) %}
select *
from {{ model }}
where (is_kpi_eligible and exclusion_reason is not null)
   or (not is_kpi_eligible and exclusion_reason is null)
{% endtest %}
