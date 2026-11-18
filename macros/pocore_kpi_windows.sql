{#
  The KPI outcome windows (days after an anchor date). FIXED by the engine, not a client var:
  every window becomes a column name (gave_90d, retained_180d, ...), and certified/foundation
  columns must be identical for every client (DESIGN_v0.2.0 §5 rule 6).

      pocore_kpi_windows()            -> [30, 90, 180, 365]   windows for gave / revenue
      pocore_kpi_windows('retained')  -> [90, 180, 365]       windows for retained

  `retained` ("still paying at the end of the window") looks for a recurring payment in the
  last `recurring_active_days` (default 45) of the window, so it is only defined for windows
  longer than that. Its list is fixed too (not derived from the var), so changing
  recurring_active_days can never add or remove columns; the build fails instead if the var
  is too large for the shortest retained window.
#}

{% macro pocore_kpi_windows(kpi=none) %}
    {%- if var('kpi_windows_days', none) is not none -%}
        {{ exceptions.raise_compiler_error("po_core: var 'kpi_windows_days' is no longer configurable (v0.2.0): KPI windows are fixed at [30, 90, 180, 365] so every client gets the same columns. Remove it from your dbt_project.yml.") }}
    {%- endif -%}
    {%- set all_windows = [30, 90, 180, 365] -%}
    {%- set retained_windows = [90, 180, 365] -%}
    {%- if kpi == 'retained' -%}
        {%- if var('recurring_active_days') | int >= retained_windows | min -%}
            {{ exceptions.raise_compiler_error("po_core: recurring_active_days (" ~ var('recurring_active_days') ~ ") must be less than the shortest retained window (" ~ retained_windows | min ~ " days)") }}
        {%- endif -%}
        {{ return(retained_windows) }}
    {%- elif kpi in (none, 'gave', 'started_monthly', 'revenue', 'revenue_per_donor') -%}
        {{ return(all_windows) }}
    {%- else -%}
        {{ exceptions.raise_compiler_error("po_core: pocore_kpi_windows called with unknown kpi '" ~ kpi ~ "'") }}
    {%- endif -%}
{% endmacro %}
