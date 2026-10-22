Welcome to your new dbt project!

### Using the starter project

Try running the following commands:
- dbt run
- dbt test


### Resources:
- Learn more about dbt [in the docs](https://docs.getdbt.com/docs/introduction)
- Check out [Discourse](https://discourse.getdbt.com/) for commonly asked questions and answers
- Join the [chat](https://community.getdbt.com/) on Slack for live discussions and support
- Find [dbt events](https://events.getdbt.com) near you
- Check out [the blog](https://blog.getdbt.com/) for the latest news on dbt's development and best practices

## SQL Server Data Quality Testing

The project uses dbt Core 1.12.6 with dbt-sqlserver 1.12.1.

### Testing conventions

- Use built-in generic tests for `not_null` and `unique`.
- Use `dbt_utils` tests where compatibility has been verified.
- Use singular SQL tests for business rules when package-generated
  SQL is incompatible with SQL Server.
- Singular tests must return zero rows to pass.
- Calculate expected transformation results independently from
  the transformation macro being tested.

### Known compatibility issue

`dbt_utils.expression_is_true` generated `SELECT 1` without a
column alias inside a temporary SQL Server view, resulting in
SQL Server error 4511.

For the products model, the affected tests were replaced with:

- `assert_stg_oltp_products_positive_price`
- `assert_stg_oltp_products_non_blank_sku`

Both tests passed against the Development warehouse.
