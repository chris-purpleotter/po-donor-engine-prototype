{#
  Custom generic tests for the gifts contract (SPEC §6.2).
  A generic test is a query that returns the rows that BREAK the rule;
  zero rows = pass.
#}

{# D4: refunds are negative, every other gift is positive. #}
{% test pode_refund_sign(model) %}
select *
from {{ model }}
where (is_refund and amount >= 0)
   or (not is_refund and amount <= 0)
{% endtest %}


{# Recurring payments must say which schedule they belong to
   (the qualifying-gift rule depends on it). #}
{% test pode_recurring_has_schedule(model) %}
select *
from {{ model }}
where gift_type = 'recurring'
  and recurring_schedule_id is null
{% endtest %}


{# exclusion_reason is null exactly when the gift is KPI-eligible. #}
{% test pode_exclusion_reason_consistent(model) %}
select *
from {{ model }}
where (is_kpi_eligible and exclusion_reason is not null)
   or (not is_kpi_eligible and exclusion_reason is null)
{% endtest %}


{# Heuristic (WARN, not error): one_time gifts that look like recurring payments
   whose schedule link was lost in the CRM. See SPEC §6.2 "Unlinked recurring payments".
   Returns one row per suspect gift, with the pattern that flagged it. #}
{% test pode_suspected_unlinked_recurring(model) %}
{{ config(severity = 'warn') }}
{#- Logic shared with pode_srv__project_health (macros/pode_suspected_unlinked_recurring_sql.sql). -#}
{{ pode_suspected_unlinked_recurring_sql(model) }}
{% endtest %}
