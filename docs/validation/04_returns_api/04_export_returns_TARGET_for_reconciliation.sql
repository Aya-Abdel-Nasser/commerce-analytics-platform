/* Optional READ-ONLY export if pyodbc is unavailable.
   Run in SSMS with Results to File / Results Grid -> Save Results As CSV.
   Export as UTF-8 CSV with column header raw_json. Keep JSON content intact.
   Beware: some export methods quote/escape JSON differently; the Python
   comparison CSV reader handles standard RFC4180 CSV, not arbitrary output.
   Best method remains a read-only pyodbc SQL connection.
*/
USE [commerce_warehouse_dev];
GO
SET NOCOUNT ON;
SELECT raw_json
FROM bronze.returns_raw
ORDER BY JSON_VALUE(raw_json, '$.payload.return_id');
GO
