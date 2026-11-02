-- Migration: Add IN_PROGRESS to duty_status and support for approval workflow

-- 1. Add IN_PROGRESS to duty_status if not present. Assuming duty_status is an ENUM.
-- (Adjust the ENUM values list to match your existing schema + 'IN_PROGRESS')
ALTER TABLE physical_verification_duties 
MODIFY COLUMN duty_status ENUM('ASSIGNED', 'IN_PROGRESS', 'SUBMITTED', 'CANCELLED') DEFAULT 'ASSIGNED';

-- 2. Ensure review_status supports PENDING, APPROVED, REJECTED.
-- Currently the servlet mentions it is generated or not updatable, but we need to update it.
ALTER TABLE asset_physical_verification 
MODIFY COLUMN review_status ENUM('PENDING', 'APPROVED', 'REJECTED') DEFAULT 'PENDING';
