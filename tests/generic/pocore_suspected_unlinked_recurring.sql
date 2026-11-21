{# Heuristic (WARN, not error): one_time gifts that look like recurring payments
   whose schedule link was lost in the CRM. See SPEC §6.2 "Unlinked recurring payments".
   Returns one row per suspect gift, with the pattern that flagged it. #}
{% test pocore_suspected_unlinked_recurring(model) %}
{{ config(severity = 'warn') }}
{#- Logic shared with pocore_admin__health (macros/pocore_sql__suspected_unlinked_recurring.sql). -#}
{{ pocore_sql__suspected_unlinked_recurring(model) }}
{% endtest %}
