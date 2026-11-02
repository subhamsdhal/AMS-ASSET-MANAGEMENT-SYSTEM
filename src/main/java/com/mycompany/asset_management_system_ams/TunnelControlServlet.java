package com.mycompany.asset_management_system_ams;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.util.logging.Logger;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * TunnelControlServlet - Manages Ngrok, Cloudflare or Custom mobile tunnels.
 * Supports starting cloudflared locally or saving manual URLs for Ngrok/Custom.
 */
@WebServlet(name = "TunnelControlServlet", urlPatterns = {"/TunnelControlServlet", "/CloudflareTunnelServlet"})
public class TunnelControlServlet extends HttpServlet {

    private static final Logger LOGGER = Logger.getLogger(TunnelControlServlet.class.getName());
    private static final String CLOUDFLARED_PATH = "C:\\Cloudflared\\cloudflared.exe";
    private static Process tunnelProcess = null;
    private static String currentTunnelUrl = "";
    private static String tunnelStatus = "stopped"; // stopped, starting, running, error

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        request.setCharacterEncoding("UTF-8");
        response.setContentType("application/json; charset=UTF-8");

        HttpSession session = request.getSession(false);
        if (session == null || session.getAttribute("username") == null) {
            response.setStatus(401);
            try (PrintWriter out = response.getWriter()) {
                out.print("{\"error\":\"Unauthorized\"}");
            }
            return;
        }

        String role = (String) session.getAttribute("role");
        if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))) {
            try (PrintWriter out = response.getWriter()) {
                out.print("{\"error\":\"Access denied. SUPER_ADMIN only.\"}");
            }
            return;
        }

        // Fault (fixed, deployment-hardening): RBAC alone used to be this
        // servlet's only gate, but it can spawn a real OS-level child process
        // (cloudflared) - a categorically different, much larger capability
        // than anything else reachable in this application, appropriate only
        // for a local/dev/demo instance (see the hardcoded Windows-only
        // CLOUDFLARED_PATH below, and RAILWAY_AMS_FINAL_DEMO_CHECKLIST.md at
        // the repo root). This must not exist as a reachable capability in a
        // real deployment regardless of who's allowed to trigger it, so it's
        // now off by default and requires an explicit opt-in
        // (system_settings.ams.mobile_tunnel.enabled='true') rather than
        // being live the moment an ADMIN/SUPER_ADMIN session exists.
        if (!SettingsDAO.isMobileTunnelEnabled()) {
            response.setStatus(403);
            try (PrintWriter out = response.getWriter()) {
                out.print("{\"error\":\"Mobile tunnel control is disabled for this deployment.\"}");
            }
            return;
        }

        int userId = 0;
        // Was reading session attribute "userId" - LoginServlet (the only place that
        // ever sets it) uses "user_id". userId was always 0 for every real user here.
        try { userId = Integer.parseInt(String.valueOf(session.getAttribute("user_id"))); } catch (Exception ignored) {}

        String action = request.getParameter("action");
        String provider = clean(request.getParameter("provider"));

        try (PrintWriter out = response.getWriter()) {
            if ("start".equals(action)) {
                if ("cloudflare".equalsIgnoreCase(provider)) {
                    String result = startCloudflareTunnel(userId);
                    out.print(result);
                } else if ("ngrok".equalsIgnoreCase(provider)) {
                    out.print("{\"status\":\"error\",\"message\":\"Automatic Ngrok start is not supported. Please start ngrok locally (ngrok http 8080) and paste the generated public URL below.\"}");
                } else {
                    out.print("{\"status\":\"error\",\"message\":\"Automatic start is only supported for Cloudflare Tunnel.\"}");
                }
            } else if ("stop".equals(action)) {
                stopTunnel(userId);
                out.print("{\"status\":\"stopped\",\"message\":\"Tunnel stopped. QR codes will use localhost URL.\"}");
            } else if ("status".equals(action)) {
                out.print(getStatusJson());
            } else if ("set_manual".equals(action)) {
                String manualUrl = clean(request.getParameter("url"));
                if (!manualUrl.isEmpty()) {
                    if (!manualUrl.startsWith("http://") && !manualUrl.startsWith("https://")) {
                        out.print("{\"error\":\"Invalid URL. Must start with http:// or https://\"}");
                        return;
                    }
                    if (manualUrl.contains("<") || manualUrl.contains(">") || manualUrl.contains("\"") || manualUrl.contains("'")) {
                        out.print("{\"error\":\"Invalid characters in URL.\"}");
                        return;
                    }
                    SettingsDAO.setMobileTunnelUrl(manualUrl, userId);
                    SettingsDAO.setQrTunnelProvider(provider.isEmpty() ? "custom" : provider, userId);
                    currentTunnelUrl = manualUrl;
                    tunnelStatus = "manual";
                    AuditDAO.log(userId, "UPDATE", "system_settings", 1, "Manual tunnel URL set: " + manualUrl + " (Provider: " + provider + ")");
                    out.print("{\"status\":\"manual\",\"url\":" + json(manualUrl) + ",\"message\":\"Manual URL saved. QR codes updated.\"}");
                } else {
                    // clear url
                    SettingsDAO.setMobileTunnelUrl("", userId);
                    if (!provider.isEmpty()) {
                        SettingsDAO.setQrTunnelProvider(provider, userId);
                    }
                    currentTunnelUrl = "";
                    tunnelStatus = "stopped";
                    out.print("{\"status\":\"stopped\",\"url\":\"\",\"message\":\"Tunnel URL cleared.\"}");
                }
            } else {
                out.print("{\"error\":\"Unknown action.\"}");
            }
        }
    }

    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {
        response.setContentType("application/json; charset=UTF-8");
        HttpSession session = request.getSession(false);
        if (session == null || session.getAttribute("username") == null) {
            response.setStatus(401);
            return;
        }
        try (PrintWriter out = response.getWriter()) {
            out.print(getStatusJson());
        }
    }

    // -------------------------------------------------------
    // Tunnel Management
    // -------------------------------------------------------

    private synchronized String startCloudflareTunnel(int userId) {
        stopTunnelProcess();

        java.io.File cf = new java.io.File(CLOUDFLARED_PATH);
        if (!cf.exists()) {
            tunnelStatus = "error";
            return "{\"status\":\"error\",\"message\":\"cloudflared.exe not found at " + CLOUDFLARED_PATH.replace("\\", "\\\\") + ". Please install cloudflared.\"}";
        }

        tunnelStatus = "starting";
        currentTunnelUrl = "";

        try {
            ProcessBuilder pb = new ProcessBuilder(CLOUDFLARED_PATH, "tunnel", "--url", "http://localhost:8080");
            pb.redirectErrorStream(true);
            tunnelProcess = pb.start();

            final Process proc = tunnelProcess;
            Thread reader = new Thread(() -> {
                try (BufferedReader br = new BufferedReader(new InputStreamReader(proc.getInputStream()))) {
                    Pattern pattern = Pattern.compile("https://[a-z0-9-]+\\.trycloudflare\\.com");
                    String line;
                    while ((line = br.readLine()) != null) {
                        LOGGER.info("[Cloudflared] " + line);
                        Matcher m = pattern.matcher(line);
                        if (m.find()) {
                            currentTunnelUrl = m.group();
                            tunnelStatus = "running";
                            SettingsDAO.setMobileTunnelUrl(currentTunnelUrl, userId);
                            SettingsDAO.setQrTunnelProvider("cloudflare", userId);
                            AuditDAO.log(userId, "UPDATE", "system_settings", 1, "Cloudflare tunnel started: " + currentTunnelUrl);
                            break;
                        }
                    }
                    while ((line = br.readLine()) != null) {
                        LOGGER.fine("[Cloudflared] " + line);
                    }
                } catch (Exception e) {
                    LOGGER.warning("[Cloudflared] Reader error: " + e.getMessage());
                }
            });
            reader.setDaemon(true);
            reader.start();

            int waited = 0;
            while (currentTunnelUrl.isEmpty() && tunnelProcess.isAlive() && waited < 200) {
                Thread.sleep(100);
                waited++;
            }

            if (!currentTunnelUrl.isEmpty()) {
                return "{\"status\":\"running\",\"url\":" + json(currentTunnelUrl)
                        + ",\"message\":\"Tunnel started! QR codes are now accessible from any mobile. URL: " + currentTunnelUrl + "\"}";
            } else if (!tunnelProcess.isAlive()) {
                tunnelStatus = "error";
                return "{\"status\":\"error\",\"message\":\"cloudflared process exited unexpectedly. Check if port 8080 is accessible.\"}";
            } else {
                tunnelStatus = "starting";
                return "{\"status\":\"starting\",\"message\":\"Tunnel is starting. Refresh status in a few seconds.\"}";
            }
        } catch (Exception e) {
            tunnelStatus = "error";
            return "{\"status\":\"error\",\"message\":\"Failed to start tunnel: " + jsonEscapeSimple(e.getMessage()) + "\"}";
        }
    }

    private synchronized void stopTunnel(int userId) {
        stopTunnelProcess();
        currentTunnelUrl = "";
        tunnelStatus = "stopped";
        SettingsDAO.setMobileTunnelUrl("", userId);
        AuditDAO.log(userId, "UPDATE", "system_settings", 1, "Tunnel stopped. QR URL reverted to localhost.");
    }

    private void stopTunnelProcess() {
        if (tunnelProcess != null && tunnelProcess.isAlive()) {
            tunnelProcess.destroy();
            try { tunnelProcess.waitFor(); } catch (Exception ignored) {}
        }
        tunnelProcess = null;
    }

    private String getStatusJson() {
        String savedUrl = SettingsDAO.getMobileTunnelUrl();
        String effectiveUrl = SettingsDAO.getQrBaseUrl();
        String displayStatus = tunnelStatus;
        if (!"running".equals(tunnelStatus) && !savedUrl.isEmpty()) {
            displayStatus = "manual";
        }
        return "{\"status\":" + json(displayStatus)
                + ",\"tunnelUrl\":" + json(currentTunnelUrl)
                + ",\"savedUrl\":" + json(savedUrl)
                + ",\"effectiveQrBaseUrl\":" + json(effectiveUrl)
                + ",\"processAlive\":" + (tunnelProcess != null && tunnelProcess.isAlive())
                + "}";
    }

    private String clean(String s) { return s == null ? "" : s.trim(); }
    private String json(String s) { return s == null ? "null" : "\"" + jsonEscapeSimple(s) + "\""; }
    private String jsonEscapeSimple(String s) { return s == null ? "" : s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n"); }

    @Override
    public void destroy() {
        if (tunnelProcess != null && tunnelProcess.isAlive()) {
            tunnelProcess.destroy();
        }
        super.destroy();
    }
}
