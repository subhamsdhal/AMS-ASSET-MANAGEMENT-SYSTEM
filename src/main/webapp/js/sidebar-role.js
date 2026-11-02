(function () {
    "use strict";

    function normalizeText(text) {
        if (!text) {
            return "";
        }

        return text
            .toString()
            .replace(/\s+/g, " ")
            .trim()
            .toLowerCase();
    }

    function normalizeRoleKey(text) {
        return normalizeText(text).replace(/\s+/g, "_").toUpperCase();
    }

    function roleFromText(text) {
        var roleText = normalizeText(text);
        var roleKey = normalizeRoleKey(text);

        if (roleText.indexOf("super admin") !== -1 || roleKey.indexOf("SUPER_ADMIN") !== -1) {
            return "SUPER_ADMIN";
        }

        if (roleText === "admin" || roleKey === "ADMIN") {
            return "ADMIN";
        }

        if (roleText.indexOf("asset manager") !== -1 || roleKey.indexOf("ASSET_MANAGER") !== -1) {
            return "ASSET_MANAGER";
        }

        if (roleText.indexOf("department head") !== -1 || roleKey.indexOf("DEPARTMENT_HEAD") !== -1) {
            return "DEPARTMENT_HEAD";
        }

        if (roleText.indexOf("auditor") !== -1) {
            return "AUDITOR";
        }

        if (roleText.indexOf("employee") !== -1) {
            return "EMPLOYEE";
        }

        return "";
    }

    function getUserRole() {
        var dataRoleElements = [
            document.querySelector(".railway-sidebar[data-user-role]"),
            document.querySelector(".sidebar[data-user-role]"),
            document.querySelector("[data-current-role]"),
            document.body
        ];

        for (var i = 0; i < dataRoleElements.length; i++) {
            if (dataRoleElements[i]) {
                var dataRole = dataRoleElements[i].getAttribute("data-user-role")
                        || dataRoleElements[i].getAttribute("data-current-role")
                        || "";
                var parsedDataRole = roleFromText(dataRole);
                if (parsedDataRole) {
                    return parsedDataRole;
                }
            }
        }

        var possibleRoleElements = [
            document.querySelector(".user-card span"),
            document.querySelector(".rail-user-main span"),
            document.querySelector(".profile-role"),
            document.querySelector(".user-role")
        ];

        for (var j = 0; j < possibleRoleElements.length; j++) {
            if (possibleRoleElements[j]) {
                var parsedRole = roleFromText(possibleRoleElements[j].textContent || "");
                if (parsedRole) {
                    return parsedRole;
                }
            }
        }

        return "EMPLOYEE";
    }

    function getCurrentPage() {
        var path = window.location.pathname || "";
        var fileName = path.substring(path.lastIndexOf("/") + 1);

        if (!fileName || fileName.trim() === "") {
            fileName = "dashboard.jsp";
        }

        return fileName.toLowerCase();
    }

    function getAllMenuLinks() {
        var links = [];

        var selectors = [
            ".menu-link",
            ".submenu-link",
            ".sidebar a",
            ".rail-sidebar a",
            ".railway-sidebar a"
        ];

        selectors.forEach(function (selector) {
            var found = document.querySelectorAll(selector);

            found.forEach(function (item) {
                if (links.indexOf(item) === -1) {
                    links.push(item);
                }
            });
        });

        return links;
    }

    function hasMenuHref(keyword) {
        var links = getAllMenuLinks();
        var key = keyword.toLowerCase();

        for (var i = 0; i < links.length; i++) {
            var href = (links[i].getAttribute("href") || "").toLowerCase();
            var filename = href.substring(href.lastIndexOf("/") + 1);
            if (filename.indexOf("?") !== -1) {
                filename = filename.substring(0, filename.indexOf("?"));
            }

            if (filename === key || href === key) {
                return true;
            }
        }

        return false;
    }

    function hideLinkByHref(keyword) {
        var links = getAllMenuLinks();
        var key = keyword.toLowerCase();

        links.forEach(function (link) {
            var href = (link.getAttribute("href") || "").toLowerCase();
            var filename = href.substring(href.lastIndexOf("/") + 1);
            // Remove query parameters for matching if any
            if (filename.indexOf("?") !== -1) {
                filename = filename.substring(0, filename.indexOf("?"));
            }

            if (filename === key || href === key) {
                link.style.setProperty("display", "none", "important");
                link.setAttribute("aria-hidden", "true");
            }
        });
    }

    function showLinkByHref(keyword) {
        var links = getAllMenuLinks();
        var key = keyword.toLowerCase();

        links.forEach(function (link) {
            var href = (link.getAttribute("href") || "").toLowerCase();
            var filename = href.substring(href.lastIndexOf("/") + 1);
            if (filename.indexOf("?") !== -1) {
                filename = filename.substring(0, filename.indexOf("?"));
            }

            if (filename === key || href === key) {
                link.style.removeProperty("display");
                link.removeAttribute("aria-hidden");
            }
        });
    }

    function hideMany(pages) {
        pages.forEach(function (page) {
            hideLinkByHref(page);
        });
    }

    function showMany(pages) {
        pages.forEach(function (page) {
            showLinkByHref(page);
        });
    }

    function canViewQr(role) {
        return role === "SUPER_ADMIN"
            || role === "ADMIN"
            || role === "ASSET_MANAGER"
            || role === "AUDITOR";
    }

    function canManageQr(role) {
        return role === "SUPER_ADMIN"
            || role === "ADMIN"
            || role === "ASSET_MANAGER";
    }

    var qrViewPages = [
        "qr_control_center.jsp",
        "qr_asset_register.jsp",
        "qr_scan_logs.jsp",
        "view_qr_scan_log.jsp",
        "qr_scan_analytics.jsp",
        "qr_coverage_report.jsp",
        "qr_missing_qr_report.jsp",
        "qr_asset_scan_history.jsp",
        "qr_ip_audit_report.jsp",
        "qr_exception_report.jsp",
        "qr_system_health.jsp",
        "qr_token_lookup.jsp",
        "qr_tagging_status.jsp",
        "qr_tagging_work_order.jsp",
        "qr_print.jsp",
        "qr_print_labels.jsp",
        "export_qr_scan_analytics_excel.jsp",
        "export_qr_coverage_report_excel.jsp",
        "export_qr_missing_qr_excel.jsp",
        "export_qr_asset_scan_history_excel.jsp",
        "export_qr_ip_audit_excel.jsp",
        "export_qr_tagging_status_excel.jsp",
        "export_qr_exception_report_excel.jsp"
    ];

    var qrManagePages = [
        "qr_bulk_generate.jsp",
        "bulkgenerateassetqrservlet",
        "qr_url_refresh.jsp",
        "refreshassetqrurlsservlet",
        "refreshassetqrurlservlet",
        "qr_token_reissue.jsp",
        "reissueassetqrtokenservlet",
        "qr_reissue_history.jsp",
        "export_qr_reissue_history_excel.jsp",
        "updateqrtaggingstatusservlet"
    ];

    var qrLegacyPages = [
        "qr_scanner.jsp",
        "qr_tags.jsp"
    ];

    var qrAllPages = []
        .concat(qrViewPages)
        .concat(qrManagePages)
        .concat(qrLegacyPages);

    var qrMenuLinks = [
        {
            title: "QR Control Center",
            href: "qr_control_center.jsp",
            icon: "fa-solid fa-qrcode"
        }
    ];

    function hideExtraQrSidebarLinks() {
        var sidebarMenus = [];

        [
            ".railway-sidebar .menu",
            ".rail-sidebar .menu",
            ".sidebar .menu"
        ].forEach(function (selector) {
            document.querySelectorAll(selector).forEach(function (menu) {
                if (sidebarMenus.indexOf(menu) === -1) {
                    sidebarMenus.push(menu);
                }
            });
        });

        var hiddenQrPages = qrAllPages.filter(function (page) {
            return page !== "qr_control_center.jsp";
        });

        sidebarMenus.forEach(function (menu) {
            menu.querySelectorAll("a").forEach(function (link) {
                var href = (link.getAttribute("href") || "").toLowerCase();

                hiddenQrPages.forEach(function (page) {
                    if (href.indexOf(page) !== -1) {
                        link.style.setProperty("display", "none", "important");
                        link.setAttribute("aria-hidden", "true");
                    }
                });
            });
        });
    }

    function injectSidebarQrLinks() {
        var role = getUserRole();

        if (!canViewQr(role)) {
            return;
        }

        var menu = document.querySelector(".railway-sidebar .menu")
            || document.querySelector(".rail-sidebar .menu")
            || document.querySelector(".sidebar .menu")
            || document.querySelector(".menu");

        if (!menu) {
            return;
        }

        qrMenuLinks.forEach(function (item) {
            if (hasMenuHref(item.href)) {
                return;
            }

            var link = document.createElement("a");
            link.href = item.href;
            link.innerHTML = "<i class=\"" + item.icon + "\"></i> " + item.title;

            var insertAfter = null;
            var allLinks = menu.querySelectorAll("a");

            allLinks.forEach(function (existing) {
                var href = (existing.getAttribute("href") || "").toLowerCase();

                if (href.indexOf("reports.jsp") !== -1) {
                    insertAfter = existing;
                }

                if (href.indexOf("audit_logs.jsp") !== -1) {
                    insertAfter = existing;
                }

                if (href.indexOf("qr_control_center.jsp") !== -1) {
                    insertAfter = existing;
                }

                if (href.indexOf("qr_asset_register.jsp") !== -1) {
                    insertAfter = existing;
                }

                if (href.indexOf("qr_tagging_status.jsp") !== -1) {
                    insertAfter = existing;
                }
            });

            if (insertAfter && insertAfter.nextSibling) {
                menu.insertBefore(link, insertAfter.nextSibling);
            } else if (insertAfter) {
                menu.appendChild(link);
            } else {
                menu.appendChild(link);
            }
        });
    }

    function applyRoleAccess() {
        var role = getUserRole();

        var roleRules = {
            SUPER_ADMIN: {
                allowAll: true,
                hide: []
            },

            ADMIN: {
                allowAll: true,
                hide: []
            },

            ASSET_MANAGER: {
                allowAll: false,
                hide: [
                    "add_department.jsp",
                    "edit_department.jsp",
                    "settings.jsp"
                ]
            },

            DEPARTMENT_HEAD: {
                allowAll: false,
                hide: [
                    "add_department.jsp",
                    "edit_department.jsp",
                    "add_asset.jsp",
                    "vendors.jsp",
                    "category_vendor_mapping.jsp",
                    "categories.jsp",
                    "allocation.jsp",
                    "returns.jsp",
                    "maintenance.jsp",
                    "physical_verification.jsp",
                    "reports.jsp",
                    "analytics.jsp",
                    "asset_health.jsp",
                    "warranty_report.jsp",
                    "settings.jsp",
                    "audit_logs.jsp"
                ].concat(qrAllPages)
            },

            AUDITOR: {
                allowAll: false,
                hide: [
                    "add_department.jsp",
                    "edit_department.jsp",
                    "add_asset.jsp",
                    "add_employee.jsp",
                    "employees.jsp",
                    "vendors.jsp",
                    "category_vendor_mapping.jsp",
                    "categories.jsp",
                    "asset_requests.jsp",
                    "allocation.jsp",
                    "returns.jsp",
                    "settings.jsp"
                ].concat(qrManagePages)
            },

            EMPLOYEE: {
                allowAll: false,
                hide: [
                    "departments.jsp",
                    "add_department.jsp",
                    "edit_department.jsp",
                    "view_department.jsp",
                    "export_departments_excel.jsp",
                    "assets.jsp",
                    "view_asset.jsp",
                    "asset_documents.jsp",
                    "add_asset.jsp",
                    "add_employee.jsp",
                    "employees.jsp",
                    "vendors.jsp",
                    "category_vendor_mapping.jsp",
                    "categories.jsp",
                    "asset_requests.jsp",
                    "allocation.jsp",
                    "returns.jsp",
                    "maintenance.jsp",
                    "physical_verification.jsp",
                    "reports.jsp",
                    "analytics.jsp",
                    "settings.jsp",
                    "audit_logs.jsp"
                ].concat(qrAllPages)
            }
        };

        var selectedRule = roleRules[role] || roleRules.EMPLOYEE;

        if (!selectedRule.allowAll) {
            hideMany(selectedRule.hide);
        }

        if (role === "SUPER_ADMIN" || role === "ADMIN") {
            showMany(qrAllPages);
            showLinkByHref("settings.jsp");
            showLinkByHref("audit_logs.jsp");
        }

        if (role === "ASSET_MANAGER") {
            showLinkByHref("physical_verification.jsp");
            showMany(qrViewPages);
            showMany(qrManagePages);
            showLinkByHref("qr_scanner.jsp");
            showLinkByHref("qr_tags.jsp");
        }

        if (role === "AUDITOR") {
            showLinkByHref("physical_verification.jsp");
            showLinkByHref("reports.jsp");
            showLinkByHref("analytics.jsp");
            showLinkByHref("audit_logs.jsp");
            showMany(qrViewPages);
            hideMany(qrManagePages);
            hideLinkByHref("qr_scanner.jsp");
            hideLinkByHref("qr_tags.jsp");
        }

        if (role === "DEPARTMENT_HEAD") {
            hideMany(qrAllPages);
        }

        if (role === "EMPLOYEE") {
            hideMany(qrAllPages);
        }

        hideExtraQrSidebarLinks();
    }

    function setActiveMenu() {
        var currentPage = getCurrentPage();
        var links = getAllMenuLinks();

        links.forEach(function (link) {
            link.classList.remove("active");
        });

        links.forEach(function (link) {
            var href = (link.getAttribute("href") || "").toLowerCase();

            if (href === currentPage || href.indexOf(currentPage) !== -1) {
                link.classList.add("active");
            }
        });

        if (currentPage === "dashboard.jsp") {
            links.forEach(function (link) {
                var href = (link.getAttribute("href") || "").toLowerCase();

                if (href.indexOf("dashboard.jsp") !== -1) {
                    link.classList.add("active");
                }
            });
        }

        var parentActivePages = {
            "add_department.jsp": "departments.jsp",
            "edit_department.jsp": "departments.jsp",
            "view_department.jsp": "departments.jsp",
            "export_departments_excel.jsp": "departments.jsp",
            "db_status.jsp": "settings.jsp",
            "backup_restore.jsp": "settings.jsp",
            "database_backup_export.jsp": "settings.jsp",
            "manage_roles.jsp": "settings.jsp",
            "access_matrix.jsp": "settings.jsp",
            "notification_settings.jsp": "settings.jsp",
            "notifications.jsp": "settings.jsp",
            "currency_settings.jsp": "settings.jsp",
            "alert_center.jsp": "settings.jsp",
            "overdue_actions.jsp": "settings.jsp",
            "change_password.jsp": "settings.jsp",
            "test_email.jsp": "settings.jsp",
            "view_location.jsp": "settings.jsp"
        };

        var parentHref = parentActivePages[currentPage];

        if (parentHref) {
            links.forEach(function (link) {
                var href = (link.getAttribute("href") || "").toLowerCase();

                if (href.indexOf(parentHref) !== -1) {
                    link.classList.add("active");
                }
            });
        }
        var qrPagesForActiveControl = [
            "qr_control_center.jsp",
            "qr_asset_register.jsp",
            "qr_scan_logs.jsp",
            "view_qr_scan_log.jsp",
            "qr_scan_analytics.jsp",
            "qr_coverage_report.jsp",
            "qr_missing_qr_report.jsp",
            "qr_asset_scan_history.jsp",
            "qr_ip_audit_report.jsp",
            "qr_exception_report.jsp",
            "qr_system_health.jsp",
            "qr_url_refresh.jsp",
            "qr_token_lookup.jsp",
            "qr_token_reissue.jsp",
            "qr_reissue_history.jsp",
            "qr_tagging_status.jsp",
            "qr_tagging_work_order.jsp",
            "qr_bulk_generate.jsp",
            "qr_print.jsp",
            "qr_print_labels.jsp",
            "export_qr_scan_analytics_excel.jsp",
            "export_qr_coverage_report_excel.jsp",
            "export_qr_missing_qr_excel.jsp",
            "export_qr_asset_scan_history_excel.jsp",
            "export_qr_ip_audit_excel.jsp",
            "export_qr_tagging_status_excel.jsp",
            "export_qr_exception_report_excel.jsp",
            "export_qr_reissue_history_excel.jsp"
        ];

        if (qrPagesForActiveControl.indexOf(currentPage) !== -1) {
            links.forEach(function (link) {
                var href = (link.getAttribute("href") || "").toLowerCase();

                if (href.indexOf("qr_control_center.jsp") !== -1) {
                    link.classList.add("active");
                }
            });
        }
    }

    function protectDirectAccess() {
        var role = getUserRole();
        var currentPage = getCurrentPage();

        var blockedPages = [];

        if (role === "DEPARTMENT_HEAD") {
            blockedPages = [
                "add_department.jsp",
                "edit_department.jsp",
                "add_asset.jsp",
                "vendors.jsp",
                "category_vendor_mapping.jsp",
                "categories.jsp",
                "allocation.jsp",
                "returns.jsp",
                "maintenance.jsp",
                "physical_verification.jsp",
                "reports.jsp",
                "analytics.jsp",
                "asset_health.jsp",
                "warranty_report.jsp",
                "settings.jsp",
                "audit_logs.jsp"
            ].concat(qrAllPages);
        }

        if (role === "AUDITOR") {
            blockedPages = [
                "add_department.jsp",
                "edit_department.jsp",
                "add_asset.jsp",
                "add_employee.jsp",
                "employees.jsp",
                "vendors.jsp",
                "category_vendor_mapping.jsp",
                "categories.jsp",
                "asset_requests.jsp",
                "allocation.jsp",
                "returns.jsp",
                "settings.jsp"
            ].concat(qrManagePages);
        }

        if (role === "EMPLOYEE") {
            blockedPages = [
                "departments.jsp",
                "add_department.jsp",
                "edit_department.jsp",
                "view_department.jsp",
                "export_departments_excel.jsp",
                "assets.jsp",
                "view_asset.jsp",
                "asset_documents.jsp",
                "add_asset.jsp",
                "add_employee.jsp",
                "employees.jsp",
                "vendors.jsp",
                "category_vendor_mapping.jsp",
                "categories.jsp",
                "asset_requests.jsp",
                "allocation.jsp",
                "returns.jsp",
                "maintenance.jsp",
                "physical_verification.jsp",
                "reports.jsp",
                "analytics.jsp",
                "settings.jsp",
                "audit_logs.jsp"
            ].concat(qrAllPages);
        }

        if (blockedPages.indexOf(currentPage) !== -1) {
            window.location.href = "dashboard.jsp?access=denied";
        }
    }

    function preserveSidebarScroll() {
        var key = "irams_sidebar_scroll_position_v5";

        var scrollTargets = [];

        [
            ".railway-sidebar",
            ".rail-sidebar",
            ".sidebar",
            ".rail-menu",
            ".menu"
        ].forEach(function (selector) {
            document.querySelectorAll(selector).forEach(function (item) {
                if (item && scrollTargets.indexOf(item) === -1) {
                    scrollTargets.push(item);
                }
            });
        });

        if (scrollTargets.length === 0) {
            return;
        }

        function isScrollable(element) {
            if (!element) {
                return false;
            }
            return element.scrollHeight > element.clientHeight + 8;
        }

        function getPrimaryScrollableTarget() {
            for (var i = 0; i < scrollTargets.length; i++) {
                if (isScrollable(scrollTargets[i])) {
                    return scrollTargets[i];
                }
            }
            return scrollTargets[0];
        }

        function saveScrollPosition() {
            var target = getPrimaryScrollableTarget();
            var value = target && typeof target.scrollTop === "number" ? target.scrollTop : 0;
            sessionStorage.setItem(key, String(value));
        }

        function restoreSavedScrollPosition() {
            var savedScroll = sessionStorage.getItem(key);
            if (savedScroll === null || savedScroll === "") {
                return false;
            }

            var value = parseInt(savedScroll, 10);
            if (isNaN(value)) {
                return false;
            }

            scrollTargets.forEach(function (target) {
                try {
                    target.scrollTop = value;
                } catch (ignore) {}
            });

            return true;
        }

        function findActiveLink() {
            var links = getAllMenuLinks();
            for (var i = 0; i < links.length; i++) {
                if (links[i].classList.contains("active")) {
                    return links[i];
                }
            }
            return null;
        }

        function keepActiveLinkVisible() {
            var activeLink = findActiveLink();
            if (!activeLink) {
                return;
            }

            var target = getPrimaryScrollableTarget();
            if (!target || !isScrollable(target)) {
                return;
            }

            var targetRect = target.getBoundingClientRect();
            var linkRect = activeLink.getBoundingClientRect();

            var linkAbove = linkRect.top < targetRect.top + 18;
            var linkBelow = linkRect.bottom > targetRect.bottom - 18;

            if (linkAbove || linkBelow) {
                var desiredTop = target.scrollTop
                        + (linkRect.top - targetRect.top)
                        - (target.clientHeight / 2)
                        + (activeLink.offsetHeight / 2);

                if (desiredTop < 0) {
                    desiredTop = 0;
                }

                try {
                    target.scrollTop = desiredTop;
                    sessionStorage.setItem(key, String(target.scrollTop || desiredTop));
                } catch (ignore) {}
            }
        }

        function restoreThenKeepActive() {
            var restored = restoreSavedScrollPosition();
            if (!restored) {
                keepActiveLinkVisible();
            } else {
                setTimeout(keepActiveLinkVisible, 40);
            }
        }

        restoreThenKeepActive();
        setTimeout(restoreThenKeepActive, 60);
        setTimeout(restoreThenKeepActive, 180);
        setTimeout(restoreThenKeepActive, 450);
        setTimeout(restoreThenKeepActive, 900);

        scrollTargets.forEach(function (target) {
            target.addEventListener("scroll", saveScrollPosition, { passive: true });
        });

        getAllMenuLinks().forEach(function (link) {
            link.addEventListener("mousedown", saveScrollPosition);
            link.addEventListener("click", saveScrollPosition);
        });

        window.addEventListener("beforeunload", saveScrollPosition);
        document.addEventListener("visibilitychange", function () {
            if (document.visibilityState === "hidden") {
                saveScrollPosition();
            }
        });
    }

    function initializeSidebar() {
        injectSidebarQrLinks();
        applyRoleAccess();
        setActiveMenu();
        protectDirectAccess();
        preserveSidebarScroll();
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", initializeSidebar);
    } else {
        initializeSidebar();
    }

})();
