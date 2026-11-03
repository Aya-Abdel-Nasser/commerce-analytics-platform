
{% macro date_to_key(date_expression) -%}

    convert(
        int,
        convert(char(8), {{ date_expression }}, 112)
    )

{%- endmacro %}
