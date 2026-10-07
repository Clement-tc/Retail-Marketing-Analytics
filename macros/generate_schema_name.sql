{#
    dev  : analytics.dbt_<suffixe>_staging, dbt_<suffixe>_marts... (isolation par développeur)
    prod : analytics.staging, analytics.marts... (noms propres pour power bi)
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if target.name == 'prod' and custom_schema_name is not none -%}
        {{ custom_schema_name | trim }}
    {%- elif custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ target.schema }}_{{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
