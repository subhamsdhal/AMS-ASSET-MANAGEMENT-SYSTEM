package com.mycompany.asset_management_system_ams;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

import java.io.IOException;
import java.io.PrintWriter;

/**
 * CopilotServlet — Handles AJAX requests from ams_copilot.jsp.
 * Returns JSON response with the copilot answer.
 */
@WebServlet(name = "CopilotServlet", urlPatterns = {"/CopilotServlet"})
public class CopilotServlet extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        request.setCharacterEncoding("UTF-8");
        response.setContentType("application/json; charset=UTF-8");
        response.setCharacterEncoding("UTF-8");

        HttpSession session = request.getSession(false);

        if (session == null || session.getAttribute("username") == null) {
            response.setStatus(401);
            try (PrintWriter out = response.getWriter()) {
                out.print("{\"error\":\"Session expired. Please login.\",\"answer\":null}");
            }
            return;
        }

        if (!SettingsDAO.isCopilotEnabled()) {
            try (PrintWriter out = response.getWriter()) {
                out.print("{\"answer\":\"AMS Copilot is currently disabled. Enable it in Settings.\",\"type\":\"DISABLED\"}");
            }
            return;
        }

        int userId = getSessionUserId(session);

        // "test_connection" action was moved to TestCopilotConnectionServlet

        String question = request.getParameter("question");
        if (question == null || question.trim().isEmpty()) {
            try (PrintWriter out = response.getWriter()) {
                out.print("{\"answer\":\"Please type a question.\",\"type\":\"EMPTY\"}");
            }
            return;
        }

        // Limit question length for safety
        if (question.length() > 500) {
            question = question.substring(0, 500);
        }

        // Optional attached image (ams_copilot.jsp's attach control) - raw
        // base64, no "data:...;base64," prefix (stripped client-side), plus
        // its mime type. Both blank/null on every request that doesn't
        // attach one, which CopilotEngine.answer()'s overload treats
        // identically to the no-image call.
        String imageData = request.getParameter("imageData");
        String imageMimeType = request.getParameter("imageMimeType");
        // Defensive cap. ams_copilot.jsp downscales every attached photo to
        // at most 1280px on its longest side before sending (a canvas
        // re-encode, not a raw phone-camera file, which would otherwise be
        // several MB and risk the servlet container's default POST-size
        // limit on an application/x-www-form-urlencoded body) - a resized
        // JPEG at that size is reliably well under 1MB of base64. 4M chars
        // leaves generous headroom over that expected size while still
        // guarding against a malformed or abusive request bloating memory/
        // the outbound LLM payload.
        if (imageData != null && imageData.length() > 4_000_000) {
            imageData = null;
            imageMimeType = null;
        }

        String username = (String) session.getAttribute("username");
        String role = (String) session.getAttribute("role");

        CopilotEngine.CopilotResponse resp =
                CopilotEngine.answer(question, userId, username, role, session, imageData, imageMimeType);

        // Build JSON response
        String answerJson = jsonEscape(resp.answer);
        String typeJson = jsonEscape(resp.mode);

        try (PrintWriter out = response.getWriter()) {
            out.print("{\"answer\":" + answerJson + ",\"type\":" + typeJson + "}");
        }
    }

    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {
        // For history/stats endpoint
        HttpSession session = request.getSession(false);
        if (session == null || session.getAttribute("username") == null) {
            response.setStatus(401);
            return;
        }

        String action = request.getParameter("action");
        response.setContentType("application/json; charset=UTF-8");

        if ("status".equals(action)) {
            boolean enabled = SettingsDAO.isCopilotEnabled();
            boolean aiMode = SettingsDAO.isAiMode();
            String mode = aiMode ? "AI" : "RULE_BASED";
            String provider = SettingsDAO.getCopilotProvider();

            try (PrintWriter out = response.getWriter()) {
                out.print("{\"enabled\":" + enabled
                        + ",\"mode\":" + jsonEscape(mode)
                        + ",\"aiMode\":" + aiMode
                        + ",\"provider\":" + jsonEscape(provider)
                        + "}");
            }
        }
    }

    private String jsonEscape(String s) {
        if (s == null) return "null";
        return "\"" + s
                .replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\n", "\\n")
                .replace("\r", "\\r")
                .replace("\t", "\\t")
                + "\"";
    }

    private int getSessionUserId(HttpSession session) {
        String[] names = {"userId", "user_id"};
        for (String name : names) {
            try {
                Object value = session.getAttribute(name);
                if (value != null) {
                    int parsed = Integer.parseInt(String.valueOf(value));
                    if (parsed > 0) {
                        return parsed;
                    }
                }
            } catch (Exception ignored) {}
        }
        return 0;
    }
}
