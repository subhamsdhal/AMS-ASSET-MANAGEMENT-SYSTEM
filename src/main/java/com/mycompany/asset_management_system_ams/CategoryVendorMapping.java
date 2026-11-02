package com.mycompany.asset_management_system_ams;

public class CategoryVendorMapping {

    private int mappingId;
    private int categoryId;
    private String categoryName;
    private int vendorId;
    private String vendorName;
    private String status;
    private String createdAt;

    private int linkedAssetCount;

    public int getMappingId() {
        return mappingId;
    }

    public void setMappingId(int mappingId) {
        this.mappingId = mappingId;
    }

    public int getCategoryId() {
        return categoryId;
    }

    public void setCategoryId(int categoryId) {
        this.categoryId = categoryId;
    }

    public String getCategoryName() {
        return categoryName;
    }

    public void setCategoryName(String categoryName) {
        this.categoryName = categoryName;
    }

    public int getVendorId() {
        return vendorId;
    }

    public void setVendorId(int vendorId) {
        this.vendorId = vendorId;
    }

    public String getVendorName() {
        return vendorName;
    }

    public void setVendorName(String vendorName) {
        this.vendorName = vendorName;
    }

    public String getStatus() {
        return status;
    }

    public void setStatus(String status) {
        this.status = status;
    }

    public String getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(String createdAt) {
        this.createdAt = createdAt;
    }

    public int getLinkedAssetCount() {
        return linkedAssetCount;
    }

    public void setLinkedAssetCount(int linkedAssetCount) {
        this.linkedAssetCount = linkedAssetCount;
    }

    public String getSupplierName() {
        return vendorName;
    }

    public void setSupplierName(String supplierName) {
        this.vendorName = supplierName;
    }

    public int getSupplierId() {
        return vendorId;
    }

    public void setSupplierId(int supplierId) {
        this.vendorId = supplierId;
    }
}