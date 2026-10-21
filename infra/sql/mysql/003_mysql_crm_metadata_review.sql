SELECT
    table_name,
    constraint_name,
    constraint_type
FROM information_schema.table_constraints
WHERE table_schema = 'commerce_crm_dev'
ORDER BY
    table_name,
    constraint_type,
    constraint_name;
###########--------------------------------------------------------------------------------------------------
#####-----------------------------------------------------------------------------------------------################
#########################################################
SELECT
    TABLE_NAME,
    CONSTRAINT_NAME,
    COLUMN_NAME,
    REFERENCED_TABLE_NAME,
    REFERENCED_COLUMN_NAME
FROM information_schema.KEY_COLUMN_USAGE
WHERE TABLE_SCHEMA = 'commerce_crm_dev'
  AND REFERENCED_TABLE_NAME IS NOT NULL
ORDER BY
    TABLE_NAME,
    CONSTRAINT_NAME,
    ORDINAL_POSITION;
######################################################################################
SELECT
    TABLE_NAME,
    ORDINAL_POSITION,
    COLUMN_NAME,
    DATA_TYPE,
    COLUMN_TYPE,
    CHARACTER_MAXIMUM_LENGTH,
    NUMERIC_PRECISION,
    NUMERIC_SCALE,
    DATETIME_PRECISION,
    IS_NULLABLE,
    COLUMN_DEFAULT,
    COLUMN_KEY,
    EXTRA
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = 'commerce_crm_dev'
  AND TABLE_NAME IN (
      'crm_customers',
      'loyalty_accounts',
      'loyalty_transactions',
      'campaigns',
      'campaign_memberships',
      'support_tickets'
  )
ORDER BY
    TABLE_NAME,
    ORDINAL_POSITION;