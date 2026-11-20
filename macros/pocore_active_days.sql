{#
  The 12-month line the engine draws everywhere: "active" means a gift in the last
  pocore_active_days() days, a gift after a longer gap is a win-back (is_reactivation_gift),
  "lapsed" is the next 12 months after that. One number, so those definitions can't drift apart.
  An engine constant, not a client var: every client's stages mean the same thing.
#}
{% macro pocore_active_days() %} {{ return(365) }}{% endmacro %}
