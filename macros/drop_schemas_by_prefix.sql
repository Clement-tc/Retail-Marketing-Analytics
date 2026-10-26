{#
    supprime les schémas de la base cible dont le nom commence par un préfixe.
    sert à nettoyer les schémas jetables de la CI après chaque run :
    dbt run-operation drop_schemas_by_prefix --args "{prefix: dbt_ci_pr_12}"
    garde-fou : refuse tout préfixe qui ne commence pas par dbt_ci_
#}
{% macro drop_schemas_by_prefix(prefix) %}

    {% if not prefix.lower().startswith('dbt_ci_') %}
        {{ exceptions.raise_compiler_error("préfixe refusé : seuls les schémas dbt_ci_* peuvent être supprimés (reçu : " ~ prefix ~ ")") }}
    {% endif %}

    {% set schemas_query %}
        select schema_name
        from {{ target.database }}.information_schema.schemata
        where schema_name ilike '{{ prefix }}%'
    {% endset %}

    {% set schemas = run_query(schemas_query).columns[0].values() %}

    {% for schema in schemas %}
        {% do run_query("drop schema if exists " ~ target.database ~ "." ~ schema ~ " cascade") %}
        {{ log("schéma supprimé : " ~ schema, info=true) }}
    {% endfor %}

    {% if schemas | length == 0 %}
        {{ log("aucun schéma à supprimer pour le préfixe " ~ prefix, info=true) }}
    {% endif %}

{% endmacro %}
