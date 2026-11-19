{#
  The 12-month line the engine draws everywhere: "active" means a gift in the last
  pocore_active_days() days, a gift after a longer gap is a win-back (is_reactivation_gift),
  "lapsed" is the next 12 months after that. One number, so those definitions can't drift apart.
  An engine constant, not a client var: every client's stages mean the same thing.
#}
{% macro pocore_active_days() %}{{ return(365) }}{% endmacro %}


{#
  Lifecycle stages: ids and readable labels, in the order people think about them.
  The stage LOGIC stays written out in pocore_ftr__person_snapshot (first match wins); this list
  only names the stages. Used for the Supporter Insights "Lifecycle stage" dropdown (as bands,
  see pocore_pack_settings). integration_tests/assert_lifecycle_stage_labels fails if the
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
