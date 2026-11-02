(function () {
    "use strict";

    var rafId = 0;
    var timerList = [];

    function qs(selector) {
        return document.querySelector(selector);
    }

    function getNumberFromCssVar(name, fallback) {
        var raw = getComputedStyle(document.documentElement).getPropertyValue(name) || "";
        var value = parseFloat(raw);
        return isNaN(value) ? fallback : value;
    }

    function isRailwayPage() {
        return !!(
            document.body && (
                document.body.classList.contains("railway-ui") ||
                qs(".railway-main") ||
                qs(".main") ||
                qs(".railway-sidebar") ||
                qs(".sidebar")
            )
        );
    }

    function ensureRailwayBodyClass() {
        if (document.body && isRailwayPage()) {
            document.body.classList.add("railway-ui");
        }
    }

    function getWatermark() {
        var watermark = qs(".ir-global-body-watermark");

        if (watermark) {
            return watermark;
        }

        if (!document.body || !isRailwayPage()) {
            return null;
        }

        watermark = document.createElement("div");
        watermark.className = "ir-global-body-watermark";
        watermark.setAttribute("aria-hidden", "true");

        var img = document.createElement("img");
        img.src = "images/Emblem_of_India.png";
        img.alt = "";
        img.draggable = false;
        img.loading = "eager";
        img.decoding = "async";

        watermark.appendChild(img);
        document.body.appendChild(watermark);

        return watermark;
    }

    function removeDuplicateWatermarks() {
        var marks = Array.prototype.slice.call(
            document.querySelectorAll(".ir-global-body-watermark, .page-fixed-emblem-watermark")
        );

        if (marks.length <= 1) {
            return;
        }

        var keep = marks[0];

        marks.slice(1).forEach(function (mark) {
            if (mark !== keep && mark.parentNode) {
                mark.parentNode.removeChild(mark);
            }
        });
    }

    function getVisibleMainArea() {
        var sidebarWidth = getNumberFromCssVar("--ir-sidebar-width", 245);
        var leftStripWidth = getNumberFromCssVar("--ir-left-strip-width", 7);
        var collapsed = document.body.classList.contains("sidebar-collapsed");

        var main = qs(".railway-main") || qs(".main");
        var scroll = qs(".main-scroll-content");
        var topbar = qs(".railway-topbar") || qs(".topbar");
        var sidebar = qs(".railway-sidebar") || qs(".sidebar");

        var left = collapsed ? leftStripWidth : leftStripWidth + sidebarWidth;
        var right = window.innerWidth;

        if (main) {
            var mainRect = main.getBoundingClientRect();

            if (mainRect.width > 120) {
                left = Math.max(left, mainRect.left);
                right = Math.min(right, mainRect.right);
            }
        }

        if (!collapsed && sidebar) {
            var sidebarRect = sidebar.getBoundingClientRect();

            if (sidebarRect.right > 0) {
                left = Math.max(left, sidebarRect.right);
            }
        }

        if (right <= left + 120) {
            right = window.innerWidth;
        }

        var top = 83;
        var bottom = window.innerHeight - 14;

        if (topbar) {
            var topbarRect = topbar.getBoundingClientRect();

            if (topbarRect.bottom > 0) {
                top = Math.max(top, topbarRect.bottom + 4);
            }
        }

        if (scroll) {
            var scrollRect = scroll.getBoundingClientRect();

            if (scrollRect.height > 120) {
                top = Math.max(top, scrollRect.top);
                bottom = Math.min(bottom, scrollRect.bottom);
            }
        }

        if (bottom <= top + 120) {
            bottom = window.innerHeight - 14;
        }

        return {
            left: left,
            right: right,
            top: top,
            bottom: bottom
        };
    }

    function applyWatermarkCenter() {
        ensureRailwayBodyClass();

        if (!document.body || !document.body.classList.contains("railway-ui")) {
            return;
        }

        var watermark = getWatermark();

        if (!watermark) {
            return;
        }

        removeDuplicateWatermarks();

        var area = getVisibleMainArea();
        var centerX = Math.round(area.left + ((area.right - area.left) / 2));
        var centerY = Math.round(area.top + ((area.bottom - area.top) / 2));

        /*
           IMPORTANT:
           Older page CSS added --ir-body-watermark-left on body itself.
           Root-level JS variables cannot override body-level variables.
           So this fix writes to BOTH documentElement and body, and also sets
           direct element style left/top. This bypasses the fixed-position bug.
        */
        document.documentElement.style.setProperty("--ir-body-watermark-left", centerX + "px");
        document.documentElement.style.setProperty("--ir-body-watermark-top", centerY + "px");

        document.body.style.setProperty("--ir-body-watermark-left", centerX + "px");
        document.body.style.setProperty("--ir-body-watermark-top", centerY + "px");

        watermark.style.left = centerX + "px";
        watermark.style.top = centerY + "px";
        watermark.style.position = "fixed";
        watermark.style.transform = "translate(-50%, -50%)";
        watermark.style.pointerEvents = "none";
        watermark.style.userSelect = "none";
    }

    function clearTimers() {
        while (timerList.length) {
            clearTimeout(timerList.pop());
        }
    }

    function scheduleWatermarkCenter() {
        clearTimers();

        if (rafId) {
            cancelAnimationFrame(rafId);
        }

        rafId = requestAnimationFrame(function () {
            rafId = 0;
            applyWatermarkCenter();
        });

        [60, 140, 240, 420, 700, 1000].forEach(function (delay) {
            timerList.push(setTimeout(applyWatermarkCenter, delay));
        });
    }

    function bindWatchers() {
        var nodes = [
            document.body,
            qs(".app"),
            qs(".ams-shell"),
            qs(".railway-sidebar") || qs(".sidebar"),
            qs(".railway-main") || qs(".main"),
            qs(".main-scroll-content"),
            qs(".railway-topbar") || qs(".topbar")
        ].filter(Boolean);

        nodes.forEach(function (node) {
            node.addEventListener("transitionrun", scheduleWatermarkCenter);
            node.addEventListener("transitionend", scheduleWatermarkCenter);

            var observer = new MutationObserver(scheduleWatermarkCenter);
            observer.observe(node, {
                attributes: true,
                attributeFilter: ["class", "style"]
            });
        });
    }

    function init() {
        ensureRailwayBodyClass();
        getWatermark();
        bindWatchers();
        scheduleWatermarkCenter();
    }

    window.IRAMSUpdateBodyWatermark = scheduleWatermarkCenter;

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", init, { once: true });
    } else {
        init();
    }

    window.addEventListener("load", scheduleWatermarkCenter);
    window.addEventListener("resize", scheduleWatermarkCenter);
    window.addEventListener("orientationchange", scheduleWatermarkCenter);

    document.addEventListener("click", function (event) {
        if (event.target.closest(".nav-toggle") ||
                event.target.closest("[data-sidebar-toggle]") ||
                event.target.closest(".sidebar-toggle") ||
                event.target.closest(".menu-toggle")) {
            scheduleWatermarkCenter();
        }
    });
})();
