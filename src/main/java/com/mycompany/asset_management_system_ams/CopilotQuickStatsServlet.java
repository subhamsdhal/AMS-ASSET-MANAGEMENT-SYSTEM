package com.mycompany.asset_management_system_ams;

import jakarta.servlet.RequestDispatcher;
import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * CopilotQuickStatsServlet — a deliberately AI-free, direct-SQL "how many
 * records were added today/yesterday/this month/last month" grid, covering
 * every major module.
 *
 * Exists specifically as a presentation safety net: added because the AI
 * Copilot's answer time depends on external providers (Groq/Gemini/NVIDIA)
 * that can be rate-limited or slow, and a live demo cannot wait on that.
 * This page runs a handful of COUNT queries directly against the database -
 * no LLM call anywhere in the path - so it is fast and reliable regardless
 * of what the AI providers are doing at that moment.
 *
 * "Added" means created_at (when the row was actually entered into AMS),
 * the same convention CopilotToolExecutor already uses for every module's
 * "added"/"joined" tool (see e.g. searchAssets(), searchEmployees(),
 * getEmployeesByJoiningDate()) - not a business date like allocation_date
 * or request_date, which answer a different question.
 */
@WebServlet(name = "CopilotQuickStatsServlet", urlPatterns = {"/CopilotQuickStatsServlet"})
public class CopilotQuickStatsServlet extends HttpServlet {

    private static final Logger LOGGER = Logger.getLogger(CopilotQuickStatsServlet.class.getName());

    /** One row of the grid: a module name paired with the table/column it counts. */
    private static final class Module {
        final String label;
        final String table;
        final String dateColumn;

        Module(String label, String table, String dateColumn) {
            this.label = label;
            this.table = table;
            this.dateColumn = dateColumn;
        }
    }

    private static final List<Module> MODULES = List.of(
            new Module("Assets",                "assets",                        "created_at"),
            new Module("Employees",              "employees",                     "created_at"),
            new Module("Allocations",            "asset_allocation",              "created_at"),
            new Module("Returns",                "asset_returns",                 "created_at"),
            new Module("Maintenance Requests",   "maintenance_requests",          "created_at"),
            new Module("Asset Requests",         "asset_requests",                "created_at"),
            new Module("Physical Verifications", "asset_physical_verification",   "created_at")
    );

    public static final class ModuleStats {
        public final String label;
        public final long today;
        public final long yesterday;
        public final long thisMonth;
        public final long lastMonth;
        public final String error;

        ModuleStats(String label, long today, long yesterday, long thisMonth, long lastMonth) {
            this.label = label;
            this.today = today;
            this.yesterday = yesterday;
            this.thisMonth = thisMonth;
            this.lastMonth = lastMonth;
            this.error = null;
        }

        ModuleStats(String label, String error) {
            this.label = label;
            this.today = 0;
            this.yesterday = 0;
            this.thisMonth = 0;
            this.lastMonth = 0;
            this.error = error;
        }
    }

    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        HttpSession session = request.getSession(false);
        String username = session == null ? null : (String) session.getAttribute("username");
        if (username == null) {
            response.sendRedirect("login.jsp");
            return;
        }

        List<ModuleStats> stats = new ArrayList<>();
        long startNanos = System.nanoTime();

        try (Connection conn = DBConnection.getConnection()) {
            for (Module m : MODULES) {
                stats.add(queryModule(conn, m));
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "CopilotQuickStatsServlet: connection failure", e);
            // Fail closed with per-module error rows rather than a blank
            // page - this page exists specifically to be reliable when
            // other things are not, so it should degrade gracefully too.
            Map<String, String> already = new LinkedHashMap<>();
            for (Module m : MODULES) {
                if (already.putIfAbsent(m.label, "ok") == null) {
                    stats.add(new ModuleStats(m.label, "Database unavailable"));
                }
            }
        }

        long elapsedMs = (System.nanoTime() - startNanos) / 1_000_000;

        request.setAttribute("stats", stats);
        request.setAttribute("generatedAtMs", System.currentTimeMillis());
        request.setAttribute("elapsedMs", elapsedMs);

        RequestDispatcher dispatcher = request.getRequestDispatcher("copilot_quick_stats.jsp");
        dispatcher.forward(request, response);
    }

    /**
     * One query per module via conditional aggregation - a single pass over
     * the table's index on the date column returns all four periods at
     * once, rather than four separate COUNT(*) queries per module.
     */
    private ModuleStats queryModule(Connection conn, Module m) {
        String sql =
                "SELECT " +
                "SUM(CASE WHEN DATE(" + m.dateColumn + ") = CURDATE() THEN 1 ELSE 0 END) AS c_today, " +
                "SUM(CASE WHEN DATE(" + m.dateColumn + ") = CURDATE() - INTERVAL 1 DAY THEN 1 ELSE 0 END) AS c_yesterday, " +
                "SUM(CASE WHEN YEAR(" + m.dateColumn + ") = YEAR(CURDATE()) " +
                "     AND MONTH(" + m.dateColumn + ") = MONTH(CURDATE()) THEN 1 ELSE 0 END) AS c_this_month, " +
                "SUM(CASE WHEN YEAR(" + m.dateColumn + ") = YEAR(CURDATE() - INTERVAL 1 MONTH) " +
                "     AND MONTH(" + m.dateColumn + ") = MONTH(CURDATE() - INTERVAL 1 MONTH) THEN 1 ELSE 0 END) AS c_last_month " +
                "FROM " + m.table + " WHERE " + m.dateColumn + " IS NOT NULL";
        // Table/column names are baked in from the fixed MODULES list above,
        // never from user input, so string-building the SQL here (rather
        // than a PreparedStatement, which cannot parameterize identifiers)
        // does not open an injection path.

        try (PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            if (rs.next()) {
                return new ModuleStats(m.label,
                        rs.getLong("c_today"),
                        rs.getLong("c_yesterday"),
                        rs.getLong("c_this_month"),
                        rs.getLong("c_last_month"));
            }
            return new ModuleStats(m.label, 0, 0, 0, 0);
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "CopilotQuickStatsServlet: query failed for " + m.table, e);
            return new ModuleStats(m.label, "Query failed");
        }
    }
}
