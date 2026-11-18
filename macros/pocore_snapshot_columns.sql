{#
  The person snapshot's columns, in ONE place, so the foundation tables built from it can't
  drift apart (pocore_foundation__person__month and pocore_foundation__person both use these).
  Add a new snapshot feature here once and it appears in both.

    pocore_snapshot_columns('attributes')  who the person is (contract + client attr_* columns)
    pocore_snapshot_columns('state')       what was true about them as of a month-end:
                                           derived values first, then their ingredients
#}

{% macro pocore_snapshot_columns(kind) %}
    {%- if kind == 'attributes' -%}
        {%- set cols = ['created_at', 'person_type', 'is_deceased', 'region', 'acquisition_channel', 'acquisition_theme'] -%}
        {%- for c in var('people_extra_columns') -%}{%- do cols.append('attr_' ~ c) -%}{%- endfor -%}
        {{ return(cols) }}
    {%- elif kind == 'state' -%}
        {{ return([
            'lifecycle_stage', 'is_new_donor', 'is_reactivated', 'is_recurring_active', 'gave_prior_year_not_ytd',
            'first_gift_date', 'first_gift_amount', 'first_gift_band', 'first_gift_year',
            'last_gift_date', 'last_gift_year',
            'days_since_first_gift', 'days_since_last_gift', 'days_since_last_recurring',
            'days_since_reactivation', 'reactivations_lifetime',
            'gift_count_12m', 'net_giving_12m', 'gift_count_lifetime', 'net_giving_lifetime',
            'net_giving_ytd', 'net_giving_prior_year'
        ]) }}
    {%- else -%}
        {{ exceptions.raise_compiler_error("po_core: pocore_snapshot_columns(kind) needs 'attributes' or 'state', got '" ~ kind ~ "'") }}
    {%- endif -%}
{% endmacro %}
