{#
  Lifecycle stages: ids and readable labels, in the order people think about them.
  The stage LOGIC stays written out in pocore_ftr__person__month_lookback (first match wins); this list
  only names the stages. Used for the Supporter Insights "Lifecycle stage" dropdown (as bands,
  see pocore_pack_settings). integration_tests/tests/assert_labels_and_measures fails if the
  snapshot produces a stage that isn't listed here.
#}
{% macro pocore_lifecycle_stages() %}
    {{ return([
        {'id': 'sustainer',   'label': 'Sustainers (active monthly)'},
        {'id': 'new',         'label': 'New (first gift in last 90 days)'},
        {'id': 'active',      'label': 'Active (gave in last 12 months)'},
        {'id': 'lapsed',      'label': 'Lapsed (13-24 months)'},
        {'id': 'deep_lapsed', 'label': 'Deep lapsed (24+ months)'},
        {'id': 'prospect',    'label': 'Prospects (no gifts yet)'}
    ]) }}
{% endmacro %}
