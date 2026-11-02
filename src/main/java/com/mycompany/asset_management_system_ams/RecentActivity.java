package com.mycompany.asset_management_system_ams;

public class RecentActivity {

    private int auditId;
    private String action;
    private String tableName;
    private String remarks;
    private String actionTime;
    private String ipAddress;

    public RecentActivity(int auditId, String action, String tableName, String remarks, String actionTime) {
        this(auditId, action, tableName, remarks, actionTime, "");
    }

    public RecentActivity(int auditId, String action, String tableName, String remarks, String actionTime, String ipAddress) {
        this.auditId = auditId;
        this.action = action;
        this.tableName = tableName;
        this.remarks = remarks;
        this.actionTime = actionTime;
        this.ipAddress = ipAddress;
    }

    public int getAuditId() {
        return auditId;
    }

    public String getAction() {
        return action;
    }

    public String getTableName() {
        return tableName;
    }

    public String getRemarks() {
        return remarks;
    }

    public String getActionTime() {
        return actionTime;
    }

    public String getIpAddress() {
        return ipAddress;
    }
}