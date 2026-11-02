package com.mycompany.asset_management_system_ams;

import java.util.List;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * CopilotKnowledgeBaseTest — the "how IR-AMS actually works" search that
 * lets the Copilot answer conceptual questions grounded in this system's
 * REAL, code-verified behavior instead of the model's own general knowledge
 * of how such systems typically work (which would get several of this
 * system's actual rules wrong - see CopilotKnowledgeBase's own class doc
 * for concrete examples). Locks in that the handful of curated topics rank
 * sensibly for the phrasing a real question would use, and that a genuinely
 * unrelated query returns nothing rather than a weak, misleading match.
 */
public class CopilotKnowledgeBaseTest {

    @Test
    public void testAssetRequestApprovalQuestionMatchesTheRequestLifecycleTopic() {
        List<CopilotKnowledgeBase.Topic> results = CopilotKnowledgeBase.search(
                "how does asset request approval work");
        assertTrue(results.size() > 0, "Expected at least one match.");
        assertEquals("asset_request_lifecycle", results.get(0).id);
    }

    @Test
    public void testDepartmentHeadPermissionQuestionMatchesRbacTopic() {
        List<CopilotKnowledgeBase.Topic> results = CopilotKnowledgeBase.search(
                "what can a department head do");
        assertTrue(results.size() > 0);
        assertEquals("rbac_roles", results.get(0).id);
    }

    @Test
    public void testDamagedAssetQuestionMatchesStatusLifecycleTopic() {
        List<CopilotKnowledgeBase.Topic> results = CopilotKnowledgeBase.search(
                "what happens when an asset is marked damaged");
        assertTrue(results.size() > 0);
        assertEquals("asset_status_lifecycle", results.get(0).id);
    }

    @Test
    public void testQrTaggingQuestionMatchesQrTopic() {
        List<CopilotKnowledgeBase.Topic> results = CopilotKnowledgeBase.search("qr tagging pending meaning");
        assertTrue(results.size() > 0);
        assertEquals("qr_control_center", results.get(0).id);
    }

    @Test
    public void testCopilotSelfCapabilityQuestionMatchesCopilotTopic() {
        List<CopilotKnowledgeBase.Topic> results = CopilotKnowledgeBase.search("what can the copilot do");
        assertTrue(results.size() > 0);
        assertEquals("copilot_capabilities", results.get(0).id);
    }

    @Test
    public void testWarrantyRenewalQuestionMatchesWarrantyTopic() {
        List<CopilotKnowledgeBase.Topic> results = CopilotKnowledgeBase.search(
                "how do I renew an asset's warranty");
        assertTrue(results.size() > 0);
        assertEquals("warranty_tracking", results.get(0).id);
    }

    @Test
    public void testHealthScoreQuestionMatchesHealthTopic() {
        List<CopilotKnowledgeBase.Topic> results = CopilotKnowledgeBase.search(
                "how is the asset health score calculated");
        assertTrue(results.size() > 0);
        assertEquals("asset_health_score", results.get(0).id);
    }

    @Test
    public void testVendorMappingQuestionMatchesVendorTopic() {
        List<CopilotKnowledgeBase.Topic> results = CopilotKnowledgeBase.search(
                "can any vendor supply any category of asset");
        assertTrue(results.size() > 0);
        assertEquals("vendor_category_management", results.get(0).id);
    }

    @Test
    public void testBackupScheduleQuestionMatchesBackupTopic() {
        List<CopilotKnowledgeBase.Topic> results = CopilotKnowledgeBase.search(
                "does the system take automatic scheduled backups");
        assertTrue(results.size() > 0);
        assertEquals("backup_restore", results.get(0).id);
    }

    @Test
    public void testAuditTrailQuestionMatchesReportsAuditTopic() {
        List<CopilotKnowledgeBase.Topic> results = CopilotKnowledgeBase.search(
                "does every action show up in the audit log");
        assertTrue(results.size() > 0);
        assertEquals("reports_and_audit", results.get(0).id);
    }

    @Test
    public void testRoleAssignmentQuestionMatchesRoleDutyTopic() {
        List<CopilotKnowledgeBase.Topic> results = CopilotKnowledgeBase.search(
                "who can assign a department head duty to an employee");
        assertTrue(results.size() > 0);
        assertEquals("role_duty_assignment", results.get(0).id);
    }

    @Test
    public void testDeleteDepartmentQuestionMatchesDepartmentTopic() {
        List<CopilotKnowledgeBase.Topic> results = CopilotKnowledgeBase.search(
                "can I delete a department that still has employees in it");
        assertTrue(results.size() > 0);
        assertEquals("departments_management", results.get(0).id);
    }

    @Test
    public void testDeleteCategoryQuestionMatchesCategoryTopic() {
        List<CopilotKnowledgeBase.Topic> results = CopilotKnowledgeBase.search(
                "how do I delete an asset category");
        assertTrue(results.size() > 0);
        assertEquals("categories_management", results.get(0).id);
    }

    @Test
    public void testDocumentUploadSizeQuestionMatchesDocumentTopic() {
        List<CopilotKnowledgeBase.Topic> results = CopilotKnowledgeBase.search(
                "what is the file size limit for uploading an employee document");
        assertTrue(results.size() > 0);
        assertEquals("document_uploads", results.get(0).id);
    }

    @Test
    public void testEmailAlertsMasterSwitchQuestionMatchesNotificationTopic() {
        List<CopilotKnowledgeBase.Topic> results = CopilotKnowledgeBase.search(
                "if I turn off email alerts does that disable warranty alerts too");
        assertTrue(results.size() > 0);
        assertEquals("notification_system", results.get(0).id);
    }

    @Test
    public void testSettingsAccessQuestionMatchesSettingsTopic() {
        List<CopilotKnowledgeBase.Topic> results = CopilotKnowledgeBase.search(
                "which roles can open the settings page");
        assertTrue(results.size() > 0);
        assertEquals("settings_overview", results.get(0).id);
    }

    @Test
    public void testMaintenanceRequestApprovalQuestionMatchesMaintenanceWorkflowTopic() {
        List<CopilotKnowledgeBase.Topic> results = CopilotKnowledgeBase.search(
                "can an employee file their own maintenance request");
        assertTrue(results.size() > 0);
        assertEquals("maintenance_workflow", results.get(0).id);
    }

    @Test
    public void testUndoDisposalQuestionMatchesDisposalTopic() {
        List<CopilotKnowledgeBase.Topic> results = CopilotKnowledgeBase.search(
                "can I undo an asset disposal once it's done");
        assertTrue(results.size() > 0);
        assertEquals("asset_disposal", results.get(0).id);
    }

    @Test
    public void testEmployeeTransferQuestionMatchesTransferTopic() {
        List<CopilotKnowledgeBase.Topic> results = CopilotKnowledgeBase.search(
                "can an employee submit their own transfer preference for an allocated asset");
        assertTrue(results.size() > 0);
        assertEquals("employee_transfer", results.get(0).id);
    }

    @Test
    public void testForgotPasswordQuestionMatchesPasswordRecoveryTopic() {
        List<CopilotKnowledgeBase.Topic> results = CopilotKnowledgeBase.search(
                "I forgot my password how do I reset it");
        assertTrue(results.size() > 0);
        assertEquals("password_reset_recovery", results.get(0).id);
    }

    @Test
    public void testManageRolesVsDutyAssignmentQuestionMatchesTheDistinctionTopic() {
        List<CopilotKnowledgeBase.Topic> results = CopilotKnowledgeBase.search(
                "does assigning a duty on role and duty assignment actually change what someone can access");
        assertTrue(results.size() > 0);
        assertEquals("role_assignment_vs_role_editing", results.get(0).id);
    }

    @Test
    public void testCurrencySettingQuestionMatchesCurrencyTopic() {
        List<CopilotKnowledgeBase.Topic> results = CopilotKnowledgeBase.search(
                "if I change the currency setting will prices show differently everywhere");
        assertTrue(results.size() > 0);
        assertEquals("currency_settings", results.get(0).id);
    }

    @Test
    public void testOverdueReturnsQuestionMatchesAlertCenterTopic() {
        List<CopilotKnowledgeBase.Topic> results = CopilotKnowledgeBase.search(
                "what is the difference between overdue actions and the dashboard alert panel");
        assertTrue(results.size() > 0);
        assertEquals("alert_center_overdue_actions", results.get(0).id);
    }

    @Test
    public void testQrReissueQuestionMatchesQrReportingTopic() {
        List<CopilotKnowledgeBase.Topic> results = CopilotKnowledgeBase.search(
                "if I reissue a QR code will the old printed one still work");
        assertTrue(results.size() > 0);
        assertEquals("qr_reporting_and_reissue", results.get(0).id);
    }

    @Test
    public void testAnalyticsVsReportsQuestionMatchesTheComparisonTopic() {
        List<CopilotKnowledgeBase.Topic> results = CopilotKnowledgeBase.search(
                "what is the difference between the analytics page and the reports page");
        assertTrue(results.size() > 0);
        assertEquals("analytics_vs_reports", results.get(0).id);
    }

    @Test
    public void testPublicQrScanQuestionMatchesTheExposureTopic() {
        List<CopilotKnowledgeBase.Topic> results = CopilotKnowledgeBase.search(
                "does the public anonymous qr scan page reveal who the current asset holder is");
        assertTrue(results.size() > 0);
        assertEquals("public_qr_scan_exposure", results.get(0).id);
    }

    @Test
    public void testUnrelatedQueryReturnsNoMatches() {
        List<CopilotKnowledgeBase.Topic> results = CopilotKnowledgeBase.search(
                "what is the capital of france and how do volcanoes form");
        assertTrue(results.isEmpty(), "A genuinely unrelated query must not force a weak match: " + results);
    }

    @Test
    public void testBlankQueryReturnsNoMatches() {
        assertTrue(CopilotKnowledgeBase.search("").isEmpty());
        assertTrue(CopilotKnowledgeBase.search("   ").isEmpty());
    }

    @Test
    public void testResultsAreCappedAtThree() {
        // A broad query touching many topics' shared vocabulary (asset,
        // status, role) must still return a focused top-3, not everything
        // that scored above zero.
        List<CopilotKnowledgeBase.Topic> results = CopilotKnowledgeBase.search(
                "asset status role employee request verification qr");
        assertTrue(results.size() <= 3, "Expected at most 3 ranked results, got " + results.size());
    }
}
