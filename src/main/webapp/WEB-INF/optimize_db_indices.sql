-- -----------------------------------------------------------------------------
-- Railway Asset Management System (IR-AMS)
-- Database Optimization: Indices & Integrity Script
-- -----------------------------------------------------------------------------

-- 1. Optimize Audit Logs (Heavily queried for tracking and reports)
CREATE INDEX idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX idx_audit_logs_module_action ON audit_logs(module_name, action_type);
CREATE INDEX idx_audit_logs_timestamp ON audit_logs(timestamp);

-- 2. Optimize Assets (Often filtered by status, category, and department)
CREATE INDEX idx_assets_asset_status ON assets(asset_status);
CREATE INDEX idx_assets_category_id ON assets(category_id);
CREATE INDEX idx_assets_department_id ON assets(department_id);

-- 3. Optimize QR Scans (Scanned frequently by users/IPs)
CREATE INDEX idx_qr_scans_asset_id ON qr_scan_logs(asset_id);
CREATE INDEX idx_qr_scans_scanned_by ON qr_scan_logs(scanned_by_user_id);
CREATE INDEX idx_qr_scans_scan_time ON qr_scan_logs(scan_time);

-- 4. Optimize Allocations (Frequently checked for active allocations)
CREATE INDEX idx_allocation_asset_id ON allocation(asset_id);
CREATE INDEX idx_allocation_employee_id ON allocation(employee_id);
CREATE INDEX idx_allocation_status ON allocation(status);

-- 5. Optimize Requests (Filtered by status and requestor)
CREATE INDEX idx_requests_status ON asset_requests(status);
CREATE INDEX idx_requests_employee_id ON asset_requests(employee_id);
CREATE INDEX idx_requests_created_at ON asset_requests(created_at);

-- 6. Add Missing Foreign Keys (If any are dropped or missing)
-- Assumes standard MySQL InnoDB constraints. 
-- NOTE: If these already exist, this step might throw a duplicate key error, 
-- which is safe to ignore during manual execution.
ALTER TABLE allocation 
ADD CONSTRAINT fk_allocation_asset 
FOREIGN KEY (asset_id) REFERENCES assets(asset_id) ON DELETE CASCADE;

ALTER TABLE allocation 
ADD CONSTRAINT fk_allocation_employee 
FOREIGN KEY (employee_id) REFERENCES employees(employee_id) ON DELETE CASCADE;

ALTER TABLE asset_requests 
ADD CONSTRAINT fk_requests_employee 
FOREIGN KEY (employee_id) REFERENCES employees(employee_id) ON DELETE CASCADE;
