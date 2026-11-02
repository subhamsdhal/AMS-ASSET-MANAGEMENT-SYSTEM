<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="java.net.URLEncoder"%>

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

    token = token.trim();

    if (token.contains("token=")) {
        token = token.substring(token.indexOf("token=") + 6);
        int ampIndex = token.indexOf("&");
        if (ampIndex >= 0) {
            token = token.substring(0, ampIndex);
        }
    }

    String redirectUrl = "public_asset_view.jsp";

    if (!token.trim().isEmpty()) {
        redirectUrl += "?token=" + URLEncoder.encode(token.trim(), "UTF-8");
    }

    response.sendRedirect(redirectUrl);
%>
