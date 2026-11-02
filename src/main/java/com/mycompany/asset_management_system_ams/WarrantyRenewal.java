package com.mycompany.asset_management_system_ams;

/**
 * WarrantyRenewal - one row in an asset's warranty renewal history.
 *
 * Was the concrete gap found comparing against a competing team's build of
 * the same brief: this app only ever stored a single flat
 * assets.warranty_expiry date, so renewing a warranty just overwrote the
 * only record of the previous coverage period - there was no way to answer
 * "how many times has this asset's warranty been renewed, and what did each
 * renewal cost?" This class plus WarrantyRenewalDAO/warranty_renewals is
 * that history.
 */
public class WarrantyRenewal {

    private int renewalId;
    private int assetId;
    private String previousExpiry;
    private String newExpiry;
    private Integer extensionMonths;
    private double renewalCost;
    private String notes;
    private String renewedByUsername;
    private String createdAt;

    public int getRenewalId() {
        return renewalId;
    }

    public void setRenewalId(int renewalId) {
        this.renewalId = renewalId;
    }

    public int getAssetId() {
        return assetId;
    }

    public void setAssetId(int assetId) {
        this.assetId = assetId;
    }

    public String getPreviousExpiry() {
        return previousExpiry;
    }

    public void setPreviousExpiry(String previousExpiry) {
        this.previousExpiry = previousExpiry;
    }

    public String getNewExpiry() {
        return newExpiry;
    }

    public void setNewExpiry(String newExpiry) {
        this.newExpiry = newExpiry;
    }

    public Integer getExtensionMonths() {
        return extensionMonths;
    }

    public void setExtensionMonths(Integer extensionMonths) {
        this.extensionMonths = extensionMonths;
    }

    public double getRenewalCost() {
        return renewalCost;
    }

    public void setRenewalCost(double renewalCost) {
        this.renewalCost = renewalCost;
    }

    public String getNotes() {
        return notes;
    }

    public void setNotes(String notes) {
        this.notes = notes;
    }

    public String getRenewedByUsername() {
        return renewedByUsername;
    }

    public void setRenewedByUsername(String renewedByUsername) {
        this.renewedByUsername = renewedByUsername;
    }

    public String getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(String createdAt) {
        this.createdAt = createdAt;
    }
}
