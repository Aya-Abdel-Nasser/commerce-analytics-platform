
-- Reconcile integrated customers against upstream models.
-- Any returned row represents a data quality failure.

with expected_customers as (

    select
        o.customer_id,
        o.customer_code,
        o.full_name,
        o.email,
        o.city,
        o.created_at as customer_created_at,
        o.updated_at as oltp_updated_at,
        o.ingested_at_utc,

        c.crm_customer_id,
        c.external_customer_code,
        c.signup_at as crm_signup_at,
        c.customer_segment,
        c.marketing_opt_in,
        c.preferred_channel,
        c.updated_at as crm_updated_at,

        l.loyalty_account_id,
        l.loyalty_tier,
        l.points_balance,

        case
            when l.loyalty_account_id is not null
            then 1 else 0
        end as has_loyalty_account,

        l.loyalty_transaction_count,
        l.earn_transaction_count,
        l.redeem_transaction_count,
        l.adjust_transaction_count,

        l.earned_points,
        l.redeemed_points,
        l.net_adjustment_points,
        l.net_points_delta

    from {{ ref('stg_oltp_customers') }} as o

    left join {{ ref('stg_crm_customers') }} as c
        on o.customer_code = c.external_customer_code

    left join {{ ref('int_loyalty_accounts_integrated') }} as l
        on c.crm_customer_id = l.crm_customer_id

),

reconciliation as (

    select
        e.customer_id as expected_customer_id,
        a.customer_id as actual_customer_id,

        case
            when e.customer_id is not null
             and a.customer_id is not null
             and exists (

                select
                    e.customer_code,
                    e.full_name,
                    e.email,
                    e.city,
                    e.customer_created_at,
                    e.oltp_updated_at,
                    e.ingested_at_utc,

                    e.crm_customer_id,
                    e.external_customer_code,
                    e.crm_signup_at,
                    e.customer_segment,
                    e.marketing_opt_in,
                    e.preferred_channel,
                    e.crm_updated_at,

                    e.loyalty_account_id,
                    e.loyalty_tier,
                    e.points_balance,
                    e.has_loyalty_account,

                    e.loyalty_transaction_count,
                    e.earn_transaction_count,
                    e.redeem_transaction_count,
                    e.adjust_transaction_count,

                    e.earned_points,
                    e.redeemed_points,
                    e.net_adjustment_points,
                    e.net_points_delta

                except

                select
                    a.customer_code,
                    a.full_name,
                    a.email,
                    a.city,
                    a.customer_created_at,
                    a.oltp_updated_at,
                    a.ingested_at_utc,

                    a.crm_customer_id,
                    a.external_customer_code,
                    a.crm_signup_at,
                    a.customer_segment,
                    a.marketing_opt_in,
                    a.preferred_channel,
                    a.crm_updated_at,

                    a.loyalty_account_id,
                    a.loyalty_tier,
                    a.points_balance,
                    a.has_loyalty_account,

                    a.loyalty_transaction_count,
                    a.earn_transaction_count,
                    a.redeem_transaction_count,
                    a.adjust_transaction_count,

                    a.earned_points,
                    a.redeemed_points,
                    a.net_adjustment_points,
                    a.net_points_delta
             )
            then 1
            else 0
        end as has_mismatch

    from expected_customers as e

    full outer join {{ ref('int_customers_integrated') }} as a
        on e.customer_id = a.customer_id

)

select
    expected_customer_id,
    actual_customer_id,
    has_mismatch

from reconciliation

where
    expected_customer_id is null
    or actual_customer_id is null
    or has_mismatch = 1
