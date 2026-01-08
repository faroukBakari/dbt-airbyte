{% macro generate_schema_name(custom_schema_name, node) -%}
    {#
        Use the custom schema name directly without concatenating with default schema.
        This gives us clean schema names: staging, marts, gold
    #}
    {%- if custom_schema_name is none -%}
        {{ default_schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
