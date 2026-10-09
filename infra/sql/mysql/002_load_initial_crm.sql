-- Commerce Analytics Platform | MySQL CRM | DEV | Initial bulk load.
-- Run via infra/scripts/load_crm_initial.ps1; it substitutes __CSV_DIR__.
-- Only the six CRM tables are affected. No tables are truncated/deleted.
-- The target tables must be empty; repeat runs after success are rejected.
-- This file uses server-side LOAD DATA INFILE in one InnoDB transaction.
USE commerce_crm_dev;
SET SESSION time_zone = '+00:00';
SET SESSION sql_mode = CONCAT_WS(',', @@SESSION.sql_mode, 'STRICT_ALL_TABLES');

-- TEMPORARY DDL precedes the transaction, to avoid changes to schema.
CREATE TEMPORARY TABLE _crm_initial_load_assert (
    is_valid TINYINT NOT NULL,
    CONSTRAINT chk_crm_initial_load_assert CHECK (is_valid = 1)
) ENGINE=InnoDB;

START TRANSACTION;

-- Fail before changing anything if this initial load already exists.
INSERT INTO _crm_initial_load_assert (is_valid)
SELECT IF(
    (SELECT COUNT(*) FROM crm_customers) = 0 AND
    (SELECT COUNT(*) FROM loyalty_accounts) = 0 AND
    (SELECT COUNT(*) FROM loyalty_transactions) = 0 AND
    (SELECT COUNT(*) FROM campaigns) = 0 AND
    (SELECT COUNT(*) FROM campaign_memberships) = 0 AND
    (SELECT COUNT(*) FROM support_tickets) = 0, 1, 0
);

-- Parent tables first, then their child tables; FK checks stay enabled.
LOAD DATA INFILE '__CSV_DIR__/crm_customers.csv'
INTO TABLE crm_customers
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(crm_customer_id, external_customer_code, signup_at, customer_segment,
 marketing_opt_in, preferred_channel, updated_at);

LOAD DATA INFILE '__CSV_DIR__/loyalty_accounts.csv'
INTO TABLE loyalty_accounts
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(loyalty_account_id, crm_customer_id, loyalty_tier, points_balance,
 enrolled_at, updated_at);

LOAD DATA INFILE '__CSV_DIR__/loyalty_transactions.csv'
INTO TABLE loyalty_transactions
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(loyalty_transaction_id, loyalty_account_id, transaction_type,
 points_delta, @reference_order_number, occurred_at)
SET reference_order_number = NULLIF(@reference_order_number, '');

LOAD DATA INFILE '__CSV_DIR__/campaigns.csv'
INTO TABLE campaigns
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(campaign_id, campaign_code, campaign_name, channel, campaign_status,
 starts_at, ends_at, updated_at);

LOAD DATA INFILE '__CSV_DIR__/campaign_memberships.csv'
INTO TABLE campaign_memberships
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(campaign_id, crm_customer_id, engagement_status, targeted_at,
 @engaged_at, updated_at)
SET engaged_at = NULLIF(@engaged_at, '');

LOAD DATA INFILE '__CSV_DIR__/support_tickets.csv'
INTO TABLE support_tickets
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(ticket_id, ticket_number, crm_customer_id, issue_category,
 ticket_status, created_at, @resolved_at, updated_at)
SET resolved_at = NULLIF(@resolved_at, '');

-- If any count is wrong, a CHECK constraint raises an error and rolls back.
INSERT INTO _crm_initial_load_assert (is_valid)
SELECT IF(
    (SELECT COUNT(*) FROM crm_customers) = 50000 AND
    (SELECT COUNT(*) FROM loyalty_accounts) = 35000 AND
    (SELECT COUNT(*) FROM loyalty_transactions) = 175000 AND
    (SELECT COUNT(*) FROM campaigns) = 120 AND
    (SELECT COUNT(*) FROM campaign_memberships) = 360000 AND
    (SELECT COUNT(*) FROM support_tickets) = 45000, 1, 0
);

COMMIT;

-- Count display only after a successful commit.
SELECT 'crm_customers' AS table_name, COUNT(*) AS row_count FROM crm_customers
UNION ALL SELECT 'loyalty_accounts', COUNT(*) FROM loyalty_accounts
UNION ALL SELECT 'loyalty_transactions', COUNT(*) FROM loyalty_transactions
UNION ALL SELECT 'campaigns', COUNT(*) FROM campaigns
UNION ALL SELECT 'campaign_memberships', COUNT(*) FROM campaign_memberships
UNION ALL SELECT 'support_tickets', COUNT(*) FROM support_tickets;
