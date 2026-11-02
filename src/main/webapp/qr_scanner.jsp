<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="java.util.Locale"%>

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
                out.append(Character.toUpperCase(part.charAt(0))).append(part.substring(1)).append(" ");
            }
        }

        return out.toString().trim();
    }
%>

<%
    String username = (String) session.getAttribute("username");
    String role = (String) session.getAttribute("role");

    response.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
    response.setHeader("Pragma", "no-cache");
    response.setDateHeader("Expires", 0);

    if (username == null || role == null) {
        response.sendRedirect("login.jsp");
        return;
    }

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>QR Scanner - IR-AMS</title>

    <meta name="viewport" content="width=device-width, initial-scale=1.0">

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/qr_scanner.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

        <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
                <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content qr-scan-board">

            <section class="qr-scan-hero">
                <div>
                    <h1>QR Scanner</h1>
                    <p>
                        Scan printed asset QR labels or paste the QR token/link manually.
                        The scanner opens live asset details from the database.
                    </p>
                </div>

                
            </section>

            <section class="scan-layout">

                <div class="scan-panel">
                    <h2>Camera Scan</h2>

                    <div class="scanner-box">
                        <div id="reader">
                            <div class="scanner-placeholder">
                                <i class="fa-solid fa-camera"></i>
                                <strong>Camera scanner ready</strong>
                                <span>Click Start Camera and allow camera permission.</span>
                            </div>
                        </div>
                    </div>

                    <div class="scan-controls">
                        <button type="button" class="scan-btn primary" id="startScannerBtn">
                            <i class="fa-solid fa-play"></i>
                            Start Camera
                        </button>

                        <button type="button" class="scan-btn danger" id="stopScannerBtn">
                            <i class="fa-solid fa-stop"></i>
                            Stop
                        </button>

                        <button type="button" class="scan-btn" id="switchCameraBtn">
                            <i class="fa-solid fa-camera-rotate"></i>
                            Switch Camera
                        </button>
                    </div>

                    <div class="camera-note">
                        <strong>Camera note:</strong>
                        Browser camera works on <strong>localhost</strong> or <strong>HTTPS</strong>.
                        For mobile phone scanning, open the project using Cloudflare Tunnel HTTPS link.
                    </div>
                </div>

                <div class="scan-panel">
                    <h2>Manual QR / Token Scan</h2>

                    <div class="manual-box">
                        <label for="manualQrInput">Paste QR token or full QR link</label>

                        <textarea id="manualQrInput"
                                  placeholder="Example token: ECORQRABCDE12345&#10;or full link: http://localhost:8080/public_asset_view.jsp?token=ECORQRABCDE12345"></textarea>

                        <div class="scan-controls">
                            <button type="button" class="scan-btn primary" id="openManualBtn">
                                <i class="fa-solid fa-up-right-from-square"></i>
                                Open Live Asset
                            </button>

                            <button type="button" class="scan-btn" id="clearManualBtn">
                                <i class="fa-solid fa-eraser"></i>
                                Clear
                            </button>
                        </div>

                        <div id="scanResultBox" class="result-box"></div>
                    </div>

                    <div class="guide-grid">
                        <div class="guide-card">
                            <i class="fa-solid fa-link"></i>
                            <strong>Dynamic QR Link</strong>
                            <span>QR should contain public_asset_view.jsp token link. Same printed QR always shows latest updated asset details.</span>
                        </div>

                        <div class="guide-card">
                            <i class="fa-solid fa-mobile-screen-button"></i>
                            <strong>Mobile Scan</strong>
                            <span>Use Cloudflare Tunnel or deployed HTTPS link so mobile camera can open the live asset page.</span>
                        </div>

                        <div class="guide-card">
                            <i class="fa-solid fa-shield-halved"></i>
                            <strong>Official Use</strong>
                            <span>Employees can verify asset status, condition, holder and location from the QR public view.</span>
                        </div>

                        <div class="guide-card">
                            <i class="fa-solid fa-print"></i>
                            <strong>Print QR</strong>
                            <span>Generate QR from asset QR card page, then print and paste on asset label/sticker.</span>
                        </div>
                    </div>
                </div>

            </section>

        </div>
    </main>
</div>

<script src="https://unpkg.com/html5-qrcode" type="text/javascript"></script>

<script>
(function () {
    "use strict";

    var html5QrCode = null;
    var cameras = [];
    var currentCameraIndex = 0;
    var scannerRunning = false;

    var startBtn = document.getElementById("startScannerBtn");
    var stopBtn = document.getElementById("stopScannerBtn");
    var switchBtn = document.getElementById("switchCameraBtn");
    var manualInput = document.getElementById("manualQrInput");
    var openManualBtn = document.getElementById("openManualBtn");
    var clearManualBtn = document.getElementById("clearManualBtn");
    var resultBox = document.getElementById("scanResultBox");

    function showResult(message, type) {
        resultBox.className = "result-box active " + (type || "");
        resultBox.innerHTML = message;
    }

    function getContextPath() {
        return "<%= request.getContextPath() %>";
    }

    function isFullUrl(text) {
        return /^https?:\/\//i.test(text);
    }

    function extractToken(text) {
        if (!text) {
            return "";
        }

        text = text.trim();

        try {
            if (isFullUrl(text)) {
                var url = new URL(text);
                var token = url.searchParams.get("token") || url.searchParams.get("qr") || "";

                if (token.trim().length > 0) {
                    return token.trim();
                }
            }
        } catch (e) {
            console.warn(e);
        }

        var tokenMatch = text.match(/(?:token|qr)=([A-Za-z0-9_\-]+)/i);

        if (tokenMatch && tokenMatch[1]) {
            return tokenMatch[1].trim();
        }

        return text.replace(/\s+/g, "").trim();
    }

    function openQrValue(rawValue) {
        var text = (rawValue || "").trim();

        if (text.length === 0) {
            showResult("<strong>No QR value found.</strong><br>Please scan or paste QR token/link.", "warning");
            return;
        }

        if (isFullUrl(text)) {
            try {
                var scannedUrl = new URL(text);
                var tokenFromUrl = scannedUrl.searchParams.get("token") || scannedUrl.searchParams.get("qr") || "";

                if (tokenFromUrl.trim().length > 0) {
                    showResult("<strong>QR detected successfully.</strong><br>Opening live asset record...", "success");
                    window.location.href = getContextPath() + "/public_asset_view.jsp?token=" + encodeURIComponent(tokenFromUrl.trim());
                    return;
                }

                showResult("<strong>QR link detected.</strong><br>Opening scanned URL...", "success");
                window.location.href = text;
                return;

            } catch (e) {
                showResult("<strong>Invalid QR link.</strong><br>The scanned link is not readable.", "danger");
                return;
            }
        }

        var token = extractToken(text);

        if (token.length < 8) {
            showResult("<strong>Invalid token.</strong><br>QR token looks too short. Please scan again.", "danger");
            return;
        }

        showResult("<strong>QR token detected.</strong><br>Opening live asset record...", "success");
        window.location.href = getContextPath() + "/public_asset_view.jsp?token=" + encodeURIComponent(token);
    }

    function onScanSuccess(decodedText) {
        if (!decodedText) {
            return;
        }

        if (scannerRunning && html5QrCode) {
            html5QrCode.stop().then(function () {
                scannerRunning = false;
                openQrValue(decodedText);
            }).catch(function () {
                openQrValue(decodedText);
            });
        } else {
            openQrValue(decodedText);
        }
    }

    function onScanFailure() {
        /*
         * Silent failure while camera is scanning.
         * QR scanner fires many decode failures per second.
         */
    }

    function getPreferredCameraId() {
        if (!cameras || cameras.length === 0) {
            return null;
        }

        for (var i = 0; i < cameras.length; i++) {
            var label = (cameras[i].label || "").toLowerCase();

            if (label.indexOf("back") >= 0 || label.indexOf("rear") >= 0 || label.indexOf("environment") >= 0) {
                currentCameraIndex = i;
                return cameras[i].id;
            }
        }

        return cameras[currentCameraIndex].id;
    }

    function startScanner() {
        if (scannerRunning) {
            showResult("<strong>Scanner already running.</strong>", "warning");
            return;
        }

        if (typeof Html5Qrcode === "undefined") {
            showResult("<strong>Scanner library not loaded.</strong><br>Please check internet connection or use manual token paste.", "danger");
            return;
        }

        html5QrCode = html5QrCode || new Html5Qrcode("reader");

        Html5Qrcode.getCameras().then(function (devices) {
            cameras = devices || [];

            if (cameras.length === 0) {
                showResult("<strong>No camera found.</strong><br>Use manual QR token/link paste.", "danger");
                return;
            }

            var cameraId = getPreferredCameraId();

            html5QrCode.start(
                cameraId,
                {
                    fps: 10,
                    qrbox: function (viewfinderWidth, viewfinderHeight) {
                        var minEdge = Math.min(viewfinderWidth, viewfinderHeight);
                        var boxSize = Math.floor(minEdge * 0.72);

                        return {
                            width: boxSize,
                            height: boxSize
                        };
                    },
                    aspectRatio: 1.0
                },
                onScanSuccess,
                onScanFailure
            ).then(function () {
                scannerRunning = true;
                showResult("<strong>Camera started.</strong><br>Point camera towards printed asset QR code.", "success");
            }).catch(function (err) {
                showResult("<strong>Camera permission failed.</strong><br>" + String(err), "danger");
            });

        }).catch(function (err) {
            showResult("<strong>Unable to access camera.</strong><br>" + String(err), "danger");
        });
    }

    function stopScanner() {
        if (!scannerRunning || !html5QrCode) {
            showResult("<strong>Scanner is not running.</strong>", "warning");
            return;
        }

        html5QrCode.stop().then(function () {
            scannerRunning = false;
            showResult("<strong>Scanner stopped.</strong>", "success");
        }).catch(function (err) {
            showResult("<strong>Unable to stop scanner.</strong><br>" + String(err), "danger");
        });
    }

    function switchCamera() {
        if (!cameras || cameras.length <= 1) {
            showResult("<strong>No alternate camera found.</strong>", "warning");
            return;
        }

        currentCameraIndex = (currentCameraIndex + 1) % cameras.length;

        if (scannerRunning && html5QrCode) {
            html5QrCode.stop().then(function () {
                scannerRunning = false;
                startScanner();
            }).catch(function () {
                startScanner();
            });
        } else {
            startScanner();
        }
    }

    startBtn.addEventListener("click", startScanner);
    stopBtn.addEventListener("click", stopScanner);
    switchBtn.addEventListener("click", switchCamera);

    openManualBtn.addEventListener("click", function () {
        openQrValue(manualInput.value);
    });

    clearManualBtn.addEventListener("click", function () {
        manualInput.value = "";
        resultBox.className = "result-box";
        resultBox.innerHTML = "";
        manualInput.focus();
    });

    manualInput.addEventListener("keydown", function (event) {
        if (event.ctrlKey && event.key === "Enter") {
            openQrValue(manualInput.value);
        }
    });
})();
</script>

<script src="js/topbar-search.js?v=28000"></script>
<script src="js/user-dropdown.js?v=28000"></script>
<script src="js/sidebar-role.js?v=28000"></script>
<script src="js/ir-body-watermark.js?v=28000"></script>
<script src="js/dashboard-actions.js?v=28000"></script>

</body>
</html>