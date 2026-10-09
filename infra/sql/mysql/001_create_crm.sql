-- Commerce Analytics Platform — MySQL CRM source schema
-- Environment: DEV | Database: commerce_crm_dev
-- Run with a MySQL account with CREATE privileges (not inf_mysql_reader).
-- All DATETIME values are generated and interpreted as UTC.
-- This is an initial schema, not a migration script.

USE commerce_crm_dev;

-- CRM owns its identifiers; external_customer_code links to the OLTP business key.
CREATE TABLE IF NOT EXISTS crm_customers (
    crm_customer_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    external_customer_code VARCHAR(32) NOT NULL,
    signup_at DATETIME(6) NOT NULL,
    customer_segment VARCHAR(20) NOT NULL,
    marketing_opt_in BOOLEAN NOT NULL DEFAULT FALSE,
    preferred_channel VARCHAR(20) NOT NULL DEFAULT 'NONE',
    updated_at DATETIME(6) NOT NULL,
    PRIMARY KEY (crm_customer_id),
    UNIQUE KEY uq_crm_customer_external_code (external_customer_code),
    CONSTRAINT chk_crm_customer_segment CHECK (customer_segment IN ('NEW', 'ACTIVE', 'AT_RISK', 'VIP')),
    CONSTRAINT chk_crm_preferred_channel CHECK (preferred_channel IN ('EMAIL', 'SMS', 'PUSH', 'NONE'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS loyalty_accounts (
    loyalty_account_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    crm_customer_id BIGINT UNSIGNED NOT NULL,
    loyalty_tier VARCHAR(20) NOT NULL,
    points_balance INT NOT NULL DEFAULT 0,
    enrolled_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    PRIMARY KEY (loyalty_account_id),
    UNIQUE KEY uq_loyalty_account_customer (crm_customer_id),
    CONSTRAINT fk_loyalty_account_customer FOREIGN KEY (crm_customer_id)
        REFERENCES crm_customers (crm_customer_id),
    CONSTRAINT chk_loyalty_tier CHECK (loyalty_tier IN ('BRONZE', 'SILVER', 'GOLD', 'PLATINUM')),
    CONSTRAINT chk_loyalty_balance CHECK (points_balance >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS loyalty_transactions (
    loyalty_transaction_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    loyalty_account_id BIGINT UNSIGNED NOT NULL,
    transaction_type VARCHAR(20) NOT NULL,
    points_delta INT NOT NULL,
    reference_order_number VARCHAR(40) NULL,
    occurred_at DATETIME(6) NOT NULL,
    PRIMARY KEY (loyalty_transaction_id),
    KEY ix_loyalty_transactions_account_time (loyalty_account_id, occurred_at),
    KEY ix_loyalty_transactions_order (reference_order_number),
    CONSTRAINT fk_loyalty_transaction_account FOREIGN KEY (loyalty_account_id)
        REFERENCES loyalty_accounts (loyalty_account_id),
    CONSTRAINT chk_loyalty_transaction_type CHECK (transaction_type IN ('EARN', 'REDEEM', 'ADJUST')),
    CONSTRAINT chk_loyalty_transaction_points CHECK (
        (transaction_type = 'EARN' AND points_delta > 0) OR
        (transaction_type = 'REDEEM' AND points_delta < 0) OR
        (transaction_type = 'ADJUST' AND points_delta <> 0)
    )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS campaigns (
    campaign_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    campaign_code VARCHAR(40) NOT NULL,
    campaign_name VARCHAR(150) NOT NULL,
    channel VARCHAR(20) NOT NULL,
    campaign_status VARCHAR(20) NOT NULL,
    starts_at DATETIME(6) NOT NULL,
    ends_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    PRIMARY KEY (campaign_id),
    UNIQUE KEY uq_campaign_code (campaign_code),
    CONSTRAINT chk_campaign_channel CHECK (channel IN ('EMAIL', 'SMS', 'PUSH')),
    CONSTRAINT chk_campaign_status CHECK (campaign_status IN ('DRAFT', 'ACTIVE', 'COMPLETED')),
    CONSTRAINT chk_campaign_date_range CHECK (ends_at > starts_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS campaign_memberships (
    campaign_id BIGINT UNSIGNED NOT NULL,
    crm_customer_id BIGINT UNSIGNED NOT NULL,
    engagement_status VARCHAR(20) NOT NULL,
    targeted_at DATETIME(6) NOT NULL,
    engaged_at DATETIME(6) NULL,
    updated_at DATETIME(6) NOT NULL,
    PRIMARY KEY (campaign_id, crm_customer_id),
    KEY ix_memberships_customer (crm_customer_id),
    CONSTRAINT fk_membership_campaign FOREIGN KEY (campaign_id)
        REFERENCES campaigns (campaign_id),
    CONSTRAINT fk_membership_customer FOREIGN KEY (crm_customer_id)
        REFERENCES crm_customers (crm_customer_id),
    CONSTRAINT chk_membership_status CHECK (
        engagement_status IN ('TARGETED', 'SENT', 'OPENED', 'CONVERTED', 'UNSUBSCRIBED')
    )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS support_tickets (
    ticket_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    ticket_number VARCHAR(40) NOT NULL,
    crm_customer_id BIGINT UNSIGNED NOT NULL,
    issue_category VARCHAR(30) NOT NULL,
    ticket_status VARCHAR(20) NOT NULL,
    created_at DATETIME(6) NOT NULL,
    resolved_at DATETIME(6) NULL,
    updated_at DATETIME(6) NOT NULL,
    PRIMARY KEY (ticket_id),
    UNIQUE KEY uq_support_ticket_number (ticket_number),
    KEY ix_tickets_customer_time (crm_customer_id, created_at),
    CONSTRAINT fk_ticket_customer FOREIGN KEY (crm_customer_id)
        REFERENCES crm_customers (crm_customer_id),
    CONSTRAINT chk_ticket_category CHECK (
        issue_category IN ('DELIVERY', 'PAYMENT', 'RETURN', 'PRODUCT', 'OTHER')
    ),
    CONSTRAINT chk_ticket_status CHECK (
        ticket_status IN ('OPEN', 'IN_PROGRESS', 'RESOLVED', 'CLOSED')
    ),
    CONSTRAINT chk_ticket_resolution_date CHECK (
        resolved_at IS NULL OR resolved_at >= created_at
    )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
