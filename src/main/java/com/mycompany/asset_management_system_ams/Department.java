package com.mycompany.asset_management_system_ams;

import java.sql.Timestamp;

public class Department {

    private int departmentId;
    private String departmentName;
    private String description;
    private int departmentHeadUserId;
    private String status;
    private Timestamp createdAt;
    private Timestamp updatedAt;
    private String departmentCode;
    
    private String departmentHeadName; // Extra field for view
    private int assetCount;
    private int employeeCount;

    public Department() {
    }

    public int getDepartmentId() { return departmentId; }
    public void setDepartmentId(int departmentId) { this.departmentId = departmentId; }

    public String getDepartmentName() { return departmentName; }
    public void setDepartmentName(String departmentName) { this.departmentName = departmentName; }

    public String getDescription() { return description; }
    public void setDescription(String description) { this.description = description; }

    public int getDepartmentHeadUserId() { return departmentHeadUserId; }
    public void setDepartmentHeadUserId(int departmentHeadUserId) { this.departmentHeadUserId = departmentHeadUserId; }

    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }

    public Timestamp getCreatedAt() { return createdAt; }
    public void setCreatedAt(Timestamp createdAt) { this.createdAt = createdAt; }

    public Timestamp getUpdatedAt() { return updatedAt; }
    public void setUpdatedAt(Timestamp updatedAt) { this.updatedAt = updatedAt; }

    public String getDepartmentCode() { return departmentCode; }
    public void setDepartmentCode(String departmentCode) { this.departmentCode = departmentCode; }

    public String getDepartmentHeadName() { return departmentHeadName; }
    public void setDepartmentHeadName(String departmentHeadName) { this.departmentHeadName = departmentHeadName; }

    public int getAssetCount() { return assetCount; }
    public void setAssetCount(int assetCount) { this.assetCount = assetCount; }

    public int getEmployeeCount() { return employeeCount; }
    public void setEmployeeCount(int employeeCount) { this.employeeCount = employeeCount; }
}
