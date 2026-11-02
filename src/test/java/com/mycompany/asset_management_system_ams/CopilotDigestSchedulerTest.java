package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.List;

import jakarta.servlet.ServletContext;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.MockedStatic;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.mockStatic;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * CopilotDigestSchedulerTest — the Copilot's one proactive behaviour, tested
 * with NotificationHelper itself mocked out in every single test. That is
 * deliberate and load-bearing: this suite must be safe to run against ANY
 * environment, including one with real SMTP configured and real recipient
 * emails on file (confirmed true for the local dev DB this was built
 * against) - no test here may ever risk a real send. The underlying queries
 * were additionally verified once, by hand, directly against a real local
 * MySQL instance (read-only SELECTs only, no risk) while building this
 * feature; this suite is what guards them in CI afterwards.
 */
public class CopilotDigestSchedulerTest {

    // ─────────────────────────────────────────────────────────────────────
    // Gating - must never touch the DB, let alone send, when disabled
    // ─────────────────────────────────────────────────────────────────────

    @Test
    public void testRunCheckSkipsEverythingWhenSmtpDisabled() {
        try (MockedStatic<SettingsDAO> settings = mockStatic(SettingsDAO.class);
             MockedStatic<DBConnection> db = mockStatic(DBConnection.class);
             MockedStatic<NotificationHelper> notify = mockStatic(NotificationHelper.class)) {

            settings.when(SettingsDAO::isSmtpEnabled).thenReturn(false);

            CopilotDigestScheduler.runCheck(mock(ServletContext.class));

            db.verifyNoInteractions();
            notify.verify(() -> NotificationHelper.sendNotification(
                    any(), anyString(), anyString(), any(), anyString(), anyString(), anyString(), anyString(), anyString()),
                    times(0));
        }
    }

    @Test
    public void testRunCheckSkipsEverythingWhenDigestAlertsDisabled() {
        try (MockedStatic<SettingsDAO> settings = mockStatic(SettingsDAO.class);
             MockedStatic<DBConnection> db = mockStatic(DBConnection.class);
             MockedStatic<NotificationHelper> notify = mockStatic(NotificationHelper.class)) {

            settings.when(SettingsDAO::isSmtpEnabled).thenReturn(true);
            notify.when(() -> NotificationHelper.isAlertSettingEnabled("copilot_digest_alerts", true))
                    .thenReturn(false);

            CopilotDigestScheduler.runCheck(mock(ServletContext.class));

            db.verifyNoInteractions();
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Dedup
    // ─────────────────────────────────────────────────────────────────────

    @Test
    public void testAlreadySentRecentlyReadsNotificationLogs() throws Exception {
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);
        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(true);
        when(rs.getInt(1)).thenReturn(1);

        try (MockedStatic<DBConnection> db = mockStatic(DBConnection.class)) {
            db.when(DBConnection::getConnection).thenReturn(con);

            assertTrue(CopilotDigestScheduler.alreadySentRecently());

            ArgumentCaptor<String> sqlCaptor = ArgumentCaptor.forClass(String.class);
            verify(con).prepareStatement(sqlCaptor.capture());
            assertTrue(sqlCaptor.getValue().toUpperCase(java.util.Locale.ENGLISH).contains("NOTIFICATION_LOGS"));
        }
    }

    @Test
    public void testAlreadySentRecentlyDegradesToFalseOnDbFailure() {
        // A dedup check that can't run must send anyway, not silently go dark
        // on a real backlog just because the check itself failed.
        try (MockedStatic<DBConnection> db = mockStatic(DBConnection.class)) {
            db.when(DBConnection::getConnection).thenThrow(new RuntimeException("down"));

            assertFalse(CopilotDigestScheduler.alreadySentRecently());
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Query -> PendingItem mapping
    // ─────────────────────────────────────────────────────────────────────

    @Test
    public void testFindPendingAssetRequestsMapsRowsCorrectly() throws Exception {
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);
        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(true, false);
        when(rs.getInt("request_id")).thenReturn(42);
        when(rs.getString("priority")).thenReturn("HIGH");
        when(rs.getString("employee_name")).thenReturn("Priya Sharma");
        when(rs.getString("employee_code")).thenReturn("EMP004");
        when(rs.getString("category_name")).thenReturn("Laptop");
        when(rs.getInt("days_pending")).thenReturn(5);

        try (MockedStatic<DBConnection> db = mockStatic(DBConnection.class)) {
            db.when(DBConnection::getConnection).thenReturn(con);

            List<CopilotDigestScheduler.PendingItem> items = CopilotDigestScheduler.findPendingAssetRequests(3);

            assertEquals(1, items.size());
            assertEquals("Request #42", items.get(0).label);
            assertTrue(items.get(0).detail.contains("Laptop"));
            assertTrue(items.get(0).detail.contains("Priya Sharma"));
            assertTrue(items.get(0).detail.contains("EMP004"));
            assertTrue(items.get(0).detail.contains("HIGH"));
            assertTrue(items.get(0).detail.contains("5 days"));
            assertEquals(5, items.get(0).daysPending);
        }
    }

    @Test
    public void testFindPendingAssetRequestsDegradesToEmptyOnDbFailure() {
        try (MockedStatic<DBConnection> db = mockStatic(DBConnection.class)) {
            db.when(DBConnection::getConnection).thenThrow(new RuntimeException("down"));

            assertTrue(CopilotDigestScheduler.findPendingAssetRequests(3).isEmpty());
        }
    }

    @Test
    public void testFindPendingMaintenanceRequestsMapsRowsCorrectly() throws Exception {
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);
        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(true, false);
        when(rs.getInt("request_id")).thenReturn(7);
        when(rs.getString("issue_description")).thenReturn("Screen flickering");
        when(rs.getString("asset_code")).thenReturn("AST010");
        when(rs.getString("asset_name")).thenReturn("Dell Laptop");
        when(rs.getInt("days_pending")).thenReturn(4);

        try (MockedStatic<DBConnection> db = mockStatic(DBConnection.class)) {
            db.when(DBConnection::getConnection).thenReturn(con);

            List<CopilotDigestScheduler.PendingItem> items = CopilotDigestScheduler.findPendingMaintenanceRequests(3);

            assertEquals(1, items.size());
            assertEquals("Maintenance #7", items.get(0).label);
            assertTrue(items.get(0).detail.contains("AST010"));
            assertTrue(items.get(0).detail.contains("Screen flickering"));
            assertTrue(items.get(0).detail.contains("4 days"));
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Email content - the escaping matters since these fields are free text
    // (issue descriptions, employee/category names) embedded into an HTML
    // email body.
    // ─────────────────────────────────────────────────────────────────────

    @Test
    public void testSendDigestEscapesHtmlInFreeTextFields() {
        List<CopilotDigestScheduler.PendingItem> maliciousRequest = List.of(
                new CopilotDigestScheduler.PendingItem(
                        "Request #1", "<script>alert(1)</script> requested by <b>Someone</b>", 5));

        // Built BEFORE NotificationEventService is statically mocked below -
        // its own constructor calls NotificationEventService.safe()
        // internally, which a static mock of the whole class would otherwise
        // intercept too (Mockito's strict-stubbing check then flags that as
        // an unstubbed call rather than letting the real method run).
        NotificationEventService.EmailRouting routing =
                new NotificationEventService.EmailRouting("manager@example.com", "admin@example.com");

        try (MockedStatic<NotificationHelper> notify = mockStatic(NotificationHelper.class);
             MockedStatic<NotificationEventService> events = mockStatic(NotificationEventService.class)) {

            events.when(() -> NotificationEventService.buildMasterDataRecipients("ADDED"))
                    .thenReturn(routing);
            notify.when(() -> NotificationHelper.buildHtmlEmail(anyString(), anyString(), anyString(), anyString()))
                    .thenReturn("<html>fake</html>");

            CopilotDigestScheduler.sendDigest(mock(ServletContext.class), 3, maliciousRequest, List.of(), List.of());

            ArgumentCaptor<String> detailsHtmlCaptor = ArgumentCaptor.forClass(String.class);
            notify.verify(() -> NotificationHelper.buildHtmlEmail(
                    anyString(), anyString(), detailsHtmlCaptor.capture(), anyString()));

            String detailsHtml = detailsHtmlCaptor.getValue();
            assertFalse(detailsHtml.contains("<script>"), "Raw <script> must never reach the email HTML: " + detailsHtml);
            assertTrue(detailsHtml.contains("&lt;script&gt;"), "Expected the tag escaped instead: " + detailsHtml);

            notify.verify(() -> NotificationHelper.sendNotification(
                    any(), eq("COPILOT_DIGEST"), eq(NotificationHelper.MODULE_COPILOT_DIGEST),
                    eq(0), eq("manager@example.com"), eq("admin@example.com"), eq(""), anyString(), eq("<html>fake</html>")));
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Full runCheck() orchestration, with the DB and NotificationHelper both
    // mocked - the "nothing to report" branch must never call sendDigest()
    // (proven by NotificationHelper.sendNotification() never firing), and a
    // real backlog must.
    // ─────────────────────────────────────────────────────────────────────

    @Test
    public void testRunCheckSendsNothingWhenAllThreeListsAreEmpty() throws Exception {
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet emptyResultSet = mock(ResultSet.class);
        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(emptyResultSet);
        // Every query (dedup + both find* + the cost-outlier insight) comes
        // back empty/zero.
        when(emptyResultSet.next()).thenReturn(false);
        when(emptyResultSet.getInt(1)).thenReturn(0);

        try (MockedStatic<SettingsDAO> settings = mockStatic(SettingsDAO.class);
             MockedStatic<DBConnection> db = mockStatic(DBConnection.class);
             MockedStatic<NotificationHelper> notify = mockStatic(NotificationHelper.class)) {

            settings.when(SettingsDAO::isSmtpEnabled).thenReturn(true);
            settings.when(SettingsDAO::getCopilotDigestAgingDays).thenReturn(3);
            notify.when(() -> NotificationHelper.isAlertSettingEnabled("copilot_digest_alerts", true))
                    .thenReturn(true);
            db.when(DBConnection::getConnection).thenReturn(con);

            CopilotDigestScheduler.runCheck(mock(ServletContext.class));

            notify.verify(() -> NotificationHelper.sendNotification(
                    any(), anyString(), anyString(), any(), anyString(), anyString(), anyString(), anyString(), anyString()),
                    times(0));
        }
    }

    @Test
    public void testRunCheckSendsWhenOnlyCostOutliersAreNonEmpty() throws Exception {
        // Both aging lists (asset requests, maintenance requests) come back
        // empty; only the cost-outlier insight has something to report. The
        // digest must still fire - proactively surfacing an insight nobody
        // asked for is exactly this feature's point, and it must not be
        // gated behind also having an aging backlog.
        Connection con = mock(Connection.class);
        PreparedStatement genericPs = mock(PreparedStatement.class);
        ResultSet emptyResultSet = mock(ResultSet.class);
        when(emptyResultSet.next()).thenReturn(false);
        when(emptyResultSet.getInt(1)).thenReturn(0);
        when(con.prepareStatement(anyString())).thenReturn(genericPs);
        when(genericPs.executeQuery()).thenReturn(emptyResultSet);

        PreparedStatement outlierPs = mock(PreparedStatement.class);
        ResultSet outlierRs = mock(ResultSet.class);
        when(outlierRs.next()).thenReturn(true, false);
        when(outlierRs.getString("asset_code")).thenReturn("AST006");
        when(outlierRs.getString("asset_name")).thenReturn("Canon Multifunction Printer");
        when(outlierRs.getString("category_name")).thenReturn("Printer & Scanner");
        when(outlierRs.getString("total_cost")).thenReturn("6500.00");
        when(outlierRs.getString("avg_cost")).thenReturn("3250.00");
        when(outlierRs.getDouble("cost_ratio")).thenReturn(2.0);
        when(outlierPs.executeQuery()).thenReturn(outlierRs);
        // Registered AFTER the generic anyString() stub so this more
        // specific matcher takes precedence for that one query only. Must be
        // unique to queryMaintenanceCostOutliers()'s own SQL - "asset_categories"
        // looked unique at first but findPendingAssetRequests() ALSO joins
        // that table, which silently stole this outlier ResultSet's
        // sequenced next()=true/false answer before the real outlier query
        // ever ran (confirmed live: this test failed until switching to a
        // substring - "cost_ratio" - that only the outlier query's SQL has).
        when(con.prepareStatement(org.mockito.ArgumentMatchers.contains("cost_ratio"))).thenReturn(outlierPs);

        // Built BEFORE NotificationEventService is statically mocked below -
        // see testSendDigestEscapesHtmlInFreeTextFields's own comment on
        // exactly this ordering requirement.
        NotificationEventService.EmailRouting routing =
                new NotificationEventService.EmailRouting("manager@example.com", "admin@example.com");

        try (MockedStatic<SettingsDAO> settings = mockStatic(SettingsDAO.class);
             MockedStatic<DBConnection> db = mockStatic(DBConnection.class);
             MockedStatic<NotificationHelper> notify = mockStatic(NotificationHelper.class);
             MockedStatic<NotificationEventService> events = mockStatic(NotificationEventService.class)) {

            settings.when(SettingsDAO::isSmtpEnabled).thenReturn(true);
            settings.when(SettingsDAO::getCopilotDigestAgingDays).thenReturn(3);
            notify.when(() -> NotificationHelper.isAlertSettingEnabled("copilot_digest_alerts", true))
                    .thenReturn(true);
            notify.when(() -> NotificationHelper.buildHtmlEmail(anyString(), anyString(), anyString(), anyString()))
                    .thenReturn("<html>fake</html>");
            db.when(DBConnection::getConnection).thenReturn(con);
            events.when(() -> NotificationEventService.buildMasterDataRecipients("ADDED"))
                    .thenReturn(routing);

            CopilotDigestScheduler.runCheck(mock(ServletContext.class));

            ArgumentCaptor<String> detailsHtmlCaptor = ArgumentCaptor.forClass(String.class);
            notify.verify(() -> NotificationHelper.buildHtmlEmail(
                    anyString(), anyString(), detailsHtmlCaptor.capture(), anyString()));
            assertTrue(detailsHtmlCaptor.getValue().contains("AST006"),
                    "Expected the cost outlier to appear in the digest body: " + detailsHtmlCaptor.getValue());

            notify.verify(() -> NotificationHelper.sendNotification(
                    any(), anyString(), anyString(), any(), anyString(), anyString(), anyString(), anyString(), anyString()),
                    times(1));
        }
    }
}
