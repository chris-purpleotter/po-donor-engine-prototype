{#
  The engine's group measures (a segment's `primary_kpi`): the ONE list. Adding a measure means
  adding it here, computing its {id}_{N}d outcome columns in pocore_ftr__person__month_lookahead, and
  carrying them through pocore_foundation__person__month; everything else reads this list.

    id       the kpi_id used in config (primary_kpi) and in column names ({id}_rate_90d ...)
    name     how it reads in text: "1,234 people gave"
    phrase   how it reads with a window ({days} is replaced): "gave within 90 days"
    adds_up  true when a longer window always includes a shorter one (anyone who gave within
             30 days also gave within 90). False for retained ("still paying at the end of the
             window"): someone retained at 90 days can be gone by 180. Reports may only say
             "each bar includes the ones above it" when this is true.

  Windows per measure come from pocore_kpi_windows(id). Revenue (revenue_per_donor) is not a
  group measure: it is reported alongside every measure.
#}

{% macro pocore_measures() %}
    {{ return([
        {'id': 'gave',            'name': 'gave',                   'phrase': 'gave within {days} days',                'adds_up': true},
        {'id': 'started_monthly', 'name': 'started monthly giving', 'phrase': 'started monthly giving within {days} days', 'adds_up': true},
        {'id': 'retained',        'name': 'still giving monthly',   'phrase': 'still giving monthly after {days} days',   'adds_up': false}
    ]) }}
{% endmacro %}
