{#
  The columns of pocore_foundation__person: who each person is.

  Built from config, so you never edit this for a client:
    - the contract's person columns (fixed)
    - plus one attr_<name> column per entry in the client's `people_extra_columns` var

  Edit this only when the ENGINE gains a new contract column for every client.
  Used by: pocore_entity__person, the group module (segment rules can use these), the pack cube.
#}
{% macro pocore_columns__person() %}
    {%- set columns = ['created_at', 'person_type', 'is_deceased', 'region', 'acquisition_channel', 'acquisition_theme'] -%}
    {%- for name in var('people_extra_columns') -%}
        {%- do columns.append('attr_' ~ name) -%}
    {%- endfor -%}
    {{ return(columns) }}
{% endmacro %}
