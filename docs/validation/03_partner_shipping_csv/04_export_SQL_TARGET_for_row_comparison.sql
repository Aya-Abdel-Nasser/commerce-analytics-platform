/*
Optional export query: after selecting "Results to File" or saving results as CSV,
include the exact header row in the saved CSV. Use UTF-8 encoding.
This is a SELECT ONLY and does not export automatically.
For SQL NULL vs CSV empty-string distinctions, prefer direct pyodbc mode in 03.
*/
USE [commerce_warehouse_dev];
GO
SELECT
    shipment_id, order_number, carrier_code, tracking_number,
    shipment_status, shipped_at, delivered_at,
    shipping_fee_egp, source_updated_at
FROM bronze.partner_shipments
ORDER BY shipment_id;
GO
