
{% macro clean_optional_text(column_expression) %}

    nullif(
        ltrim(rtrim({{ column_expression }})),
        ''
    )

{% endmacro %}
