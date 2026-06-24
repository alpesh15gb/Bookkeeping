-- PRODUCTION DATA REPAIR — GST Configuration
-- Generated: 2026-06-25 by scan_gst_config.py
-- Review each statement before executing
-- Run in a transaction: BEGIN; ... COMMIT;

-- ============================================================
-- CATEGORY A: GSTIN present but tax_mode = NON_GST
-- These tenants registered with a GSTIN but the old registration
-- flow did not auto-detect tax_mode. Fix: set GST_REGULAR.
-- ============================================================

UPDATE tenants SET tax_mode = 'GST_REGULAR'
WHERE id = '87dd9b89-63f2-4766-86e2-ef5b07095869';  -- Test Company Pvt Ltd

UPDATE tenants SET tax_mode = 'GST_REGULAR'
WHERE id = '6dfced8a-c8a2-405a-9011-9a87a8407bed';  -- Test Company 3

UPDATE tenants SET tax_mode = 'GST_REGULAR'
WHERE id = '8962b60f-b872-49a8-ab6d-96cfb0a188ac';  -- Deploy Test Company

-- ============================================================
-- CATEGORY B: GST_REGULAR but origin_state_code = NULL
-- Only 1 can be auto-fixed from GSTIN prefix.
-- The other 5 have no GSTIN — require manual state_code entry.
-- ============================================================

-- Auto-fixable: SBH IT SOLUTIONS (GSTIN prefix = 36 = Telangana)
UPDATE tenant_settings SET origin_state_code = '36'
WHERE tenant_id = '0a506d6a-445f-4466-b3a6-459b65ed2bc6';

-- ============================================================
-- CATEGORY B — MANUAL INTERVENTION REQUIRED
-- These 5 tenants are GST_REGULAR but have no GSTIN.
-- Either provide a GSTIN or switch back to NON_GST.
-- ============================================================

-- Option 1: If these are test tenants, disable GST
-- UPDATE tenants SET tax_mode = 'NON_GST' WHERE id = '...';
-- UPDATE tenant_settings SET gst_enabled = false WHERE tenant_id = '...';

-- Option 2: If these are real tenants, add GSTIN + origin_state_code
-- UPDATE tenants SET gstin = 'XXAAAAA1111A1Z1' WHERE id = '...';
-- UPDATE tenant_settings SET origin_state_code = 'XX' WHERE tenant_id = '...';

-- Tenant IDs requiring manual fix:
--   c4b63b73... (GST Test Co)
--   d79aa857... (GST Flow Co)
--   d1625a0b... (GST Test Co)
--   b6dea9f5... (GST Test Co)
--   ec092a56... (GST Service Co)

-- ============================================================
-- INV/2026/0009 — Existing invoice with zero GST
-- This invoice was created under NON_GST mode.
-- GST amounts are baked into the database.
-- Options:
--   1. Cancel and recreate after tenant fix
--   2. Manual journal entry correction
-- ============================================================
