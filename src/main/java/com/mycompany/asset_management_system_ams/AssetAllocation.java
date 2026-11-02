package com.mycompany.asset_management_system_ams;

public class AssetAllocation {

    private int allocationId;
    private int assetId;
    private int employeeId;

    private String assetCode;
    private String assetName;

    private String employeeCode;
    private String employeeName;

    private String departmentName;

    private String allocationDate;
    private String returnDate;
    private String allocationStatus;
    private String remarks;

    // Employee self-service transfer preference (see migrations/003_employee_
    // transfer_asset_preferences.sql) - null until the employee submits one via
    // employee_transfer_preference.jsp. Purely advisory: TransferEmployeeServlet
    // shows it to the admin finalizing the transfer as a pre-filled suggestion,
    // never applies it automatically.
    private String employeeTransferPreference;
    private String employeeTransferNote;
    private String employeeTransferRequestedAt;

    public int getAllocationId() {
        return allocationId;
    }

    public void setAllocationId(int allocationId) {
        this.allocationId = allocationId;
    }

    public int getAssetId() {
        return assetId;
    }

    public void setAssetId(int assetId) {
        this.assetId = assetId;
    }

    public int getEmployeeId() {
        return employeeId;
    }

    public void setEmployeeId(int employeeId) {
        this.employeeId = employeeId;
    }

    public String getAssetCode() {
        return assetCode;
    }

    public void setAssetCode(String assetCode) {
        this.assetCode = assetCode;
    }

    public String getAssetName() {
        return assetName;
    }

    public void setAssetName(String assetName) {
        this.assetName = assetName;
    }

    public String getEmployeeCode() {
        return employeeCode;
    }

    public void setEmployeeCode(String employeeCode) {
        this.employeeCode = employeeCode;
    }

    public String getEmployeeName() {
        return employeeName;
    }

    public void setEmployeeName(String employeeName) {
        this.employeeName = employeeName;
    }

    public String getDepartmentName() {
        return departmentName;
    }

    public void setDepartmentName(String departmentName) {
        this.departmentName = departmentName;
    }

    public String getAllocationDate() {
        return allocationDate;
    }

    public void setAllocationDate(String allocationDate) {
        this.allocationDate = allocationDate;
    }

    public String getReturnDate() {
        return returnDate;
    }

    public void setReturnDate(String returnDate) {
        this.returnDate = returnDate;
    }

    public String getAllocationStatus() {
        return allocationStatus;
    }

    public void setAllocationStatus(String allocationStatus) {
        this.allocationStatus = allocationStatus;
    }

    public String getRemarks() {
        return remarks;
    }

    public void setRemarks(String remarks) {
        this.remarks = remarks;
    }

    public String getEmployeeTransferPreference() {
        return employeeTransferPreference;
    }

    public void setEmployeeTransferPreference(String employeeTransferPreference) {
        this.employeeTransferPreference = employeeTransferPreference;
    }

    public String getEmployeeTransferNote() {
        return employeeTransferNote;
    }

    public void setEmployeeTransferNote(String employeeTransferNote) {
        this.employeeTransferNote = employeeTransferNote;
    }

    public String getEmployeeTransferRequestedAt() {
        return employeeTransferRequestedAt;
    }

    public void setEmployeeTransferRequestedAt(String employeeTransferRequestedAt) {
        this.employeeTransferRequestedAt = employeeTransferRequestedAt;
    }
}