{#
  Return the CLIENT model that provides one of the engine's inputs ('donors', 'gifts', ...).

      {{ pode_input_model('gifts') }}
        -> var('gifts_model')               e.g. 'conform_gifts' (engine default: 'gifts')
        -> ref(project_name, 'conform_gifts')

  project_name = the ROOT project being run, i.e. always the client project.
  Naming the project explicitly (two-argument ref) makes the dependency on the
  client's model intentional and stops dbt's "package node depends on root
  project node" warning.

  Future (non-breaking, MINOR): an optional `<input>_package` var defaulting to
  project_name, if conform ever ships as a shared package (e.g. NPSP).
#}

{% macro pode_input_model(input) %}
    {{ return(ref(project_name, var(input ~ '_model'))) }}
{% endmacro %}
