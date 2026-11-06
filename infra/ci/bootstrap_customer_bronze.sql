USE [commerce_warehouse_ci];
GO

-- =====================================================
-- Commerce Analytics Platform
-- CI Integration Testing
-- Customer Domain: Bronze Schema
-- =====================================================

CREATE SCHEMA [bronze];
GO

-- =====================================================
-- 1. PostgreSQL OLTP Customers
-- =====================================================

CREATE TABLE [bronze].[oltp_customers] (
    [customer_id] BIGINT NULL,
    [customer_code] NVARCHAR(32) NULL,
    [full_name] NVARCHAR(120) NULL,
    [email] NVARCHAR(255) NULL,
    [city] NVARCHAR(80) NULL,
    [created_at] DATETIME2(6) NULL,
    [updated_at] DATETIME2(6) NULL,
    [_ingested_at_utc] DATETIME2(6) NOT NULL
);
GO

-- =====================================================
-- 2. MySQL CRM Customers
-- =====================================================

CREATE TABLE [bronze].[crm_customers] (
    [crm_customer_id] DECIMAL(20, 0) NOT NULL,
    [external_customer_code] NVARCHAR(64) NOT NULL,
    [signup_at] DATETIME2(6) NOT NULL,
    [customer_segment] NVARCHAR(40) NOT NULL,
    [marketing_opt_in] SMALLINT NOT NULL,
    [preferred_channel] NVARCHAR(40) NOT NULL,
    [updated_at] DATETIME2(6) NOT NULL
);
GO

-- =====================================================
-- 3. MySQL CRM Loyalty Accounts
-- =====================================================

CREATE TABLE [bronze].[crm_loyalty_accounts] (
    [loyalty_account_id] DECIMAL(20, 0) NOT NULL,
    [crm_customer_id] DECIMAL(20, 0) NOT NULL,
    [loyalty_tier] NVARCHAR(40) NOT NULL,
    [points_balance] INT NOT NULL,
    [enrolled_at] DATETIME2(6) NOT NULL,
    [updated_at] DATETIME2(6) NOT NULL
);
GO

-- =====================================================
-- 4. MySQL CRM Loyalty Transactions
-- =====================================================

CREATE TABLE [bronze].[crm_loyalty_transactions] (
    [loyalty_transaction_id] DECIMAL(20, 0) NOT NULL,
    [loyalty_account_id] DECIMAL(20, 0) NOT NULL,
    [transaction_type] NVARCHAR(40) NOT NULL,
    [points_delta] INT NOT NULL,
    [reference_order_number] NVARCHAR(80) NULL,
    [occurred_at] DATETIME2(6) NOT NULL
);
GO