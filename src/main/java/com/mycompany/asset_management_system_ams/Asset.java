package com.mycompany.asset_management_system_ams;

public class Asset {

    private int assetId;
    private String assetCode;
    private String assetName;
    private String categoryName;
    private String vendorName;
    private String serialNumber;
    private String qrCode;
    private String assetImagePath;
    private String location;
    private String purchaseDate;
    private double purchaseCost;
    private String warrantyExpiry;
    private String assetStatus;
    private double depreciationRate;

    public int getAssetId() {
        return assetId;
    }

    public void setAssetId(int assetId) {
        this.assetId = assetId;
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

    public String getCategoryName() {
        return categoryName;
    }

    public void setCategoryName(String categoryName) {
        this.categoryName = categoryName;
    }

    public String getVendorName() {
        return vendorName;
    }

    public void setVendorName(String vendorName) {
        this.vendorName = vendorName;
    }

    public String getSerialNumber() {
        return serialNumber;
    }

    public void setSerialNumber(String serialNumber) {
        this.serialNumber = serialNumber;
    }

    public String getQrCode() {
        return qrCode;
    }

    public void setQrCode(String qrCode) {
        this.qrCode = qrCode;
    }

    public String getAssetImagePath() {
        return assetImagePath;
    }

    public void setAssetImagePath(String assetImagePath) {
        this.assetImagePath = assetImagePath;
    }

    public String getLocation() {
        return location;
    }

    public void setLocation(String location) {
        this.location = location;
    }

    public String getPurchaseDate() {
        return purchaseDate;
    }

    public void setPurchaseDate(String purchaseDate) {
        this.purchaseDate = purchaseDate;
    }

    public double getPurchaseCost() {
        return purchaseCost;
    }

    public void setPurchaseCost(double purchaseCost) {
        this.purchaseCost = purchaseCost;
    }

    public String getWarrantyExpiry() {
        return warrantyExpiry;
    }

    public void setWarrantyExpiry(String warrantyExpiry) {
        this.warrantyExpiry = warrantyExpiry;
    }

    public String getAssetStatus() {
        return assetStatus;
    }

    public void setAssetStatus(String assetStatus) {
        this.assetStatus = assetStatus;
    }

    public double getDepreciationRate() {
        return depreciationRate;
    }

    public void setDepreciationRate(double depreciationRate) {
        this.depreciationRate = depreciationRate;
    }
}
