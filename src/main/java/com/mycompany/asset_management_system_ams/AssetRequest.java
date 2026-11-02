package com.mycompany.asset_management_system_ams;

public class AssetRequest {

    private int requestId;
    private String employeeName;
    private String employeeCode;
    private String categoryName;
    private String requestDate;
    private String requestStatus;
    private String approvedBy;
    private String remarks;
    private String departmentName;
    private String deptHeadAction;
    private String deptHeadByName;
    private String deptHeadDate;
    private String deptHeadRemarks;

    public int getRequestId() {
        return requestId;
    }

    public void setRequestId(int requestId) {
        this.requestId = requestId;
    }

    public String getEmployeeName() {
        return employeeName;
    }

    public void setEmployeeName(String employeeName) {
        this.employeeName = employeeName;
    }

    public String getEmployeeCode() {
        return employeeCode;
    }

    public void setEmployeeCode(String employeeCode) {
        this.employeeCode = employeeCode;
    }

    public String getCategoryName() {
        return categoryName;
    }

    public void setCategoryName(String categoryName) {
        this.categoryName = categoryName;
    }

    public String getRequestDate() {
        return requestDate;
    }

    public void setRequestDate(String requestDate) {
        this.requestDate = requestDate;
    }

    public String getRequestStatus() {
        return requestStatus;
    }

    public void setRequestStatus(String requestStatus) {
        this.requestStatus = requestStatus;
    }

    public String getApprovedBy() {
        return approvedBy;
    }

    public void setApprovedBy(String approvedBy) {
        this.approvedBy = approvedBy;
    }

    public String getRemarks() {
        return remarks;
    }

    public void setRemarks(String remarks) {
        this.remarks = remarks;
    }

    public String getDepartmentName() {
        return departmentName;
    }

    public void setDepartmentName(String departmentName) {
        this.departmentName = departmentName;
    }

    public String getDeptHeadAction() {
        return deptHeadAction;
    }

    public void setDeptHeadAction(String deptHeadAction) {
        this.deptHeadAction = deptHeadAction;
    }

    public String getDeptHeadByName() {
        return deptHeadByName;
    }

    public void setDeptHeadByName(String deptHeadByName) {
        this.deptHeadByName = deptHeadByName;
    }

    public String getDeptHeadDate() {
        return deptHeadDate;
    }

    public void setDeptHeadDate(String deptHeadDate) {
        this.deptHeadDate = deptHeadDate;
    }

    public String getDeptHeadRemarks() {
        return deptHeadRemarks;
    }

    public void setDeptHeadRemarks(String deptHeadRemarks) {
        this.deptHeadRemarks = deptHeadRemarks;
    }
}