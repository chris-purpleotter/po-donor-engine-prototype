{# Recurring payments must say which schedule they belong to
   (the qualifying-gift rule depends on it). #}
{% test pocore_recurring_has_schedule(model) %}
select *
from {{ model }}
where gift_type = 'recurring'
  and recurring_schedule_id is null
{% endtest %}
