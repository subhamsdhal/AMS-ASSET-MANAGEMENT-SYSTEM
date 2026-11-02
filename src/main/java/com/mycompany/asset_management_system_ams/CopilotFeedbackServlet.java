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
 * CopilotFeedbackServlet — records a thumbs-up/down on one Copilot answer.
 *
 * Deliberately tiny and fire-and-forget from the UI's perspective: the chat
 * experience the feedback is ABOUT must never be disrupted by giving
 * feedback on it, so this never returns anything the JS needs to branch on
 * beyond a plain ok/not-ok - see ams_copilot.jsp's feedback button handler.
 */
@WebServlet(name = "CopilotFeedbackServlet", urlPatterns = {"/CopilotFeedbackServlet"})
public class CopilotFeedbackServlet extends HttpServlet {

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
                out.print("{\"ok\":false,\"error\":\"Session expired.\"}");
            }
            return;
        }

        int userId = getSessionUserId(session);
        String question = trimTo(request.getParameter("question"), 2000);
        String answer = trimTo(request.getParameter("answer"), 8000);
        String rating = request.getParameter("rating");

        if (userId <= 0 || question.isEmpty() || answer.isEmpty()) {
            try (PrintWriter out = response.getWriter()) {
                out.print("{\"ok\":false,\"error\":\"Missing question/answer.\"}");
            }
            return;
        }

        boolean saved = CopilotFeedbackDAO.record(userId, question, answer, rating);

        try (PrintWriter out = response.getWriter()) {
            out.print("{\"ok\":" + saved + "}");
        }
    }

    private String trimTo(String value, int max) {
        if (value == null) {
            return "";
        }
        String trimmed = value.trim();
        return trimmed.length() > max ? trimmed.substring(0, max) : trimmed;
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
