package com.mycompany.asset_management_system_ams;

import java.math.BigDecimal;

public class Vendor {

    private int vendorId;
    private String vendorName;
    private String contactPerson;
    private String email;
    private String phone;
    private String address;
    private String createdAt;

    private int assetCount;
    private BigDecimal totalPurchaseValue;

    // Fault, found live: VendorDAO's queries already SELECT v.vendor_status,
    // but mapVendor() never read it onto this object, so the value was
    // fetched from MySQL and silently discarded on every single row before
    // it ever reached vendors.jsp. Confirmed live: deleting a supplier
    // (soft-disable - see VendorDAO.deleteVendor()) genuinely set
    // vendor_status to INACTIVE in the database, but the Suppliers page had
    // no way to know that, so the "deleted" row stayed listed with its
    // Delete button still showing, indistinguishable from an active
    // supplier - Delete looked like it silently did nothing.
    private String status;

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

    public String getContactPerson() {
        return contactPerson;
    }

    public void setContactPerson(String contactPerson) {
        this.contactPerson = contactPerson;
    }

    public String getEmail() {
        return email;
    }

    public void setEmail(String email) {
        this.email = email;
    }
    
    public String getPhone() {
        return phone;
    }

    public void setPhone(String phone) {
        this.phone = phone;
    }
    
    public String getAddress() {
        return address;
    }

    public void setAddress(String address) {
        this.address = address;
    }

    public String getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(String createdAt) {
        this.createdAt = createdAt;
    }

    public int getAssetCount() {
        return assetCount;
    }

    public void setAssetCount(int assetCount) {
        this.assetCount = assetCount;
    }

    public BigDecimal getTotalPurchaseValue() {
        return totalPurchaseValue;
    }

    public void setTotalPurchaseValue(BigDecimal totalPurchaseValue) {
        this.totalPurchaseValue = totalPurchaseValue;
    }

    public String getStatus() {
        return status;
    }

    public void setStatus(String status) {
        this.status = status;
    }
}