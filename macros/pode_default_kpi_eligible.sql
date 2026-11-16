{#
  Default KPI eligibility by gift_category (SPEC D1 / §6.2).

  Called from the CLIENT's conform model, then extended with client exceptions:

      {{ po_donor_engine.pode_default_kpi_eligible('gift_category') }}
          and campaign_code != 'CAPITAL-2026'          as is_kpi_eligible

  Compiles to plain SQL (a boolean expression). Changing this list changes
  output numbers for every client -> MAJOR release (D12).
#}

{% macro pode_default_kpi_eligible(category_column) %}
    ({{ category_column }} in ('cash', 'pledge_payment', 'daf'))
{% endmacro %}
