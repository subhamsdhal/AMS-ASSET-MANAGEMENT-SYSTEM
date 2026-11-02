package com.mycompany.asset_management_system_ams;

/**
 * ProfileChangeRequest - one employee-submitted "please change my X"
 * request, reviewed and approved/rejected by an admin.
 *
 * Was a gap found comparing against a competing team's build of the same
 * brief: employees there can request a profile field change with a reason,
 * and an admin reviews current-value vs. requested-value side by side
 * before approving. This app previously had no employee-initiated,
 * admin-approved path at all - only an admin directly editing the employee
 * record themselves.
 */
public class ProfileChangeRequest {

    private int requestId;
    private int employeeId;
    private String employeeCode;
    private String employeeName;
    private String fieldName;
    private String currentValue;
    private String requestedValue;
    private String reason;
    private String status;
    private String reviewedByUsername;
    private String reviewNote;
    private String createdAt;
    private String reviewedAt;
    private String departmentName;

    public int getRequestId() {
        return requestId;
    }

    public void setRequestId(int requestId) {
        this.requestId = requestId;
    }

    public int getEmployeeId() {
        return employeeId;
    }

    public void setEmployeeId(int employeeId) {
        this.employeeId = employeeId;
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

    public String getFieldName() {
        return fieldName;
    }

    public void setFieldName(String fieldName) {
        this.fieldName = fieldName;
    }

    public String getCurrentValue() {
        return currentValue;
    }

    public void setCurrentValue(String currentValue) {
        this.currentValue = currentValue;
    }

    public String getRequestedValue() {
        return requestedValue;
    }

    public void setRequestedValue(String requestedValue) {
        this.requestedValue = requestedValue;
    }

    public String getReason() {
        return reason;
    }

    public void setReason(String reason) {
        this.reason = reason;
    }

    public String getStatus() {
        return status;
    }

    public void setStatus(String status) {
        this.status = status;
    }

    public String getReviewedByUsername() {
        return reviewedByUsername;
    }

    public void setReviewedByUsername(String reviewedByUsername) {
        this.reviewedByUsername = reviewedByUsername;
    }

    public String getReviewNote() {
        return reviewNote;
    }

    public void setReviewNote(String reviewNote) {
        this.reviewNote = reviewNote;
    }

    public String getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(String createdAt) {
        this.createdAt = createdAt;
    }

    public String getReviewedAt() {
        return reviewedAt;
    }

    public void setReviewedAt(String reviewedAt) {
        this.reviewedAt = reviewedAt;
    }

    public String getDepartmentName() {
        return departmentName;
    }

    public void setDepartmentName(String departmentName) {
        this.departmentName = departmentName;
    }
}
