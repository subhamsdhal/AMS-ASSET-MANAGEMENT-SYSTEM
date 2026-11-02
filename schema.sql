CREATE TABLE `asset_allocation` (
  `allocation_id` int NOT NULL AUTO_INCREMENT,
  `asset_id` int NOT NULL,
  `employee_id` int NOT NULL,
  `allocation_date` date NOT NULL,
  `expected_return_date` date DEFAULT NULL,
  `return_date` date DEFAULT NULL,
  `allocation_status` enum('ALLOCATED','RETURNED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'ALLOCATED',
  `issue_condition` enum('GOOD','DAMAGED','NEEDS_REPAIR') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'GOOD',
  `issue_location_id` int DEFAULT NULL,
  `issued_by` int DEFAULT NULL,
  `received_by` int DEFAULT NULL,
  `remarks` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `employee_transfer_preference` enum('RETAIN','RETURN') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `employee_transfer_note` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `employee_transfer_requested_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`allocation_id`),
  KEY `idx_allocation_asset_id` (`asset_id`),
  KEY `idx_allocation_employee_id` (`employee_id`),
  KEY `idx_allocation_status` (`allocation_status`),
  KEY `idx_allocation_issue_location_id` (`issue_location_id`),
  KEY `idx_allocation_issued_by` (`issued_by`),
  KEY `idx_allocation_received_by` (`received_by`)
) ENGINE=InnoDB AUTO_INCREMENT=48 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
-- employee_transfer_preference/_note/_requested_at added by
-- migrations/003_employee_transfer_asset_preferences.sql - see that file for
-- the idempotent ALTER TABLE (run it against any live DB using this schema).


CREATE TABLE `asset_categories` (
  `category_id` int NOT NULL AUTO_INCREMENT,
  `category_name` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `useful_life_years` int DEFAULT NULL,
  `default_depreciation_rate` decimal(5,2) DEFAULT '0.00',
  `status` enum('ACTIVE','INACTIVE') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'ACTIVE',
  `is_active` enum('YES','NO') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'YES',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`category_id`),
  UNIQUE KEY `uk_asset_categories_name` (`category_name`)
) ENGINE=InnoDB AUTO_INCREMENT=17 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `asset_disposal` (
  `disposal_id` int NOT NULL AUTO_INCREMENT,
  `asset_id` int NOT NULL,
  `disposal_date` date NOT NULL,
  `disposal_reason` enum('END_OF_LIFE','BEYOND_ECONOMIC_REPAIR','OBSOLETE','DAMAGED','LOST','OTHER') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'END_OF_LIFE',
  `disposal_value` decimal(12,2) DEFAULT '0.00',
  -- Maker-checker split (previously a single-actor action: disposeAsset()
  -- used to insert this row as 'COMPLETED' and flip assets.asset_status to
  -- DISPOSED in the same step). requested_by/requested_date record who
  -- proposed the disposal and when; approved_by/approved_date now
  -- exclusively record the second-party reviewer's decision (COMPLETED or
  -- REJECTED), never the requester. Same "X_by/X_date" attribution pairing
  -- already used throughout this schema (dept_head_by/dept_head_date on
  -- asset_requests, issued_by/received_by on asset_allocation).
  `requested_by` int DEFAULT NULL,
  `requested_date` date DEFAULT NULL,
  `approved_by` int DEFAULT NULL,
  `approved_date` date DEFAULT NULL,
  `disposal_status` enum('PENDING','APPROVED','COMPLETED','REJECTED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'PENDING',
  `remarks` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  -- The write-off entry: the asset's own DepreciationUtil-computed book value
  -- as of disposal_date, populated by AssetDAO.reviewDisposal() at the
  -- moment a disposal is approved (never user-entered). Deliberately a
  -- separate column from disposal_value above, which is whatever
  -- salvage/resale figure the maker manually typed in - this is the
  -- system's own independent accounting figure, giving a genuine
  -- reconciliation point between "what we recorded as recovered" and "what
  -- the books said this asset was actually worth" at write-off time.
  `calculated_book_value` decimal(12,2) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`disposal_id`),
  UNIQUE KEY `uk_disposal_asset_id` (`asset_id`),
  KEY `idx_disposal_approved_by` (`approved_by`),
  KEY `idx_disposal_requested_by` (`requested_by`),
  KEY `idx_disposal_status` (`disposal_status`),
  KEY `idx_disposal_date` (`disposal_date`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `asset_document_text_index` (
  `id` int NOT NULL AUTO_INCREMENT,
  `document_id` int NOT NULL,
  `asset_id` int NOT NULL,
  `file_name` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `extracted_text` longtext COLLATE utf8mb4_unicode_ci,
  `extraction_status` varchar(50) COLLATE utf8mb4_unicode_ci DEFAULT 'PENDING',
  `extracted_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `created_by` int DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `document_id` (`document_id`),
  KEY `asset_id` (`asset_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `asset_documents` (
  `document_id` int NOT NULL AUTO_INCREMENT,
  `asset_id` int NOT NULL,
  `document_type` enum('ASSET_PHOTO','INVOICE','WARRANTY','MANUAL','OTHER') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'OTHER',
  `original_file_name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `stored_file_path` varchar(500) COLLATE utf8mb4_unicode_ci NOT NULL,
  `mime_type` varchar(120) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `file_size` bigint DEFAULT NULL,
  `uploaded_by` int DEFAULT NULL,
  `uploaded_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`document_id`),
  KEY `idx_asset_documents_asset` (`asset_id`),
  KEY `fk_asset_documents_uploaded_by` (`uploaded_by`)
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `asset_physical_verification` (
  `verification_id` int NOT NULL AUTO_INCREMENT,
  `verification_round_id` int DEFAULT NULL,
  `duty_id` int DEFAULT NULL,
  `asset_id` int NOT NULL,
  `verified_status` enum('VERIFIED','LOCATION_MISMATCH','EMPLOYEE_MISMATCH','NOT_FOUND','DAMAGED','UNDER_REPAIR','NEEDS_REVIEW') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'VERIFIED',
  `verified_by_user_id` int DEFAULT NULL,
  `actual_location_id` int DEFAULT NULL,
  `actual_employee_id` int DEFAULT NULL,
  `verification_officer_employee_id` int DEFAULT NULL,
  `verification_officer_department_id` int DEFAULT NULL,
  `remarks` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  `review_status` enum('SUBMITTED','REVIEWED','APPROVED','REJECTED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'SUBMITTED',
  `reviewed_by_user_id` int DEFAULT NULL,
  `reviewed_on` datetime DEFAULT NULL,
  `verified_on` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`verification_id`),
  KEY `idx_pv_asset_id` (`asset_id`),
  KEY `idx_pv_round_id` (`verification_round_id`),
  KEY `idx_pv_duty_id` (`duty_id`),
  KEY `idx_pv_status` (`verified_status`),
  KEY `idx_pv_verified_on` (`verified_on`)
) ENGINE=InnoDB AUTO_INCREMENT=91 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `asset_qr_scan_logs` (
  `scan_id` bigint NOT NULL AUTO_INCREMENT,
  `asset_id` int DEFAULT NULL,
  `qr_public_token` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `scanned_by_user_id` int DEFAULT NULL,
  `scanned_by_employee_id` int DEFAULT NULL,
  `scan_source` enum('PUBLIC_SCAN','SECURED_SCAN','MOBILE_CAMERA','WEB_CAMERA') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'PUBLIC_SCAN',
  `scan_ip` varchar(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `scan_user_agent` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `scan_status` enum('SUCCESS','FAILED','INVALID_TOKEN') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'SUCCESS',
  `remarks` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `scanned_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`scan_id`),
  KEY `idx_qr_scan_asset_id` (`asset_id`),
  KEY `idx_qr_scan_token` (`qr_public_token`),
  KEY `idx_qr_scan_user_id` (`scanned_by_user_id`),
  KEY `idx_qr_scan_employee_id` (`scanned_by_employee_id`),
  KEY `idx_qr_scan_status` (`scan_status`),
  KEY `idx_qr_scan_time` (`scanned_at`)
) ENGINE=InnoDB AUTO_INCREMENT=60 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `asset_qr_tagging_status` (
  `tagging_id` int NOT NULL AUTO_INCREMENT,
  `asset_id` int NOT NULL,
  `qr_public_token` varchar(120) DEFAULT NULL,
  `print_status` varchar(40) DEFAULT 'PENDING',
  `tag_status` varchar(40) DEFAULT 'PENDING',
  `printed_by_user_id` int DEFAULT NULL,
  `tagged_by_user_id` int DEFAULT NULL,
  `printed_at` timestamp NULL DEFAULT NULL,
  `tagged_at` timestamp NULL DEFAULT NULL,
  `remarks` varchar(500) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`tagging_id`),
  UNIQUE KEY `asset_id` (`asset_id`),
  KEY `idx_qr_tagging_asset` (`asset_id`),
  KEY `idx_qr_tagging_print_status` (`print_status`),
  KEY `idx_qr_tagging_tag_status` (`tag_status`)
) ENGINE=InnoDB AUTO_INCREMENT=91 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


CREATE TABLE `asset_qr_token_history` (
  `history_id` int NOT NULL AUTO_INCREMENT,
  `asset_id` int NOT NULL,
  `asset_code` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `asset_name` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `old_qr_public_token` varchar(120) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `new_qr_public_token` varchar(120) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `old_qr_code` text COLLATE utf8mb4_unicode_ci,
  `new_qr_code` text COLLATE utf8mb4_unicode_ci,
  `reissue_reason` varchar(500) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `reissued_by_user_id` int DEFAULT NULL,
  `reissued_by_username` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `reissued_by_role` varchar(80) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`history_id`),
  KEY `idx_asset_qr_token_history_asset` (`asset_id`),
  KEY `idx_asset_qr_token_history_old_token` (`old_qr_public_token`),
  KEY `idx_asset_qr_token_history_new_token` (`new_qr_public_token`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `asset_requests` (
  `request_id` int NOT NULL AUTO_INCREMENT,
  `employee_id` int NOT NULL,
  `department_id` int DEFAULT NULL,
  `division_id` int DEFAULT NULL,
  `location_id` int DEFAULT NULL,
  `category_id` int NOT NULL,
  `request_type` enum('NEW_ASSET','REPLACEMENT','REPAIR_SUPPORT','RETURN_SUPPORT') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'NEW_ASSET',
  `request_date` date NOT NULL,
  `required_by_date` date DEFAULT NULL,
  -- 'PENDING_DEPT_HEAD' added: an employee's own request now sits here first
  -- when their department has an active department head, instead of going
  -- straight to 'PENDING' (Asset Manager review). 'PENDING' now specifically
  -- means "no dept-head stage applies, or the dept head already forwarded it -
  -- awaiting Asset Manager/Admin/Super Admin decision", which is exactly the
  -- state AssetRequestDAO.updateRequestStatus()'s existing transition guard
  -- already requires before allowing APPROVED/REJECTED, so the Asset Manager
  -- path needed no change to enforce this - a request stuck in
  -- PENDING_DEPT_HEAD simply cannot match that guard's WHERE clause.
  `request_status` enum('PENDING_DEPT_HEAD','PENDING','APPROVED','REJECTED','FULFILLED','CANCELLED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'PENDING',
  `priority` enum('LOW','NORMAL','HIGH','URGENT') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'NORMAL',
  `approved_by` int DEFAULT NULL,
  `approved_date` date DEFAULT NULL,
  `fulfilled_asset_id` int DEFAULT NULL,
  -- Was never actually populated anywhere in the codebase (fulfilled_asset_id
  -- itself wasn't either - "FULFILLED" was a bare status flip with no asset
  -- or allocation ever linked). Both are now set together when a request is
  -- marked FULFILLED: fulfilled_allocation_id records exactly which
  -- asset_allocation row satisfied the request (the actor picks one of the
  -- employee's active allocations), and fulfilled_asset_id is derived from
  -- it, kept for backward compatibility with existing reads (view_request.jsp).
  `fulfilled_allocation_id` int DEFAULT NULL,
  `request_reason` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `remarks` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  -- Department Head review stage - deliberately separate columns from
  -- approved_by/approved_date/remarks above, which remain exclusively the
  -- Asset Manager/Admin/Super Admin's final decision. Mirrors the same
  -- "X_by/X_date" attribution pairing already used throughout this schema
  -- (issued_by/received_by, verified_by_user_id, disposal's approval chain).
  `dept_head_action` enum('FORWARDED','REJECTED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `dept_head_by` int DEFAULT NULL,
  `dept_head_date` date DEFAULT NULL,
  `dept_head_remarks` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`request_id`),
  KEY `idx_requests_employee_id` (`employee_id`),
  KEY `idx_requests_department_id` (`department_id`),
  KEY `idx_requests_division_id` (`division_id`),
  KEY `idx_requests_location_id` (`location_id`),
  KEY `idx_requests_category_id` (`category_id`),
  KEY `idx_requests_status` (`request_status`),
  KEY `idx_requests_priority` (`priority`),
  KEY `idx_requests_approved_by` (`approved_by`),
  KEY `idx_requests_fulfilled_asset_id` (`fulfilled_asset_id`),
  KEY `idx_requests_dept_head_by` (`dept_head_by`),
  KEY `idx_requests_fulfilled_allocation_id` (`fulfilled_allocation_id`)
) ENGINE=InnoDB AUTO_INCREMENT=26 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `asset_returns` (
  `return_id` int NOT NULL AUTO_INCREMENT,
  `allocation_id` int NOT NULL,
  `asset_id` int NOT NULL,
  `employee_id` int NOT NULL,
  `return_date` date NOT NULL,
  `return_condition` enum('GOOD','DAMAGED','NEEDS_REPAIR') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'GOOD',
  `received_by` int DEFAULT NULL,
  `return_location_id` int DEFAULT NULL,
  `action_after_return` enum('MARK_AVAILABLE','SEND_TO_MAINTENANCE','MARK_DAMAGED','DISPOSE_RECOMMENDED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'MARK_AVAILABLE',
  `remarks` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`return_id`),
  UNIQUE KEY `uk_asset_returns_allocation` (`allocation_id`),
  KEY `idx_asset_returns_asset_id` (`asset_id`),
  KEY `idx_asset_returns_employee_id` (`employee_id`),
  KEY `idx_asset_returns_received_by` (`received_by`),
  KEY `idx_asset_returns_location_id` (`return_location_id`),
  KEY `idx_asset_returns_condition` (`return_condition`)
) ENGINE=InnoDB AUTO_INCREMENT=11 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `assets` (
  `asset_id` int NOT NULL AUTO_INCREMENT,
  `asset_code` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `asset_name` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `category_id` int NOT NULL,
  `vendor_id` int DEFAULT NULL,
  `serial_number` varchar(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `model_number` varchar(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `purchase_date` date DEFAULT NULL,
  `purchase_cost` decimal(12,2) DEFAULT '0.00',
  `warranty_expiry` date DEFAULT NULL,
  `department_id` int DEFAULT NULL,
  `division_id` int DEFAULT NULL,
  `location_id` int DEFAULT NULL,
  `location` varchar(180) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `asset_status` enum('AVAILABLE','ALLOCATED','UNDER_MAINTENANCE','DISPOSED','LOST','DAMAGED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'AVAILABLE',
  `condition_status` enum('GOOD','DAMAGED','NEEDS_REPAIR') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'GOOD',
  `service_status` enum('SERVICEABLE','NEEDS_ATTENTION','UNDER_REPAIR','UNSERVICEABLE','SCRAP_RECOMMENDED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'SERVICEABLE',
  `last_physical_verification_date` date DEFAULT NULL,
  `qr_code` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `qr_public_token` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `asset_image_path` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `depreciation_rate` decimal(5,2) DEFAULT '0.00',
  `remarks` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_by` int DEFAULT NULL,
  `updated_by` int DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`asset_id`),
  UNIQUE KEY `uk_assets_asset_code` (`asset_code`),
  UNIQUE KEY `uk_assets_qr_public_token` (`qr_public_token`),
  UNIQUE KEY `uk_assets_serial_number` (`serial_number`),
  KEY `idx_assets_category_id` (`category_id`),
  KEY `idx_assets_vendor_id` (`vendor_id`),
  KEY `idx_assets_department_id` (`department_id`),
  KEY `idx_assets_division_id` (`division_id`),
  KEY `idx_assets_location_id` (`location_id`),
  KEY `idx_assets_asset_status` (`asset_status`),
  KEY `idx_assets_condition_status` (`condition_status`),
  KEY `fk_assets_created_by` (`created_by`),
  KEY `fk_assets_updated_by` (`updated_by`)
) ENGINE=InnoDB AUTO_INCREMENT=94 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- Warranty renewal history (Follow-up: competitor feature comparison). Also
-- self-created at runtime by WarrantyRenewalDAO.ensureTable() via
-- CREATE TABLE IF NOT EXISTS (same pattern as system_settings in
-- QrUrlUtil), so this feature works on an existing deployment without a
-- manual migration step. This definition is here for fresh installs / docs.
CREATE TABLE `warranty_renewals` (
  `renewal_id` int NOT NULL AUTO_INCREMENT,
  `asset_id` int NOT NULL,
  `previous_expiry` date DEFAULT NULL,
  `new_expiry` date NOT NULL,
  `extension_months` int DEFAULT NULL,
  `renewal_cost` decimal(12,2) DEFAULT '0.00',
  `notes` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  `renewed_by` int DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`renewal_id`),
  KEY `idx_warranty_renewals_asset` (`asset_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- Employee self-service profile change requests (Follow-up: competitor
-- feature comparison). Also self-created at runtime by
-- ProfileChangeRequestDAO.ensureTable() via CREATE TABLE IF NOT EXISTS
-- (same self-heal pattern as warranty_renewals above).
CREATE TABLE `profile_change_requests` (
  `request_id` int NOT NULL AUTO_INCREMENT,
  `employee_id` int NOT NULL,
  `field_name` varchar(30) NOT NULL,
  `current_value` varchar(255) DEFAULT NULL,
  `requested_value` varchar(255) NOT NULL,
  `reason` varchar(500) DEFAULT NULL,
  `status` enum('PENDING','APPROVED','REJECTED') NOT NULL DEFAULT 'PENDING',
  `reviewed_by` int DEFAULT NULL,
  `review_note` varchar(500) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `reviewed_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`request_id`),
  KEY `idx_profile_change_requests_employee` (`employee_id`),
  KEY `idx_profile_change_requests_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- Vendor compliance documents (Follow-up: competitor feature comparison).
-- Mirrors asset_documents' structure exactly. Also self-created at runtime
-- by VendorDocumentDAO.ensureTable() via CREATE TABLE IF NOT EXISTS.
CREATE TABLE `vendor_documents` (
  `document_id` int NOT NULL AUTO_INCREMENT,
  `vendor_id` int NOT NULL,
  `document_type` enum('TRADE_LICENSE','GST_CERTIFICATE','PAN_CARD','COMPLIANCE_CERTIFICATE','OTHER') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'OTHER',
  `original_file_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `stored_file_path` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `mime_type` varchar(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `file_size` bigint DEFAULT NULL,
  `uploaded_by` int DEFAULT NULL,
  `uploaded_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`document_id`),
  KEY `idx_vendor_documents_vendor` (`vendor_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `audit_logs` (
  `audit_id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` int DEFAULT NULL,
  `username` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `user_role` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `module_name` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `action_type` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `record_id` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `action_details` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  `ip_address` varchar(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `user_agent` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`audit_id`),
  KEY `idx_audit_user_id` (`user_id`),
  KEY `idx_audit_module` (`module_name`),
  KEY `idx_audit_action` (`action_type`),
  KEY `idx_audit_created_at` (`created_at`)
) ENGINE=InnoDB AUTO_INCREMENT=285 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `category_vendor_mapping` (
  `mapping_id` int NOT NULL AUTO_INCREMENT,
  `category_id` int NOT NULL,
  `vendor_id` int NOT NULL,
  `status` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'ACTIVE',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`mapping_id`),
  UNIQUE KEY `uq_category_vendor` (`category_id`,`vendor_id`),
  KEY `fk_cvm_vendor` (`vendor_id`)
) ENGINE=InnoDB AUTO_INCREMENT=92 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `copilot_query_logs` (
  `log_id` int NOT NULL AUTO_INCREMENT,
  `user_id` int DEFAULT NULL,
  `question` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `answer` text COLLATE utf8mb4_unicode_ci,
  `query_type` varchar(80) COLLATE utf8mb4_unicode_ci DEFAULT 'RULE_BASED',
  `tokens_used` int DEFAULT '0',
  `response_ms` int DEFAULT '0',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`log_id`),
  KEY `idx_user_id` (`user_id`),
  KEY `idx_created_at` (`created_at`)
) ENGINE=InnoDB AUTO_INCREMENT=25 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `departments` (
  `department_id` int NOT NULL AUTO_INCREMENT,
  `department_name` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `department_head_user_id` int DEFAULT NULL,
  `status` enum('ACTIVE','INACTIVE') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'ACTIVE',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `department_code` varchar(30) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`department_id`),
  UNIQUE KEY `uk_departments_department_name` (`department_name`),
  UNIQUE KEY `department_code` (`department_code`),
  KEY `idx_departments_head_user` (`department_head_user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=19 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `document_vault` (
  `doc_id` int NOT NULL AUTO_INCREMENT,
  `ref_type` enum('ASSET','EMPLOYEE','VENDOR','MAINTENANCE','DISPOSAL','RETURN','VERIFICATION','REQUEST') COLLATE utf8mb4_unicode_ci NOT NULL,
  `ref_id` int NOT NULL,
  `doc_type` varchar(80) COLLATE utf8mb4_unicode_ci NOT NULL,
  `doc_name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `file_path` varchar(500) COLLATE utf8mb4_unicode_ci NOT NULL,
  `file_size_kb` int DEFAULT '0',
  `mime_type` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `description` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `uploaded_by` int DEFAULT NULL,
  `uploaded_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `is_active` tinyint(1) DEFAULT '1',
  PRIMARY KEY (`doc_id`),
  KEY `idx_ref` (`ref_type`,`ref_id`),
  KEY `idx_uploaded_at` (`uploaded_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `email_logs` (
  `log_id` int NOT NULL AUTO_INCREMENT,
  `recipient` varchar(150) COLLATE utf8mb4_unicode_ci NOT NULL,
  `subject` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `body_preview` varchar(500) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `status` enum('SENT','FAILED','PENDING','SKIPPED') COLLATE utf8mb4_unicode_ci DEFAULT 'PENDING',
  `error_msg` varchar(500) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `sent_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `created_by` int DEFAULT NULL,
  PRIMARY KEY (`log_id`),
  KEY `idx_status` (`status`),
  KEY `idx_sent_at` (`sent_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `employees` (
  `employee_id` int NOT NULL AUTO_INCREMENT,
  `employee_code` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
    `employee_name` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `designation` varchar(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `email` varchar(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `phone` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `department_id` int NOT NULL,
  `division_id` int DEFAULT NULL,
  `location_id` int DEFAULT NULL,
  `user_id` int DEFAULT NULL,
  `joining_date` date DEFAULT NULL,
  `employee_status` enum('ACTIVE','INACTIVE','TRANSFERRED','RETIRED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'ACTIVE',
  `status` enum('ACTIVE','INACTIVE') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'ACTIVE',
  `is_deleted` tinyint(1) DEFAULT '0',
  `deleted_at` timestamp NULL DEFAULT NULL,
  `deleted_by` int DEFAULT NULL,
  `delete_reason` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `department_name` varchar(150) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`employee_id`),
  UNIQUE KEY `uk_employees_employee_code` (`employee_code`),
  UNIQUE KEY `uk_employees_email` (`email`),
  UNIQUE KEY `uk_employees_user_id` (`user_id`),
  KEY `idx_employees_department_id` (`department_id`),
  KEY `idx_employees_division_id` (`division_id`),
  KEY `idx_employees_location_id` (`location_id`)
) ENGINE=InnoDB AUTO_INCREMENT=85 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `employee_documents` (
  `document_id` int NOT NULL AUTO_INCREMENT,
  `employee_id` int NOT NULL,
  `document_title` varchar(150) COLLATE utf8mb4_unicode_ci NOT NULL,
  `document_type` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `original_file_name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `stored_file_name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `stored_file_path` varchar(500) COLLATE utf8mb4_unicode_ci NOT NULL,
  `mime_type` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `file_size` bigint DEFAULT '0',
  `uploaded_by` int DEFAULT NULL,
  `uploaded_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `status` varchar(20) COLLATE utf8mb4_unicode_ci DEFAULT 'ACTIVE',
  PRIMARY KEY (`document_id`),
  KEY `idx_employee_docs_employee` (`employee_id`),
  CONSTRAINT `fk_employee_docs_employee` FOREIGN KEY (`employee_id`) REFERENCES `employees` (`employee_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `login_security_attempts` (
  `attempt_id` int NOT NULL AUTO_INCREMENT,
  `attempted_username` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `failure_type` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `remote_address` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `user_agent` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `matched_user_id` int DEFAULT '0',
  `alert_sent` tinyint(1) DEFAULT '0',
  `attempt_time` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`attempt_id`),
  KEY `idx_login_security_attempts` (`attempted_username`,`failure_type`,`remote_address`,`attempt_time`)
) ENGINE=InnoDB AUTO_INCREMENT=33 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `maintenance_logs` (
  `maintenance_id` int NOT NULL AUTO_INCREMENT,
  `asset_id` int NOT NULL,
  `maintenance_type` enum('PREVENTIVE','CORRECTIVE','REPAIR','INSPECTION') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'PREVENTIVE',
  `maintenance_date` date NOT NULL,
  `next_due_date` date DEFAULT NULL,
  `issue_reported` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `work_done` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `maintenance_status` enum('OPEN','IN_PROGRESS','COMPLETED','CANCELLED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'OPEN',
  `cost` decimal(12,2) DEFAULT '0.00',
  `vendor_id` int DEFAULT NULL,
  `performed_by_employee_id` int DEFAULT NULL,
  `approved_by` int DEFAULT NULL,
  `remarks` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`maintenance_id`),
  KEY `idx_maintenance_asset_id` (`asset_id`),
  KEY `idx_maintenance_vendor_id` (`vendor_id`),
  KEY `idx_maintenance_employee_id` (`performed_by_employee_id`),
  KEY `idx_maintenance_approved_by` (`approved_by`),
  KEY `idx_maintenance_status` (`maintenance_status`),
  KEY `idx_maintenance_date` (`maintenance_date`)
) ENGINE=InnoDB AUTO_INCREMENT=20 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `notification_logs` (
  `notification_id` int NOT NULL AUTO_INCREMENT,
  `notification_type` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `module_name` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `reference_id` int DEFAULT NULL,
  `recipient_email` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `subject` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `message_body` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `status` enum('QUEUED','SENT','FAILED','SKIPPED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'QUEUED',
  `error_message` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  `sent_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`notification_id`),
  KEY `idx_notification_module` (`module_name`),
  KEY `idx_notification_status` (`status`),
  KEY `idx_notification_sent_at` (`sent_at`)
) ENGINE=InnoDB AUTO_INCREMENT=170 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `notification_settings` (
  `setting_id` int NOT NULL AUTO_INCREMENT,
  `maintenance_alerts` tinyint(1) DEFAULT '1',
  `request_alerts` tinyint(1) DEFAULT '1',
  `return_alerts` tinyint(1) DEFAULT '1',
  `audit_alerts` tinyint(1) DEFAULT '1',
  `email_alerts` tinyint(1) DEFAULT '1',
  `dashboard_alerts` tinyint(1) DEFAULT '1',
  `updated_by` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `warranty_alerts` tinyint(1) DEFAULT '1',
  `qr_scan_alerts` tinyint(1) DEFAULT '0',
  `backup_alerts` tinyint(1) DEFAULT '1',
  `copilot_digest_alerts` tinyint(1) DEFAULT '1',
  PRIMARY KEY (`setting_id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `password_reset_tokens` (
  `token_id` int NOT NULL AUTO_INCREMENT,
  `user_id` int NOT NULL,
  `token` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `expires_at` timestamp NOT NULL,
  `used` tinyint(1) DEFAULT '0',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`token_id`),
  UNIQUE KEY `token` (`token`),
  KEY `idx_token` (`token`),
  KEY `idx_user_id` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `physical_verification` (
  `verification_id` int NOT NULL AUTO_INCREMENT,
  `asset_id` int NOT NULL,
  `verification_date` date NOT NULL,
  `verified_by_employee_id` int DEFAULT NULL,
  `verified_by_user_id` int DEFAULT NULL,
  `expected_location_id` int DEFAULT NULL,
  `actual_location_id` int DEFAULT NULL,
  `expected_holder_employee_id` int DEFAULT NULL,
  `actual_holder_employee_id` int DEFAULT NULL,
  `asset_found` enum('YES','NO') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'YES',
  `verification_status` enum('PENDING','VERIFIED','LOCATION_MISMATCH','HOLDER_MISMATCH','REPAIR_FLAGGED','NOT_FOUND') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'PENDING',
  `physical_condition` enum('GOOD','DAMAGED','NEEDS_REPAIR') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'GOOD',
  `remarks` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`verification_id`),
  KEY `idx_pv_asset_id` (`asset_id`),
  KEY `idx_pv_verified_by_employee` (`verified_by_employee_id`),
  KEY `idx_pv_verified_by_user` (`verified_by_user_id`),
  KEY `idx_pv_expected_location` (`expected_location_id`),
  KEY `idx_pv_actual_location` (`actual_location_id`),
  KEY `idx_pv_expected_holder` (`expected_holder_employee_id`),
  KEY `idx_pv_actual_holder` (`actual_holder_employee_id`),
  KEY `idx_pv_status` (`verification_status`),
  KEY `idx_pv_date` (`verification_date`)
) ENGINE=InnoDB AUTO_INCREMENT=91 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `physical_verification_duties` (
  `duty_id` int NOT NULL AUTO_INCREMENT,
  `verification_round_id` int DEFAULT NULL,
  `assigned_employee_id` int NOT NULL,
  `assigned_department_id` int DEFAULT NULL,
  `duty_status` enum('SCHEDULED','IN_PROGRESS','SUBMITTED','COMPLETED','CANCELLED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'SCHEDULED',
  `scheduled_from` date NOT NULL,
  `scheduled_to` date DEFAULT NULL,
  `instructions` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  `created_by_user_id` int DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`duty_id`),
  KEY `idx_pvd_round` (`verification_round_id`),
  KEY `idx_pvd_employee` (`assigned_employee_id`),
  KEY `idx_pvd_department` (`assigned_department_id`),
  KEY `idx_pvd_status` (`duty_status`),
  KEY `idx_pvd_schedule` (`scheduled_from`,`scheduled_to`)
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `physical_verification_rounds` (
  `verification_round_id` int NOT NULL AUTO_INCREMENT,
  `round_code` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `round_title` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `verification_type` enum('ANNUAL','SPECIAL','SURPRISE','DEPARTMENT','LOCATION','GENERAL','PHYSICAL','SCHEDULED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'ANNUAL',
  `start_date` date DEFAULT NULL,
  `end_date` date DEFAULT NULL,
  `status` enum('SCHEDULED','IN_PROGRESS','COMPLETED','CANCELLED','ACTIVE','OPEN','PENDING') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'IN_PROGRESS',
  `created_by_user_id` int DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`verification_round_id`),
  UNIQUE KEY `uk_pv_round_code` (`round_code`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `public_asset_snapshot` (
  `snapshot_id` bigint NOT NULL AUTO_INCREMENT,
  `asset_id` int NOT NULL,
  `qr_public_token` varchar(120) COLLATE utf8mb4_unicode_ci NOT NULL,
  `asset_code` varchar(80) COLLATE utf8mb4_unicode_ci NOT NULL,
  `asset_name` varchar(180) COLLATE utf8mb4_unicode_ci NOT NULL,
  `category_name` varchar(120) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `asset_status` varchar(50) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `department_name` varchar(120) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `division_name` varchar(150) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `location_name` varchar(180) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `warranty_expiry` date DEFAULT NULL,
  `last_physical_verification_date` date DEFAULT NULL,
  `maintenance_indicator` varchar(80) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `token_active` tinyint(1) NOT NULL DEFAULT '1',
  `last_synced_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`snapshot_id`),
  UNIQUE KEY `uk_public_snapshot_token` (`qr_public_token`),
  UNIQUE KEY `uk_public_snapshot_asset` (`asset_id`),
  KEY `idx_public_snapshot_status` (`asset_status`)
) ENGINE=InnoDB AUTO_INCREMENT=15 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `public_qr_base_urls` (
  `id` int NOT NULL AUTO_INCREMENT,
  `label` varchar(100) DEFAULT NULL,
  `provider_type` varchar(50) DEFAULT NULL,
  `base_url` varchar(255) DEFAULT NULL,
  `is_active` tinyint(1) DEFAULT '0',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


CREATE TABLE `qr_sync_queue` (
  `queue_id` bigint NOT NULL AUTO_INCREMENT,
  `asset_id` int NOT NULL,
  `qr_public_token` varchar(120) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `sync_action` enum('UPSERT','INVALIDATE','DELETE') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'UPSERT',
  `sync_status` enum('PENDING','PROCESSING','SYNCED','FAILED') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'PENDING',
  `attempt_count` int NOT NULL DEFAULT '0',
  `last_error` text COLLATE utf8mb4_unicode_ci,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`queue_id`),
  KEY `idx_qr_sync_status` (`sync_status`),
  KEY `idx_qr_sync_asset` (`asset_id`)
) ENGINE=InnoDB AUTO_INCREMENT=15 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `railway_divisions` (
  `division_id` int NOT NULL AUTO_INCREMENT,
  `zone_id` int NOT NULL,
  `division_code` varchar(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `division_name` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `division_type` enum('HEADQUARTERS','DIVISION') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'DIVISION',
  `division_headquarters` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `status` enum('ACTIVE','INACTIVE') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'ACTIVE',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`division_id`),
  UNIQUE KEY `uk_railway_divisions_code` (`division_code`),
  KEY `idx_railway_divisions_zone_id` (`zone_id`)
) ENGINE=InnoDB AUTO_INCREMENT=14 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `railway_locations` (
  `location_id` int NOT NULL AUTO_INCREMENT,
  `division_id` int NOT NULL,
  `department_id` int DEFAULT NULL,
  `location_code` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `location_name` varchar(180) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `location_type` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `building_block` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `floor_level` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `room_no` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `status` enum('ACTIVE','INACTIVE') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'ACTIVE',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`location_id`),
  UNIQUE KEY `uk_railway_locations_code` (`location_code`),
  KEY `idx_railway_locations_division_id` (`division_id`),
  KEY `idx_railway_locations_department_id` (`department_id`)
) ENGINE=InnoDB AUTO_INCREMENT=26 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `railway_zones` (
  `zone_id` int NOT NULL AUTO_INCREMENT,
  `zone_code` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `zone_name` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `headquarters` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `state_name` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `status` enum('ACTIVE','INACTIVE') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'ACTIVE',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`zone_id`),
  UNIQUE KEY `uk_railway_zones_code` (`zone_code`),
  UNIQUE KEY `uk_railway_zones_name` (`zone_name`)
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `roles` (
  `role_id` int NOT NULL AUTO_INCREMENT,
  `role_name` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`role_id`),
  UNIQUE KEY `uk_roles_role_name` (`role_name`)
) ENGINE=InnoDB AUTO_INCREMENT=6 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `role_assignment_log` (
  `log_id` int NOT NULL AUTO_INCREMENT,
  `assigned_to` int NOT NULL,
  `assigned_by` int NOT NULL,
  `old_role` varchar(50) DEFAULT NULL,
  `new_role` varchar(50) NOT NULL,
  `timestamp` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `is_emergency` boolean DEFAULT FALSE,
  PRIMARY KEY (`log_id`),
  KEY `idx_log_assigned_to` (`assigned_to`),
  KEY `idx_log_assigned_by` (`assigned_by`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `system_settings` (
  `setting_id` int NOT NULL AUTO_INCREMENT,
  `setting_key` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `setting_value` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  `setting_group` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'GENERAL',
  `description` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `updated_by` int DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `org_name` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `system_name` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `office_location` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `contact_email` varchar(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `support_phone` varchar(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `currency` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `timezone` varchar(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`setting_id`),
  UNIQUE KEY `uk_system_settings_key` (`setting_key`),
  KEY `idx_system_settings_group` (`setting_group`),
  KEY `idx_system_settings_updated_by` (`updated_by`)
) ENGINE=InnoDB AUTO_INCREMENT=162 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `users` (
  `user_id` int NOT NULL AUTO_INCREMENT,
  `username` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `password_plaintext` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `password_crypt` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `email` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `current_role` enum('super_admin','admin','asset_manager','auditor','dept_head','employee') NOT NULL DEFAULT 'employee',
  -- Fault (Critical, fixed): ~13 call sites across this codebase (LoginServlet,
  -- GenerateEmployeeLoginServlet, AuditDAO, RoleAssignmentDAO, DepartmentDAO,
  -- NotificationHelper/NotificationRecipientResolver, TransferEmployeeServlet,
  -- UpdateEmployeeServlet, AddEmployeeServlet, and both seed/setup SQL scripts)
  -- read or write `users.role_id` and JOIN it against `roles.role_id`, but this
  -- column never existed in this file - a fresh install built strictly from
  -- schema.sql would fail every one of those call sites (most swallowed into a
  -- silently-wrong default by a try/catch, GenerateEmployeeLoginServlet's INSERT
  -- hitting a hard 500). `current_role` remains the actual authorization source
  -- (RoleAuthorizationFilter/RoleAccessUtil key off it, not role_id) - role_id
  -- exists so the application's own `roles` lookup-table joins resolve, kept in
  -- sync with `current_role` by the application layer (see UpdateUserRoleServlet,
  -- RoleAssignmentDAO). Nullable/no-FK-yet default so this column can be added to
  -- an existing table before it's backfilled - see migrations/005_add_users_role_id.sql
  -- for already-deployed databases and the FK added below for fresh installs.
  `role_id` int DEFAULT NULL,
  `employee_id` int DEFAULT NULL,
  `status` enum('ACTIVE','INACTIVE') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'ACTIVE',
  `force_password_change` tinyint(1) NOT NULL DEFAULT '0',
  `created_by` int DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `last_login_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`user_id`),
  UNIQUE KEY `uk_users_username` (`username`),
  UNIQUE KEY `uk_users_email` (`email`),
  KEY `idx_users_employee_id` (`employee_id`),
  KEY `idx_users_created_by` (`created_by`),
  KEY `idx_users_role_id` (`role_id`)
) ENGINE=InnoDB AUTO_INCREMENT=10 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE `vendors` (
  `vendor_id` int NOT NULL AUTO_INCREMENT,
  `vendor_name` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `contact_person` varchar(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `email` varchar(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `phone` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `address` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `gst_number` varchar(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `vendor_status` enum('ACTIVE','INACTIVE') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'ACTIVE',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`vendor_id`),
  UNIQUE KEY `uk_vendors_name` (`vendor_name`),
  UNIQUE KEY `uk_vendors_email` (`email`)
) ENGINE=InnoDB AUTO_INCREMENT=53 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;




-- Foreign Keys
ALTER TABLE `asset_allocation` ADD CONSTRAINT `fk_allocation_asset` FOREIGN KEY (`asset_id`) REFERENCES `assets` (`asset_id`) ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE `asset_allocation` ADD CONSTRAINT `fk_allocation_employee` FOREIGN KEY (`employee_id`) REFERENCES `employees` (`employee_id`) ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE `asset_allocation` ADD CONSTRAINT `fk_allocation_issue_location` FOREIGN KEY (`issue_location_id`) REFERENCES `railway_locations` (`location_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `asset_allocation` ADD CONSTRAINT `fk_allocation_issued_by` FOREIGN KEY (`issued_by`) REFERENCES `users` (`user_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `asset_allocation` ADD CONSTRAINT `fk_allocation_received_by` FOREIGN KEY (`received_by`) REFERENCES `users` (`user_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `users` ADD CONSTRAINT `fk_users_role` FOREIGN KEY (`role_id`) REFERENCES `roles` (`role_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `asset_disposal` ADD CONSTRAINT `fk_disposal_approved_by` FOREIGN KEY (`approved_by`) REFERENCES `users` (`user_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `asset_disposal` ADD CONSTRAINT `fk_disposal_asset` FOREIGN KEY (`asset_id`) REFERENCES `assets` (`asset_id`) ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE `asset_disposal` ADD CONSTRAINT `fk_disposal_requested_by` FOREIGN KEY (`requested_by`) REFERENCES `users` (`user_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `asset_document_text_index` ADD CONSTRAINT `asset_document_text_index_ibfk_1` FOREIGN KEY (`document_id`) REFERENCES `asset_documents` (`document_id`) ON DELETE CASCADE;
ALTER TABLE `asset_document_text_index` ADD CONSTRAINT `asset_document_text_index_ibfk_2` FOREIGN KEY (`asset_id`) REFERENCES `assets` (`asset_id`) ON DELETE CASCADE;
ALTER TABLE `asset_documents` ADD CONSTRAINT `fk_asset_documents_asset` FOREIGN KEY (`asset_id`) REFERENCES `assets` (`asset_id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `asset_documents` ADD CONSTRAINT `fk_asset_documents_uploaded_by` FOREIGN KEY (`uploaded_by`) REFERENCES `users` (`user_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `asset_qr_scan_logs` ADD CONSTRAINT `fk_qr_scan_asset` FOREIGN KEY (`asset_id`) REFERENCES `assets` (`asset_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `asset_qr_scan_logs` ADD CONSTRAINT `fk_qr_scan_employee` FOREIGN KEY (`scanned_by_employee_id`) REFERENCES `employees` (`employee_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `asset_qr_scan_logs` ADD CONSTRAINT `fk_qr_scan_user` FOREIGN KEY (`scanned_by_user_id`) REFERENCES `users` (`user_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `asset_qr_token_history` ADD CONSTRAINT `fk_qr_token_history_asset` FOREIGN KEY (`asset_id`) REFERENCES `assets` (`asset_id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `asset_requests` ADD CONSTRAINT `fk_requests_approved_by` FOREIGN KEY (`approved_by`) REFERENCES `users` (`user_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `asset_requests` ADD CONSTRAINT `fk_requests_category` FOREIGN KEY (`category_id`) REFERENCES `asset_categories` (`category_id`) ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE `asset_requests` ADD CONSTRAINT `fk_requests_department` FOREIGN KEY (`department_id`) REFERENCES `departments` (`department_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `asset_requests` ADD CONSTRAINT `fk_requests_division` FOREIGN KEY (`division_id`) REFERENCES `railway_divisions` (`division_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `asset_requests` ADD CONSTRAINT `fk_requests_employee` FOREIGN KEY (`employee_id`) REFERENCES `employees` (`employee_id`) ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE `asset_requests` ADD CONSTRAINT `fk_requests_fulfilled_asset` FOREIGN KEY (`fulfilled_asset_id`) REFERENCES `assets` (`asset_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `asset_requests` ADD CONSTRAINT `fk_requests_location` FOREIGN KEY (`location_id`) REFERENCES `railway_locations` (`location_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `asset_requests` ADD CONSTRAINT `fk_requests_fulfilled_allocation` FOREIGN KEY (`fulfilled_allocation_id`) REFERENCES `asset_allocation` (`allocation_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `asset_requests` ADD CONSTRAINT `fk_requests_dept_head_by` FOREIGN KEY (`dept_head_by`) REFERENCES `users` (`user_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `asset_returns` ADD CONSTRAINT `fk_returns_allocation` FOREIGN KEY (`allocation_id`) REFERENCES `asset_allocation` (`allocation_id`) ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE `asset_returns` ADD CONSTRAINT `fk_returns_asset` FOREIGN KEY (`asset_id`) REFERENCES `assets` (`asset_id`) ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE `asset_returns` ADD CONSTRAINT `fk_returns_employee` FOREIGN KEY (`employee_id`) REFERENCES `employees` (`employee_id`) ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE `asset_returns` ADD CONSTRAINT `fk_returns_location` FOREIGN KEY (`return_location_id`) REFERENCES `railway_locations` (`location_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `asset_returns` ADD CONSTRAINT `fk_returns_received_by` FOREIGN KEY (`received_by`) REFERENCES `users` (`user_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `assets` ADD CONSTRAINT `fk_assets_category` FOREIGN KEY (`category_id`) REFERENCES `asset_categories` (`category_id`) ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE `assets` ADD CONSTRAINT `fk_assets_created_by` FOREIGN KEY (`created_by`) REFERENCES `users` (`user_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `assets` ADD CONSTRAINT `fk_assets_department` FOREIGN KEY (`department_id`) REFERENCES `departments` (`department_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `assets` ADD CONSTRAINT `fk_assets_division` FOREIGN KEY (`division_id`) REFERENCES `railway_divisions` (`division_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `assets` ADD CONSTRAINT `fk_assets_location` FOREIGN KEY (`location_id`) REFERENCES `railway_locations` (`location_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `assets` ADD CONSTRAINT `fk_assets_updated_by` FOREIGN KEY (`updated_by`) REFERENCES `users` (`user_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `assets` ADD CONSTRAINT `fk_assets_vendor` FOREIGN KEY (`vendor_id`) REFERENCES `vendors` (`vendor_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `audit_logs` ADD CONSTRAINT `fk_audit_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `category_vendor_mapping` ADD CONSTRAINT `fk_cvm_category` FOREIGN KEY (`category_id`) REFERENCES `asset_categories` (`category_id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `category_vendor_mapping` ADD CONSTRAINT `fk_cvm_vendor` FOREIGN KEY (`vendor_id`) REFERENCES `vendors` (`vendor_id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `departments` ADD CONSTRAINT `fk_departments_head_user` FOREIGN KEY (`department_head_user_id`) REFERENCES `users` (`user_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `employees` ADD CONSTRAINT `fk_employees_department` FOREIGN KEY (`department_id`) REFERENCES `departments` (`department_id`) ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE `employees` ADD CONSTRAINT `fk_employees_division` FOREIGN KEY (`division_id`) REFERENCES `railway_divisions` (`division_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `employees` ADD CONSTRAINT `fk_employees_location` FOREIGN KEY (`location_id`) REFERENCES `railway_locations` (`location_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `employees` ADD CONSTRAINT `fk_employees_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `maintenance_logs` ADD CONSTRAINT `fk_maintenance_approved_by` FOREIGN KEY (`approved_by`) REFERENCES `users` (`user_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `maintenance_logs` ADD CONSTRAINT `fk_maintenance_asset` FOREIGN KEY (`asset_id`) REFERENCES `assets` (`asset_id`) ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE `maintenance_logs` ADD CONSTRAINT `fk_maintenance_employee` FOREIGN KEY (`performed_by_employee_id`) REFERENCES `employees` (`employee_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `maintenance_logs` ADD CONSTRAINT `fk_maintenance_vendor` FOREIGN KEY (`vendor_id`) REFERENCES `vendors` (`vendor_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `physical_verification` ADD CONSTRAINT `fk_pv_actual_holder` FOREIGN KEY (`actual_holder_employee_id`) REFERENCES `employees` (`employee_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `physical_verification` ADD CONSTRAINT `fk_pv_actual_location` FOREIGN KEY (`actual_location_id`) REFERENCES `railway_locations` (`location_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `physical_verification` ADD CONSTRAINT `fk_pv_asset` FOREIGN KEY (`asset_id`) REFERENCES `assets` (`asset_id`) ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE `physical_verification` ADD CONSTRAINT `fk_pv_expected_holder` FOREIGN KEY (`expected_holder_employee_id`) REFERENCES `employees` (`employee_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `physical_verification` ADD CONSTRAINT `fk_pv_expected_location` FOREIGN KEY (`expected_location_id`) REFERENCES `railway_locations` (`location_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `physical_verification` ADD CONSTRAINT `fk_pv_verified_employee` FOREIGN KEY (`verified_by_employee_id`) REFERENCES `employees` (`employee_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `physical_verification` ADD CONSTRAINT `fk_pv_verified_user` FOREIGN KEY (`verified_by_user_id`) REFERENCES `users` (`user_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `railway_divisions` ADD CONSTRAINT `fk_railway_divisions_zone` FOREIGN KEY (`zone_id`) REFERENCES `railway_zones` (`zone_id`) ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE `railway_locations` ADD CONSTRAINT `fk_railway_locations_department` FOREIGN KEY (`department_id`) REFERENCES `departments` (`department_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `railway_locations` ADD CONSTRAINT `fk_railway_locations_division` FOREIGN KEY (`division_id`) REFERENCES `railway_divisions` (`division_id`) ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE `system_settings` ADD CONSTRAINT `fk_system_settings_updated_by` FOREIGN KEY (`updated_by`) REFERENCES `users` (`user_id`) ON DELETE SET NULL ON UPDATE CASCADE;

-- Employee Maintenance Requests table
CREATE TABLE maintenance_requests (
  request_id INT AUTO_INCREMENT PRIMARY KEY,
  asset_id INT NOT NULL,
  employee_id INT NOT NULL,
  request_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  issue_description TEXT NOT NULL,
  priority VARCHAR(20) DEFAULT 'MEDIUM',
  request_status VARCHAR(30) DEFAULT 'PENDING',
  remarks TEXT,
  -- Links a request to the maintenance_logs row that actually resolved it,
  -- populated when a request is marked COMPLETED (UpdateMaintenanceRequestStatusServlet).
  -- Previously the two tables only connected by timing coincidence - this
  -- makes "which log resolved this request" a directly queryable fact.
  -- Nullable: a request can still be completed with no matching log to pick
  -- from (e.g. no maintenance_logs row exists yet for that asset).
  resolved_maintenance_id INT DEFAULT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (asset_id) REFERENCES assets(asset_id),
  FOREIGN KEY (employee_id) REFERENCES employees(employee_id),
  -- ON DELETE SET NULL (unlike the two ownership FKs above, which default to
  -- RESTRICT): this is a soft backreference to the log that happened to
  -- resolve the request, not an ownership relationship, so removing the log
  -- should not block or cascade-delete the request record.
  FOREIGN KEY (resolved_maintenance_id) REFERENCES maintenance_logs(maintenance_id) ON DELETE SET NULL,
  KEY idx_maintenance_requests_resolved_id (resolved_maintenance_id)
);
CREATE TABLE IF NOT EXISTS employee_role_assignments (
    assignment_id INT AUTO_INCREMENT PRIMARY KEY,
    employee_id INT NOT NULL,
    user_id INT NULL,
    role_code VARCHAR(50) NOT NULL,
    department_id INT NULL,
    designation_title VARCHAR(100) NULL,
    assignment_status ENUM('ACTIVE','INACTIVE') DEFAULT 'ACTIVE',
    effective_from DATE NOT NULL DEFAULT (CURRENT_DATE),
    effective_to DATE NULL,
    assigned_by_user_id INT NOT NULL,
    remarks VARCHAR(255) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (employee_id) REFERENCES employees(employee_id) ON DELETE CASCADE,
    FOREIGN KEY (department_id) REFERENCES departments(department_id) ON DELETE SET NULL
);

CREATE INDEX idx_era_employee ON employee_role_assignments(employee_id);
CREATE INDEX idx_era_user ON employee_role_assignments(user_id);
CREATE INDEX idx_era_role_status ON employee_role_assignments(role_code, assignment_status);
CREATE INDEX idx_era_department ON employee_role_assignments(department_id);

-- asset_transfers: a completed-transfer LOG (who an asset moved from/to,
-- when, why, authorized by whom). Confirmed live on this database but never
-- previously captured in schema.sql - a fresh install built strictly from
-- this file would have failed CopilotToolExecutor.getAssetTransferHistory()
-- (Module: AI Copilot), the one existing piece of code that already reads
-- this table, the same class of drift already fixed once for users.role_id
-- (migration 005). Documented here now as the source of truth for fresh
-- installs; column shapes match the live table exactly (source_allocation_id/
-- target_allocation_id are each UNIQUE and NOT NULL - a log row is only ever
-- written once both allocations genuinely exist, i.e. after a transfer has
-- actually completed, never for a pending proposal).
--
-- It was never populated by any write path - genuinely "unused by any core
-- workflow", the exact gap the project report's Future Scope flagged, just
-- not by a nonexistent table as first (mis)assumed. asset_transfer_requests
-- below is the maker-checker workflow that now writes into it on approval.
CREATE TABLE IF NOT EXISTS asset_transfers (
    transfer_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    asset_id INT NOT NULL,
    source_allocation_id INT NOT NULL,
    target_allocation_id INT NOT NULL,
    from_employee_id INT NOT NULL,
    to_employee_id INT NOT NULL,
    transfer_date DATE NOT NULL,
    transfer_reason VARCHAR(255) NOT NULL,
    authorized_by INT DEFAULT NULL,
    created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_asset_transfers_source_alloc (source_allocation_id),
    UNIQUE KEY uk_asset_transfers_target_alloc (target_allocation_id),
    KEY idx_asset_transfers_asset_id (asset_id),
    KEY idx_asset_transfers_from_emp (from_employee_id),
    KEY idx_asset_transfers_to_emp (to_employee_id),
    KEY idx_asset_transfers_date (transfer_date),
    KEY idx_asset_transfers_auth (authorized_by)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE `asset_transfers` ADD CONSTRAINT `fk_asset_transfers_asset` FOREIGN KEY (`asset_id`) REFERENCES `assets` (`asset_id`) ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE `asset_transfers` ADD CONSTRAINT `fk_asset_transfers_auth` FOREIGN KEY (`authorized_by`) REFERENCES `users` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE `asset_transfers` ADD CONSTRAINT `fk_asset_transfers_from_emp` FOREIGN KEY (`from_employee_id`) REFERENCES `employees` (`employee_id`) ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE `asset_transfers` ADD CONSTRAINT `fk_asset_transfers_source_alloc` FOREIGN KEY (`source_allocation_id`) REFERENCES `asset_allocation` (`allocation_id`) ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE `asset_transfers` ADD CONSTRAINT `fk_asset_transfers_target_alloc` FOREIGN KEY (`target_allocation_id`) REFERENCES `asset_allocation` (`allocation_id`) ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE `asset_transfers` ADD CONSTRAINT `fk_asset_transfers_to_emp` FOREIGN KEY (`to_employee_id`) REFERENCES `employees` (`employee_id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- Employee-to-employee transfer WORKFLOW (maker-checker, same shape as
-- asset_disposal): an employee (or Asset Manager/Admin/Super Admin on their
-- behalf) proposes transferring one of their allocated assets to a named
-- colleague; a Super Admin/Admin/Asset Manager separately reviews it.
-- Deliberately a separate table from asset_transfers above rather than
-- adding PENDING/REJECTED states to it directly: asset_transfers' own
-- target_allocation_id is NOT NULL, because a log row is only ever written
-- once the new allocation genuinely exists - a pending proposal has no
-- target allocation yet. On approval, AssetTransferDAO.reviewTransfer()
-- closes the source allocation, opens a new one for the receiving employee,
-- and inserts the resulting row into asset_transfers - the append-only log's
-- existing shape and the one tool that already reads it are both left
-- completely unchanged.
CREATE TABLE IF NOT EXISTS asset_transfer_requests (
    request_id INT AUTO_INCREMENT PRIMARY KEY,
    allocation_id INT NOT NULL,
    asset_id INT NOT NULL,
    from_employee_id INT NOT NULL,
    to_employee_id INT NOT NULL,
    transfer_reason VARCHAR(255) DEFAULT NULL,
    request_status ENUM('PENDING','REJECTED','COMPLETED') DEFAULT 'PENDING',
    requested_by INT DEFAULT NULL,
    requested_date DATE DEFAULT NULL,
    reviewed_by INT DEFAULT NULL,
    reviewed_date DATE DEFAULT NULL,
    remarks VARCHAR(255) DEFAULT NULL,
    -- Set only on COMPLETED - the asset_transfers log row this request
    -- produced, giving full traceability from the request to its outcome.
    transfer_id BIGINT DEFAULT NULL,
    created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY idx_transfer_requests_allocation_id (allocation_id),
    KEY idx_transfer_requests_asset_id (asset_id),
    KEY idx_transfer_requests_from_employee_id (from_employee_id),
    KEY idx_transfer_requests_to_employee_id (to_employee_id),
    KEY idx_transfer_requests_status (request_status),
    KEY idx_transfer_requests_requested_by (requested_by),
    KEY idx_transfer_requests_reviewed_by (reviewed_by),
    KEY idx_transfer_requests_transfer_id (transfer_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE `asset_transfer_requests` ADD CONSTRAINT `fk_transfer_requests_allocation` FOREIGN KEY (`allocation_id`) REFERENCES `asset_allocation` (`allocation_id`) ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE `asset_transfer_requests` ADD CONSTRAINT `fk_transfer_requests_asset` FOREIGN KEY (`asset_id`) REFERENCES `assets` (`asset_id`) ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE `asset_transfer_requests` ADD CONSTRAINT `fk_transfer_requests_from_employee` FOREIGN KEY (`from_employee_id`) REFERENCES `employees` (`employee_id`) ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE `asset_transfer_requests` ADD CONSTRAINT `fk_transfer_requests_to_employee` FOREIGN KEY (`to_employee_id`) REFERENCES `employees` (`employee_id`) ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE `asset_transfer_requests` ADD CONSTRAINT `fk_transfer_requests_requested_by` FOREIGN KEY (`requested_by`) REFERENCES `users` (`user_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `asset_transfer_requests` ADD CONSTRAINT `fk_transfer_requests_reviewed_by` FOREIGN KEY (`reviewed_by`) REFERENCES `users` (`user_id`) ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE `asset_transfer_requests` ADD CONSTRAINT `fk_transfer_requests_transfer` FOREIGN KEY (`transfer_id`) REFERENCES `asset_transfers` (`transfer_id`) ON DELETE SET NULL ON UPDATE CASCADE;

-- Persistent AMS Copilot conversation history, keyed per user so a follow-up
-- question ("what about last month?") still resolves correctly after a
-- session timeout, a logout/login, or switching devices - CopilotChatMemory
-- previously stored the rolling transcript only in the HttpSession, which is
-- gone the moment that session ends. See CopilotChatHistoryDAO/CopilotChatMemory.
CREATE TABLE IF NOT EXISTS copilot_chat_history (
    history_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    question TEXT NOT NULL,
    answer MEDIUMTEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

CREATE INDEX idx_copilot_chat_history_user ON copilot_chat_history(user_id, history_id);

-- Per-answer thumbs-up/down feedback on the AMS Copilot, the one signal
-- missing on real usage quality - every other quality check in this codebase
-- (CopilotRegressionTest, CopilotContextUnderstandingTest, etc.) is a fixed
-- test suite; nothing captures whether a REAL answer, in production, was
-- actually useful. See CopilotFeedbackDAO/CopilotFeedbackServlet.
--
-- Named copilot_answer_feedback, not copilot_feedback: a table by that
-- exact name already exists live in this database (columns conversation_id/
-- message_id/rating INT/comment/user_code) with no matching code anywhere
-- in this repo - an orphan from something else entirely. Left untouched
-- rather than assumed safe to repurpose or drop.
CREATE TABLE IF NOT EXISTS copilot_answer_feedback (
    feedback_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    question TEXT NOT NULL,
    answer MEDIUMTEXT NOT NULL,
    rating ENUM('UP','DOWN') NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

CREATE INDEX idx_copilot_answer_feedback_user ON copilot_answer_feedback(user_id, created_at);
CREATE INDEX idx_copilot_answer_feedback_rating ON copilot_answer_feedback(rating, created_at);
