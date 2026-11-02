<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="jakarta.servlet.http.HttpServletRequest"%>

<%!
    private String safeText(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "N/A";
        }

        return value.trim()
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
    }

    private String cleanLabel(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "N/A";
        }

        String text = value.trim().replace("_", " ").toLowerCase(Locale.ENGLISH);
        String[] parts = text.split("\\s+");
        StringBuilder out = new StringBuilder();

        for (String part : parts) {
            if (part.length() > 0) {
                out.append(Character.toUpperCase(part.charAt(0)))
                        .append(part.substring(1))
                        .append(" ");
            }
        }

        return out.toString().trim();
    }

    private String rowValue(Map<String, String> row, String key) {
        if (row == null) {
            return "";
        }

        String value = row.get(key);
        return value == null ? "" : value;
    }

    private String clientIp(HttpServletRequest request) {
        String ip = request.getHeader("X-Forwarded-For");

        if (ip != null && !ip.trim().isEmpty()) {
            return ip.split(",")[0].trim();
        }

        ip = request.getHeader("X-Real-IP");

        if (ip != null && !ip.trim().isEmpty()) {
            return ip.trim();
        }

        return request.getRemoteAddr();
    }

    private String limitText(String value, int max) {
        if (value == null) {
            return "";
        }

        value = value.trim();

        if (value.length() <= max) {
            return value;
        }

        return value.substring(0, max);
    }

    private String nowText() {
        return new java.text.SimpleDateFormat("dd MMM yyyy, hh:mm a").format(new java.util.Date());
    }

    private boolean tableExists(Connection con, String tableName) {
        String sql = "SELECT COUNT(*) FROM information_schema.tables "
                + "WHERE table_schema = DATABASE() AND table_name = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, tableName);

            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }

        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    private boolean columnExists(Connection con, String tableName, String columnName) {
        String sql = "SELECT COUNT(*) FROM information_schema.columns "
                + "WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, tableName);
            ps.setString(2, columnName);

            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }

        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    private String normalizeToken(String rawToken) {
        if (rawToken == null) {
            return "";
        }

        String token = rawToken.trim();

        if (token.contains("token=")) {
            int index = token.indexOf("token=");
            token = token.substring(index + 6);

            int ampIndex = token.indexOf("&");

            if (ampIndex >= 0) {
                token = token.substring(0, ampIndex);
            }
        }

        if (token.contains("qr=")) {
            int index = token.indexOf("qr=");
            token = token.substring(index + 3);

            int ampIndex = token.indexOf("&");

            if (ampIndex >= 0) {
                token = token.substring(0, ampIndex);
            }
        }

        if (token.contains("code=")) {
            int index = token.indexOf("code=");
            token = token.substring(index + 5);

            int ampIndex = token.indexOf("&");

            if (ampIndex >= 0) {
                token = token.substring(0, ampIndex);
            }
        }

        return token.trim();
    }

    private Map<String, String> getAssetSnapshotByToken(Connection con, String token) {
        Map<String, String> row = new HashMap<String, String>();

        if (token == null || token.trim().isEmpty() || !tableExists(con, "public_asset_snapshot")) {
            return row;
        }

        String sql = "SELECT "
                + "CAST(asset_id AS CHAR) AS asset_id, "
                + "asset_code, asset_name, category_name, asset_status, "
                + "department_name, division_name, location_name, "
                + "'' AS warranty_expiry, "
                + "DATE_FORMAT(last_physical_verification_date, '%d %b %Y') AS last_physical_verification_date, "
                + "maintenance_indicator, '' AS qr_public_token, "
                + "DATE_FORMAT(last_synced_at, '%d %b %Y, %h:%i %p') AS updated_at, "
                + "'' AS serial_number, '' AS model_number, '' AS vendor_name, "
                + "'' AS location_code, '' AS location_type, '' AS condition_status, '' AS service_status, "
                // Holder identity is intentionally requested here as a product decision - the
                // snapshot table itself still stores these blank (see below), so
                // fetchActiveAllocation() is what actually fills them in from the live
                // allocation/employee tables after this query runs, for both this and the
                // fallback lookup path.
                + "'' AS holder_name, '' AS holder_code, '' AS holder_designation, '' AS allocation_date, "
                + "'' AS qr_code, '' AS remarks "
                + "FROM public_asset_snapshot "
                + "WHERE qr_public_token = ? AND token_active = 1 "
                + "LIMIT 1";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, token.trim());

            try (ResultSet rs = ps.executeQuery()) {
                ResultSetMetaData meta = rs.getMetaData();
                int count = meta.getColumnCount();

                if (rs.next()) {
                    for (int i = 1; i <= count; i++) {
                        row.put(meta.getColumnLabel(i), rs.getString(i));
                    }
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return row;
    }

    private Map<String, String> getAssetByAnyQrValue(Connection con, String token) {
        Map<String, String> row = new HashMap<String, String>();

        if (token == null || token.trim().isEmpty()) {
            return row;
        }

        if (!tableExists(con, "assets")) {
            return row;
        }

        token = token.trim();

        boolean hasCategories = tableExists(con, "asset_categories");
        boolean hasVendors = tableExists(con, "vendors");
        boolean hasDepartments = tableExists(con, "departments");
        boolean hasDivisions = tableExists(con, "railway_divisions");
        boolean hasLocations = tableExists(con, "railway_locations");
        boolean hasAllocation = tableExists(con, "asset_allocation");
        boolean hasEmployees = tableExists(con, "employees");
        boolean hasReturns = tableExists(con, "asset_returns");
        boolean hasMaintenance = tableExists(con, "maintenance_logs");
        boolean aAssetId = columnExists(con, "assets", "asset_id");
        boolean aAssetCode = columnExists(con, "assets", "asset_code");
        boolean aRailwayAssetNo = columnExists(con, "assets", "railway_asset_no");
        boolean aAssetName = columnExists(con, "assets", "asset_name");
        boolean aSerialNumber = columnExists(con, "assets", "serial_number");
        boolean aModelNumber = columnExists(con, "assets", "model_number");
        boolean aPurchaseDate = columnExists(con, "assets", "purchase_date");
        boolean aWarrantyExpiry = columnExists(con, "assets", "warranty_expiry");
        boolean aAssetStatus = columnExists(con, "assets", "asset_status");
        boolean aConditionStatus = columnExists(con, "assets", "condition_status");
        boolean aServiceStatus = columnExists(con, "assets", "service_status");
        boolean aLocationText = columnExists(con, "assets", "location");
        boolean aQrCode = columnExists(con, "assets", "qr_code");
        boolean aQrPublicToken = columnExists(con, "assets", "qr_public_token");
        boolean aRemarks = columnExists(con, "assets", "remarks");
        boolean aUpdatedAt = columnExists(con, "assets", "updated_at");
        boolean aCreatedAt = columnExists(con, "assets", "created_at");
        boolean aCategoryId = columnExists(con, "assets", "category_id");
        boolean aVendorId = columnExists(con, "assets", "vendor_id");
        boolean aDepartmentId = columnExists(con, "assets", "department_id");
        boolean aDivisionId = columnExists(con, "assets", "division_id");
        boolean aLocationId = columnExists(con, "assets", "location_id");

        boolean cCategoryId = hasCategories && columnExists(con, "asset_categories", "category_id");
        boolean cCategoryName = hasCategories && columnExists(con, "asset_categories", "category_name");

        boolean vVendorId = hasVendors && columnExists(con, "vendors", "vendor_id");
        boolean vVendorName = hasVendors && columnExists(con, "vendors", "vendor_name");
        boolean vSupplierName = hasVendors && columnExists(con, "vendors", "supplier_name");

        boolean dDepartmentId = hasDepartments && columnExists(con, "departments", "department_id");
        boolean dDepartmentName = hasDepartments && columnExists(con, "departments", "department_name");

        boolean rdDivisionId = hasDivisions && columnExists(con, "railway_divisions", "division_id");
        boolean rdDivisionName = hasDivisions && columnExists(con, "railway_divisions", "division_name");

        boolean rlLocationId = hasLocations && columnExists(con, "railway_locations", "location_id");
        boolean rlLocationName = hasLocations && columnExists(con, "railway_locations", "location_name");
        boolean rlLocationCode = hasLocations && columnExists(con, "railway_locations", "location_code");
        boolean rlLocationType = hasLocations && columnExists(con, "railway_locations", "location_type");

        boolean aaAllocationId = hasAllocation && columnExists(con, "asset_allocation", "allocation_id");
        boolean aaAssetId = hasAllocation && columnExists(con, "asset_allocation", "asset_id");
        boolean aaEmployeeId = hasAllocation && columnExists(con, "asset_allocation", "employee_id");
        boolean aaStatus = hasAllocation && columnExists(con, "asset_allocation", "allocation_status");
        boolean aaAllocationDate = hasAllocation && columnExists(con, "asset_allocation", "allocation_date");

        boolean eEmployeeId = hasEmployees && columnExists(con, "employees", "employee_id");
        boolean eFullName = hasEmployees && columnExists(con, "employees", "full_name");
        boolean eEmployeeName = hasEmployees && columnExists(con, "employees", "employee_name");
        boolean eEmployeeCode = hasEmployees && columnExists(con, "employees", "employee_code");
        boolean eDesignation = hasEmployees && columnExists(con, "employees", "designation");

        boolean arAssetId = hasReturns && columnExists(con, "asset_returns", "asset_id");
        boolean arReturnDate = hasReturns && columnExists(con, "asset_returns", "return_date");
        boolean arReturnCondition = hasReturns && columnExists(con, "asset_returns", "return_condition");

        boolean mlAssetId = hasMaintenance && columnExists(con, "maintenance_logs", "asset_id");
        boolean mlMaintenanceStatus = hasMaintenance && columnExists(con, "maintenance_logs", "maintenance_status");
        boolean mlMaintenanceType = hasMaintenance && columnExists(con, "maintenance_logs", "maintenance_type");
        boolean mlMaintenanceDate = hasMaintenance && columnExists(con, "maintenance_logs", "maintenance_date");

        boolean joinCategory = hasCategories && aCategoryId && cCategoryId;
        boolean joinVendor = hasVendors && aVendorId && vVendorId;
        boolean joinDepartment = hasDepartments && aDepartmentId && dDepartmentId;
        boolean joinDivision = hasDivisions && aDivisionId && rdDivisionId;
        boolean joinLocation = hasLocations && aLocationId && rlLocationId;
        boolean joinAllocation = hasAllocation && hasEmployees && aAssetId && aaAssetId && aaEmployeeId && eEmployeeId;
        boolean joinReturns = hasReturns && aAssetId && arAssetId;
        boolean joinMaintenance = hasMaintenance && aAssetId && mlAssetId;

        String assetIdExpr = aAssetId ? "CAST(a.asset_id AS CHAR)" : "''";
        String assetCodeExpr = aAssetCode
                ? "COALESCE(a.asset_code, '')"
                : (aRailwayAssetNo ? "COALESCE(a.railway_asset_no, '')" : "''");
        String assetNameExpr = aAssetName ? "COALESCE(a.asset_name, '')" : "''";
        String serialExpr = "''";
        String modelExpr = "''";
        String purchaseDateExpr = "''";
        String warrantyExpr = "''";
        String assetStatusExpr = aAssetStatus ? "COALESCE(a.asset_status, '')" : "''";
        String conditionExpr = aConditionStatus ? "COALESCE(a.condition_status, '')" : "''";
        String serviceExpr = aServiceStatus ? "COALESCE(a.service_status, '')" : "''";
        String locationTextExpr = aLocationText ? "COALESCE(a.location, '')" : "''";
        String qrCodeExpr = "''";
        String qrTokenExpr = "''";
        String remarksExpr = aRemarks ? "COALESCE(a.remarks, '')" : "''";

        String updatedExpr = "''";

        if (aUpdatedAt) {
            updatedExpr = "DATE_FORMAT(a.updated_at, '%d %b %Y, %h:%i %p')";
        } else if (aCreatedAt) {
            updatedExpr = "DATE_FORMAT(a.created_at, '%d %b %Y, %h:%i %p')";
        }

        String categoryExpr = joinCategory && cCategoryName ? "COALESCE(ac.category_name, 'Uncategorized')" : "'Uncategorized'";

        String vendorExpr = "'No Supplier'";

        if (joinVendor) {
            if (vVendorName) {
                vendorExpr = "COALESCE(v.vendor_name, 'No Supplier')";
            } else if (vSupplierName) {
                vendorExpr = "COALESCE(v.supplier_name, 'No Supplier')";
            }
        }

        String departmentExpr = joinDepartment && dDepartmentName ? "COALESCE(d.department_name, 'Unassigned')" : "'Unassigned'";
        String divisionExpr = joinDivision && rdDivisionName ? "COALESCE(rd.division_name, '')" : "''";

        String locationNameExpr = locationTextExpr;

        if (joinLocation && rlLocationName) {
            locationNameExpr = "COALESCE(rl.location_name, " + locationTextExpr + ", 'Not Mentioned')";
        } else if (aLocationText) {
            locationNameExpr = "COALESCE(a.location, 'Not Mentioned')";
        } else {
            locationNameExpr = "'Not Mentioned'";
        }

        String locationCodeExpr = joinLocation && rlLocationCode ? "COALESCE(rl.location_code, '')" : "''";
        String locationTypeExpr = joinLocation && rlLocationType ? "COALESCE(rl.location_type, '')" : "''";

        // Product decision: show the current holder's identity on this public page
        // (requested explicitly, overriding audit/08-qr-barcode.md Finding 1's
        // recommendation to redact it). fetchActiveAllocation() re-derives this from
        // the live tables after this query runs regardless, so these expressions are
        // mostly a fallback for when that later lookup finds nothing.
        String holderNameExpr = "''";

        if (joinAllocation) {
            if (eFullName) {
                holderNameExpr = "COALESCE(e.full_name, '')";
            } else if (eEmployeeName) {
                holderNameExpr = "COALESCE(e.employee_name, '')";
            }
        }

        String holderCodeExpr = joinAllocation && eEmployeeCode ? "COALESCE(e.employee_code, '')" : "''";
        String holderDesignationExpr = joinAllocation && eDesignation ? "COALESCE(e.designation, '')" : "''";
        String allocationDateExpr = joinAllocation && aaAllocationDate ? "DATE_FORMAT(aa.allocation_date, '%d %b %Y')" : "''";
        String returnStatusExpr = joinReturns ? "'Returned'" : "''";
        String returnDateExpr = joinReturns && arReturnDate ? "DATE_FORMAT(ar.return_date, '%d %b %Y')" : "''";
        String returnConditionExpr = joinReturns && arReturnCondition ? "COALESCE(ar.return_condition, '')" : "''";
        String maintenanceStatusExpr = joinMaintenance && mlMaintenanceStatus ? "COALESCE(ml.maintenance_status, '')" : "''";
        String maintenanceTypeExpr = joinMaintenance && mlMaintenanceType ? "COALESCE(ml.maintenance_type, '')" : "''";
        String maintenanceDateExpr = joinMaintenance && mlMaintenanceDate ? "DATE_FORMAT(ml.maintenance_date, '%d %b %Y')" : "''";

        StringBuilder sql = new StringBuilder();

        sql.append("SELECT ")
                .append(assetIdExpr).append(" AS asset_id, ")
                .append(assetCodeExpr).append(" AS asset_code, ")
                .append(assetNameExpr).append(" AS asset_name, ")
                .append(assetStatusExpr).append(" AS asset_status, ")
                .append(conditionExpr).append(" AS condition_status, ")
                .append(serviceExpr).append(" AS service_status, ")
                .append(categoryExpr).append(" AS category_name, ")
                .append(vendorExpr).append(" AS vendor_name, ")
                .append(departmentExpr).append(" AS department_name, ")
                .append(divisionExpr).append(" AS division_name, ")
                .append(locationNameExpr).append(" AS location_name, ")
                .append(locationCodeExpr).append(" AS location_code, ")
                .append(locationTypeExpr).append(" AS location_type, ")
                .append(holderNameExpr).append(" AS holder_name, ")
                .append(holderCodeExpr).append(" AS holder_code, ")
                .append(holderDesignationExpr).append(" AS holder_designation, ")
                .append(allocationDateExpr).append(" AS allocation_date, ")
                .append(returnStatusExpr).append(" AS return_status, ")
                .append(returnDateExpr).append(" AS return_date, ")
                .append(returnConditionExpr).append(" AS return_condition, ")
                .append(maintenanceStatusExpr).append(" AS maintenance_status, ")
                .append(maintenanceTypeExpr).append(" AS maintenance_type, ")
                .append(maintenanceDateExpr).append(" AS maintenance_date ")
                .append("FROM assets a ");

        if (joinCategory) {
            sql.append("LEFT JOIN asset_categories ac ON a.category_id = ac.category_id ");
        }

        if (joinVendor) {
            sql.append("LEFT JOIN vendors v ON a.vendor_id = v.vendor_id ");
        }

        if (joinDepartment) {
            sql.append("LEFT JOIN departments d ON a.department_id = d.department_id ");
        }

        if (joinDivision) {
            sql.append("LEFT JOIN railway_divisions rd ON a.division_id = rd.division_id ");
        }

        if (joinLocation) {
            sql.append("LEFT JOIN railway_locations rl ON a.location_id = rl.location_id ");
        }

        if (joinAllocation) {
            sql.append("LEFT JOIN asset_allocation aa ON aa.asset_id = a.asset_id AND aa.allocation_status = 'ALLOCATED' ")
               .append("LEFT JOIN employees e ON aa.employee_id = e.employee_id ");
        }

        if (joinReturns) {
            sql.append("LEFT JOIN asset_returns ar ON ar.asset_id = a.asset_id AND ar.return_date = (SELECT MAX(return_date) FROM asset_returns WHERE asset_id = a.asset_id) ");
        }

        if (joinMaintenance) {
            sql.append("LEFT JOIN maintenance_logs ml ON ml.asset_id = a.asset_id AND ml.maintenance_date = (SELECT MAX(maintenance_date) FROM maintenance_logs WHERE asset_id = a.asset_id) ");
        }

        List<String> whereParts = new ArrayList<String>();

        if (aQrPublicToken) {
            whereParts.add("TRIM(COALESCE(a.qr_public_token, '')) = ?");
        }

        if (whereParts.isEmpty()) {
            return row;
        }

        sql.append("WHERE ");

        for (int i = 0; i < whereParts.size(); i++) {
            if (i > 0) {
                sql.append(" OR ");
            }

            sql.append(whereParts.get(i));
        }

        if (joinAllocation && aaAllocationId) {
            sql.append(" ORDER BY aa.allocation_id DESC LIMIT 1");
        } else if (aAssetId) {
            sql.append(" ORDER BY a.asset_id DESC LIMIT 1");
        } else {
            sql.append(" LIMIT 1");
        }

        try (PreparedStatement ps = con.prepareStatement(sql.toString())) {
            int paramIndex = 1;

            if (aQrPublicToken) {
                ps.setString(paramIndex++, token);
            }

            try (ResultSet rs = ps.executeQuery()) {
                ResultSetMetaData meta = rs.getMetaData();
                int count = meta.getColumnCount();

                if (rs.next()) {
                    for (int i = 1; i <= count; i++) {
                        row.put(meta.getColumnLabel(i), rs.getString(i));
                    }
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return row;
    }

    private void logScan(Connection con, Map<String, String> asset, String token, HttpServletRequest request, String status, String remarks) {
        try {
            if (!tableExists(con, "asset_qr_scan_logs")) {
                return;
            }

            List<String> columns = new ArrayList<String>();
            List<Object> values = new ArrayList<Object>();

            String assetId = rowValue(asset, "asset_id");

            if (columnExists(con, "asset_qr_scan_logs", "asset_id")) {
                columns.add("asset_id");

                if (assetId == null || assetId.trim().isEmpty()) {
                    values.add(null);
                } else {
                    try {
                        values.add(Integer.parseInt(assetId.trim()));
                    } catch (Exception e) {
                        values.add(null);
                    }
                }
            }

            if (columnExists(con, "asset_qr_scan_logs", "qr_public_token")) {
                columns.add("qr_public_token");
                values.add(limitText(token, 100));
            } else if (columnExists(con, "asset_qr_scan_logs", "scan_token")) {
                columns.add("scan_token");
                values.add(limitText(token, 100));
            } else if (columnExists(con, "asset_qr_scan_logs", "token")) {
                columns.add("token");
                values.add(limitText(token, 100));
            }

            if (columnExists(con, "asset_qr_scan_logs", "scan_source")) {
                columns.add("scan_source");
                values.add("PUBLIC_SCAN");
            }

            if (columnExists(con, "asset_qr_scan_logs", "scan_ip")) {
                columns.add("scan_ip");
                values.add(limitText(clientIp(request), 60));
            } else if (columnExists(con, "asset_qr_scan_logs", "ip_address")) {
                columns.add("ip_address");
                values.add(limitText(clientIp(request), 60));
            }

            if (columnExists(con, "asset_qr_scan_logs", "scan_user_agent")) {
                columns.add("scan_user_agent");
                values.add(limitText(request.getHeader("User-Agent"), 255));
            } else if (columnExists(con, "asset_qr_scan_logs", "user_agent")) {
                columns.add("user_agent");
                values.add(limitText(request.getHeader("User-Agent"), 255));
            }

            if (columnExists(con, "asset_qr_scan_logs", "scan_status")) {
                columns.add("scan_status");
                values.add(limitText(status, 30));
            }

            if (columnExists(con, "asset_qr_scan_logs", "remarks")) {
                columns.add("remarks");
                values.add(limitText(remarks, 255));
            }

            String timeColumn = "";

            if (columnExists(con, "asset_qr_scan_logs", "scanned_at")) {
                timeColumn = "scanned_at";
            } else if (columnExists(con, "asset_qr_scan_logs", "scan_time")) {
                timeColumn = "scan_time";
            }

            if (!timeColumn.isEmpty()) {
                columns.add(timeColumn);
                values.add(new Timestamp(System.currentTimeMillis()));
            }

            if (columns.isEmpty()) {
                return;
            }

            StringBuilder sql = new StringBuilder();
            sql.append("INSERT INTO asset_qr_scan_logs (");

            for (int i = 0; i < columns.size(); i++) {
                if (i > 0) {
                    sql.append(", ");
                }

                sql.append(columns.get(i));
            }

            sql.append(") VALUES (");

            for (int i = 0; i < columns.size(); i++) {
                if (i > 0) {
                    sql.append(", ");
                }

                sql.append("?");
            }

            sql.append(")");

            try (PreparedStatement ps = con.prepareStatement(sql.toString())) {
                for (int i = 0; i < values.size(); i++) {
                    Object value = values.get(i);

                    if (value == null) {
                        ps.setNull(i + 1, Types.NULL);
                    } else if (value instanceof Integer) {
                        ps.setInt(i + 1, (Integer) value);
                    } else if (value instanceof Timestamp) {
                        ps.setTimestamp(i + 1, (Timestamp) value);
                    } else {
                        ps.setString(i + 1, String.valueOf(value));
                    }
                }

                ps.executeUpdate();
            }

        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private void fetchActiveAllocation(Connection con, Map<String, String> asset) {
        String assetId = asset.get("asset_id");
        if (assetId == null || assetId.trim().isEmpty()) {
            return;
        }

        if (!tableExists(con, "asset_allocation") || !tableExists(con, "employees")) {
            return;
        }

        String sql = "SELECT "
                + "COALESCE(e.employee_code, '') AS holder_code, "
                + "COALESCE(e.employee_name, '') AS holder_name, "
                + "COALESCE(e.designation, '') AS holder_designation, "
                + "DATE_FORMAT(aa.allocation_date, '%d %b %Y') AS allocation_date "
                + "FROM asset_allocation aa "
                + "LEFT JOIN employees e ON aa.employee_id = e.employee_id "
                + "WHERE aa.asset_id = ? AND aa.allocation_status = 'ALLOCATED' "
                + "ORDER BY aa.allocation_id DESC "
                + "LIMIT 1";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, assetId.trim());

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    asset.put("holder_code", rs.getString("holder_code"));
                    asset.put("holder_name", rs.getString("holder_name"));
                    asset.put("holder_designation", rs.getString("holder_designation"));
                    asset.put("allocation_date", rs.getString("allocation_date"));
                } else {
                    asset.put("holder_name", "");
                    asset.put("holder_code", "");
                    asset.put("holder_designation", "");
                    asset.put("allocation_date", "");
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    // Product decision (see the call site's comment): surfaces recent maintenance
    // history on this public page. Capped at 10 most-recent rows so a long-lived
    // asset doesn't produce an unbounded public page.
    private List<Map<String, String>> fetchMaintenanceHistory(Connection con, Map<String, String> asset) {
        List<Map<String, String>> history = new ArrayList<Map<String, String>>();
        String assetId = asset.get("asset_id");

        if (assetId == null || assetId.trim().isEmpty() || !tableExists(con, "maintenance_logs")) {
            return history;
        }

        String sql = "SELECT "
                + "COALESCE(maintenance_type, '') AS maintenance_type, "
                + "DATE_FORMAT(maintenance_date, '%d %b %Y') AS maintenance_date, "
                + "COALESCE(maintenance_status, '') AS maintenance_status, "
                + "COALESCE(work_done, '') AS work_done "
                + "FROM maintenance_logs "
                + "WHERE asset_id = ? "
                + "ORDER BY maintenance_date DESC, maintenance_id DESC "
                + "LIMIT 10";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, assetId.trim());

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, String> row = new HashMap<String, String>();
                    row.put("maintenance_type", rs.getString("maintenance_type"));
                    row.put("maintenance_date", rs.getString("maintenance_date"));
                    row.put("maintenance_status", rs.getString("maintenance_status"));
                    row.put("work_done", rs.getString("work_done"));
                    history.add(row);
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }

        return history;
    }

    // Product decision (see the call site's comment): surfaces recent physical
    // verification history on this public page. Reads the active
    // asset_physical_verification table; falls back to the legacy
    // physical_verification table if that one doesn't exist (schema-drift
    // defensive pattern used consistently across this codebase's other
    // verification-aware pages, e.g. global_search.jsp).
    private List<Map<String, String>> fetchVerificationHistory(Connection con, Map<String, String> asset) {
        List<Map<String, String>> history = new ArrayList<Map<String, String>>();
        String assetId = asset.get("asset_id");

        if (assetId == null || assetId.trim().isEmpty()) {
            return history;
        }

        String sql;

        if (tableExists(con, "asset_physical_verification")) {
            sql = "SELECT "
                    + "COALESCE(verified_status, '') AS verification_status, "
                    + "DATE_FORMAT(verified_on, '%d %b %Y') AS verification_date, "
                    + "COALESCE(review_status, '') AS review_status "
                    + "FROM asset_physical_verification "
                    + "WHERE asset_id = ? "
                    + "ORDER BY verified_on DESC, verification_id DESC "
                    + "LIMIT 10";
        } else if (tableExists(con, "physical_verification")) {
            sql = "SELECT "
                    + "COALESCE(verification_status, '') AS verification_status, "
                    + "DATE_FORMAT(verification_date, '%d %b %Y') AS verification_date, "
                    + "'' AS review_status "
                    + "FROM physical_verification "
                    + "WHERE asset_id = ? "
                    + "ORDER BY verification_date DESC, verification_id DESC "
                    + "LIMIT 10";
        } else {
            return history;
        }

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, assetId.trim());

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, String> row = new HashMap<String, String>();
                    row.put("verification_status", rs.getString("verification_status"));
                    row.put("verification_date", rs.getString("verification_date"));
                    row.put("review_status", rs.getString("review_status"));
                    history.add(row);
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }

        return history;
    }
%>

<%
    response.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
    response.setHeader("Pragma", "no-cache");
    response.setDateHeader("Expires", 0);

    String token = request.getParameter("token");

    if (token == null || token.trim().isEmpty()) {
        token = request.getParameter("qr");
    }

    if (token == null || token.trim().isEmpty()) {
        token = request.getParameter("code");
    }

    if (token == null) {
        token = "";
    }

    token = normalizeToken(token);

    Map<String, String> asset = new HashMap<String, String>();
    boolean validToken = false;
    List<Map<String, String>> maintenanceHistory = new ArrayList<Map<String, String>>();
    List<Map<String, String>> verificationHistory = new ArrayList<Map<String, String>>();

    try (Connection con = DBConnection.getConnection()) {
        if (!token.isEmpty()) {
            asset = getAssetSnapshotByToken(con, token);

            if (asset.isEmpty()) {
                asset = getAssetByAnyQrValue(con, token);
            }

            validToken = !asset.isEmpty();

            if (validToken) {
                // Product decision (overrides audit/08-qr-barcode.md Finding 1's
                // recommendation to redact holder identity on this public page):
                // populate the current holder's name/code/designation from the live
                // allocation/employee tables, and also pull maintenance/verification
                // history below, for display to anyone who scans this asset's tag.
                fetchActiveAllocation(con, asset);
                maintenanceHistory = fetchMaintenanceHistory(con, asset);
                verificationHistory = fetchVerificationHistory(con, asset);
                logScan(con, asset, token, request, "SUCCESS", "Public QR scan opened live asset view");
            } else {
                logScan(con, asset, token, request, "INVALID_TOKEN", "Invalid QR token: " + token);
            }
        }

    } catch (Exception e) {
        e.printStackTrace();
    }

    String assetStatus = rowValue(asset, "asset_status");
    String serviceStatus = rowValue(asset, "service_status");
    String conditionStatus = rowValue(asset, "condition_status");
    String verificationTime = nowText();

    String statusClass = "ok";

    if ("DAMAGED".equalsIgnoreCase(assetStatus)
            || "LOST".equalsIgnoreCase(assetStatus)
            || "DISPOSED".equalsIgnoreCase(assetStatus)
            || "UNSERVICEABLE".equalsIgnoreCase(serviceStatus)
            || "UNDER_REPAIR".equalsIgnoreCase(serviceStatus)) {
        statusClass = "danger";
    } else if ("UNDER_MAINTENANCE".equalsIgnoreCase(assetStatus)
            || "NEEDS_ATTENTION".equalsIgnoreCase(serviceStatus)
            || "NEEDS_REPAIR".equalsIgnoreCase(conditionStatus)) {
        statusClass = "warning";
    }
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Live Asset QR View - IR-AMS</title>

    <meta name="viewport" content="width=device-width, initial-scale=1.0">

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/public_asset_view.css?v=28001">
</head>

<body>
<div class="public-shell">
    <div class="public-card">
        <div class="public-header">
            <div class="rail-logo">
                <i class="fa-solid fa-train-subway"></i>
            </div>

            <div>
                <h1>IR-AMS Live Asset Verification</h1>
                <p>East Coast Railway · Indian Railways · Real-time QR based asset information</p>
            </div>
        </div>

        <div class="public-body">
            <% if (!validToken) { %>
                <div class="invalid-box">
                    <i class="fa-solid fa-circle-xmark"></i>
                    <h2>Invalid Asset QR</h2>
                    <p>
                        This QR token is missing, invalid, expired, or not linked with any live asset record.
                        Please contact the Asset Management System administrator.
                    </p>
                </div>
            <% } %>

            <% if (validToken) { %>

                <section class="asset-hero">
                    <div>
                        <h2><%= safeText(rowValue(asset, "asset_name")) %></h2>
                        <p>
                            <strong><%= safeText(rowValue(asset, "asset_code")) %></strong>
                        </p>
                    </div>

                    <div>
                        <span class="live-pill <%= safeText(statusClass) %>">
                            <i class="fa-solid fa-circle-check"></i>
                            Live Record
                        </span>
                    </div>
                </section>

                <section class="grid">
                    <div class="stat">
                        <span>Asset Status</span>
                        <strong><%= safeText(cleanLabel(rowValue(asset, "asset_status"))) %></strong>
                    </div>

                    <div class="stat">
                        <span>Condition</span>
                        <strong><%= safeText(cleanLabel(rowValue(asset, "condition_status"))) %></strong>
                    </div>

                    <div class="stat">
                        <span>Service Status</span>
                        <strong><%= safeText(cleanLabel(rowValue(asset, "service_status"))) %></strong>
                    </div>

                    <div class="stat">
                        <span>Verified At</span>
                        <strong><%= safeText(verificationTime) %></strong>
                    </div>
                </section>

                <section class="panel">
                    <h3>Asset Information</h3>

                    <table class="info-table">
                        <tr><th>Asset Code</th><td><%= safeText(rowValue(asset, "asset_code")) %></td></tr>
                        <tr><th>Asset Name</th><td><%= safeText(rowValue(asset, "asset_name")) %></td></tr>
                        <tr><th>Category</th><td><%= safeText(rowValue(asset, "category_name")) %></td></tr>
                        <tr><th>Department</th><td><%= safeText(rowValue(asset, "department_name")) %></td></tr>
                        <tr>
                            <th>Location</th>
                            <td>
                                <%= safeText(rowValue(asset, "location_name")) %>
                                <% if (!rowValue(asset, "location_code").trim().isEmpty()) { %>
                                    · <%= safeText(rowValue(asset, "location_code")) %>
                                <% } %>
                            </td>
                        </tr>
                    </table>
                </section>

                <section class="panel">
                    <h3>Current Allotted Employee / Holder</h3>
                    <% if (!rowValue(asset, "holder_name").isEmpty()) { %>
                    <table class="info-table">
                        <tr><th>Employee Name</th><td><%= safeText(rowValue(asset, "holder_name")) %></td></tr>
                        <tr><th>Employee Code</th><td><%= safeText(rowValue(asset, "holder_code")) %></td></tr>
                        <tr><th>Designation</th><td><%= safeText(rowValue(asset, "holder_designation")) %></td></tr>
                        <tr><th>Allocation Date</th><td><%= safeText(rowValue(asset, "allocation_date")) %></td></tr>
                    </table>
                    <% } else { %>
                    <p style="padding: 15px; color: #666; font-style: italic;">No active holder. This asset is not currently allocated.</p>
                    <% } %>
                </section>

                <% if (!rowValue(asset, "return_status").isEmpty()) { %>
                <section class="panel">
                    <h3>Return Status</h3>
                    <table class="info-table">
                        <tr><th>Status</th><td><%= safeText(rowValue(asset, "return_status")) %></td></tr>
                        <% if (!rowValue(asset, "return_date").isEmpty()) { %>
                        <tr><th>Return Date</th><td><%= safeText(rowValue(asset, "return_date")) %></td></tr>
                        <% } %>
                        <% if (!rowValue(asset, "return_condition").isEmpty()) { %>
                        <tr><th>Return Condition</th><td><%= safeText(cleanLabel(rowValue(asset, "return_condition"))) %></td></tr>
                        <% } %>
                    </table>
                </section>
                <% } %>

                <% if (!rowValue(asset, "maintenance_status").isEmpty() || "UNDER_MAINTENANCE".equalsIgnoreCase(assetStatus) || "NEEDS_ATTENTION".equalsIgnoreCase(serviceStatus) || "NEEDS_REPAIR".equalsIgnoreCase(conditionStatus)) { %>
                <section class="panel">
                    <h3>Maintenance Status</h3>
                    <table class="info-table">
                        <tr><th>Status</th><td><%= !rowValue(asset, "maintenance_status").isEmpty() ? safeText(cleanLabel(rowValue(asset, "maintenance_status"))) : "Maintenance Applicable" %></td></tr>
                        <% if (!rowValue(asset, "maintenance_type").isEmpty()) { %>
                        <tr><th>Type</th><td><%= safeText(cleanLabel(rowValue(asset, "maintenance_type"))) %></td></tr>
                        <% } %>
                        <% if (!rowValue(asset, "maintenance_date").isEmpty()) { %>
                        <tr><th>Date</th><td><%= safeText(rowValue(asset, "maintenance_date")) %></td></tr>
                        <% } %>
                    </table>
                </section>
            <% } %>

            <% if (!maintenanceHistory.isEmpty()) { %>
                <section class="panel">
                    <h3>Maintenance History</h3>
                    <table class="info-table">
                        <tr><th>Date</th><th>Type</th><th>Status</th><th>Work Done</th></tr>
                        <% for (Map<String, String> m : maintenanceHistory) { %>
                        <tr>
                            <td><%= safeText(rowValue(m, "maintenance_date")) %></td>
                            <td><%= safeText(cleanLabel(rowValue(m, "maintenance_type"))) %></td>
                            <td><%= safeText(cleanLabel(rowValue(m, "maintenance_status"))) %></td>
                            <td><%= safeText(rowValue(m, "work_done")) %></td>
                        </tr>
                        <% } %>
                    </table>
                </section>
            <% } %>

            <% if (!verificationHistory.isEmpty()) { %>
                <section class="panel">
                    <h3>Physical Verification History</h3>
                    <table class="info-table">
                        <tr><th>Date</th><th>Status</th><th>Review Status</th></tr>
                        <% for (Map<String, String> v : verificationHistory) { %>
                        <tr>
                            <td><%= safeText(rowValue(v, "verification_date")) %></td>
                            <td><%= safeText(cleanLabel(rowValue(v, "verification_status"))) %></td>
                            <td><%= safeText(cleanLabel(rowValue(v, "review_status"))) %></td>
                        </tr>
                        <% } %>
                    </table>
                </section>
            <% } %>

            <% } %>
        </div>

        <div class="footer-note">
            This public page displays safe live details from Railway Asset Management System. If the asset record is
            updated later, the same printed QR code will show the latest permitted database information automatically.
        </div>
    </div>
</div>
</body>
</html>-
