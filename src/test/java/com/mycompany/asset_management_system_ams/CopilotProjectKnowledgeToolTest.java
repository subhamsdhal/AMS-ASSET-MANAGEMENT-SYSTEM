package com.mycompany.asset_management_system_ams;

import java.util.List;
import java.util.Map;

import jakarta.servlet.http.HttpSession;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;

/**
 * CopilotProjectKnowledgeToolTest — get_project_knowledge (via
 * search_project_knowledge in the catalog), and its role-availability -
 * deliberately open to every role, unlike every other admin/audit-only tool
 * added this session, since explaining how the system works is not
 * sensitive the way live records or Copilot-operational data are.
 */
public class CopilotProjectKnowledgeToolTest {

    @Test
    public void testBlankQueryIsAnError() {
        CopilotQueryPlan plan = new CopilotQueryPlan();
        plan.knowledgeQuery = null;
        Map<String, Object> result = CopilotToolExecutor.getProjectKnowledge(plan, mock(HttpSession.class));
        assertTrue(result.containsKey("error"));
    }

    @Test
    public void testMatchingQueryReturnsTopics() {
        CopilotQueryPlan plan = new CopilotQueryPlan();
        plan.knowledgeQuery = "how does asset request approval work";
        Map<String, Object> result = CopilotToolExecutor.getProjectKnowledge(plan, mock(HttpSession.class));

        assertEquals(Boolean.TRUE, result.get("found"));
        @SuppressWarnings("unchecked")
        List<Map<String, String>> topics = (List<Map<String, String>>) result.get("topics");
        assertFalse(topics.isEmpty());
        assertTrue(topics.get(0).get("content").toLowerCase().contains("pending"));
    }

    @Test
    public void testNoMatchReturnsFoundFalseWithHonestNote() {
        CopilotQueryPlan plan = new CopilotQueryPlan();
        plan.knowledgeQuery = "capital of france";
        Map<String, Object> result = CopilotToolExecutor.getProjectKnowledge(plan, mock(HttpSession.class));

        assertEquals(Boolean.FALSE, result.get("found"));
        assertTrue(((String) result.get("note")).toLowerCase().contains("isn't something"));
    }

    @Test
    public void testEveryRoleIsPermittedToUseThisTool() {
        for (String role : new String[]{"SUPER_ADMIN", "ADMIN", "ASSET_MANAGER", "AUDITOR",
                "DEPARTMENT_HEAD", "EMPLOYEE"}) {
            List<LlmToolSpec> tools = CopilotToolCatalog.forRole(role);
            boolean hasKnowledgeTool = tools.stream().anyMatch(t -> "search_project_knowledge".equals(t.name));
            assertTrue(hasKnowledgeTool, role + " should be able to ask how IR-AMS works.");
        }
    }
}
