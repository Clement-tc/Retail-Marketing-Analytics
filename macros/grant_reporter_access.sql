{#
    donne au rôle reporter (power bi) l'accès au schéma marts de la prod.
    appelé en fin d'exécution (on-run-end) ; les droits select sur chaque table sont
    gérés par la config grants des marts. sans effet hors prod : ni la dev ni la ci
    n'ont à être lues par le reporting
#}
{% macro grant_reporter_access() %}

    {% if execute and target.name == 'prod' %}
        {% do run_query("grant usage on schema " ~ target.database ~ ".marts to role reporter") %}
        {{ log("usage sur " ~ target.database ~ ".marts accordé au rôle reporter", info=true) }}
    {% endif %}

{% endmacro %}
