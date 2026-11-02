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
