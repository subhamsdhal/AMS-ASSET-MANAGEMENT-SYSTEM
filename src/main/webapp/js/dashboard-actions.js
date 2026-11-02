(function () {
    "use strict";

    function qs(selector) {
        return document.querySelector(selector);
    }

    function qsa(selector) {
        return Array.prototype.slice.call(document.querySelectorAll(selector));
    }

    function go(url) {
        if (url && url !== "#") {
            window.location.href = url;
        }
    }

    function initializeAiCopilotShortcut() {
        var actions = qs(".topbar-actions") || qs(".top-right");

        if (!actions) {
            return;
        }

        if (actions.querySelector(".ai-copilot-topbar-btn")) {
            return;
        }

        var link = document.createElement("a");
        link.className = "top-icon-btn ai-copilot-topbar-btn";
        link.href = "ams_copilot.jsp";
        link.setAttribute("aria-label", "AI Copilot");
        link.setAttribute("title", "Open AI Copilot");
        link.innerHTML = "<i class=\"fa-solid fa-robot\"></i><span class=\"ai-pulse-dot\" aria-hidden=\"true\"></span>";

        var help = actions.querySelector("a[href='dashboard_help.jsp']");
        var userCard = actions.querySelector(".user-card");

        actions.insertBefore(link, help || userCard || null);
    }

    function getDashboardRole() {
        var dataRoleElement = qs(".railway-sidebar[data-user-role]") || qs(".sidebar[data-user-role]") || document.body;
        var roleText = dataRoleElement
            ? normalizeRoleName(dataRoleElement.getAttribute("data-user-role") || dataRoleElement.getAttribute("data-current-role") || "")
            : "";

        if (!roleText) {
            var roleElement = qs(".user-card span") || qs(".rail-user-main span") || qs(".profile-role");

            if (roleElement) {
                roleText = normalizeRoleName(roleElement.textContent || "");
            }
        }

        if (roleText.indexOf("SUPER ADMIN") !== -1) {
            return "SUPER_ADMIN";
        }

        if (roleText === "ADMIN") {
            return "ADMIN";
        }

        if (roleText.indexOf("ASSET MANAGER") !== -1) {
            return "ASSET_MANAGER";
        }

        if (roleText.indexOf("DEPARTMENT HEAD") !== -1) {
            return "DEPARTMENT_HEAD";
        }

        if (roleText.indexOf("AUDITOR") !== -1) {
            return "AUDITOR";
        }

        if (roleText.indexOf("EMPLOYEE") !== -1) {
            return "EMPLOYEE";
        }

        return "";
    }

    function normalizeRoleName(text) {
        return (text || "")
            .toString()
            .replace(/_/g, " ")
            .replace(/\s+/g, " ")
            .trim()
            .toUpperCase();
    }

    function isDashboardMenuItemAllowed(role, url) {
        if (role === "SUPER_ADMIN" || role === "ADMIN") {
            return true;
        }

        if (url === "settings.jsp" || url === "backup_restore.jsp" || url === "db_status.jsp") {
            return false;
        }

        if (url === "notifications.jsp" || url === "alert_center.jsp" || url === "overdue_actions.jsp") {
            return false;
        }

        if (role === "ASSET_MANAGER") {
            return [
                "category_vendor_mapping.jsp",
                "categories.jsp",
                "reports.jsp",
                "audit_logs.jsp",
                "asset_requests.jsp"
            ].indexOf(url) !== -1;
        }

        if (role === "DEPARTMENT_HEAD") {
            // Was just ["asset_requests.jsp"] - but neither menuItems() list
            // (below) had an entry with that URL, so this role's dropdown was
            // guaranteed to render completely empty (every candidate item got
            // filtered out) no matter which of the two buttons was clicked.
            // Added "asset_requests.jsp" as an actual menu item below to match
            // what this whitelist already expected to exist, and added
            // "reports.jsp" since RoleAccessUtil.java already grants
            // DEPARTMENT_HEAD access to reports.jsp - this JS copy just didn't
            // know that. See CHANGELOG-fixes.md (Dashboard module).
            return [
                "asset_requests.jsp",
                "reports.jsp"
            ].indexOf(url) !== -1;
        }

        if (role === "AUDITOR") {
            return [
                "audit_logs.jsp",
                "reports.jsp"
            ].indexOf(url) !== -1;
        }

        if (role === "EMPLOYEE") {
            return [
                "add_request.jsp"
            ].indexOf(url) !== -1;
        }

        return false;
    }

    function ensureDropdown() {
        var menu = document.getElementById("dashboardActionMenu");

        if (menu) {
            return menu;
        }

        menu = document.createElement("div");
        menu.id = "dashboardActionMenu";
        menu.className = "dashboard-action-menu";
        document.body.appendChild(menu);

        return menu;
    }

    function closeDropdown() {
        var menu = document.getElementById("dashboardActionMenu");

        if (menu) {
            menu.classList.remove("active");
            menu.innerHTML = "";
        }
    }

    function menuItems(type) {
        var role = getDashboardRole();
        var items;

        if (type === "hq") {
            items = [
                {
                    icon: "fa-bell",
                    title: "Notifications",
                    subtitle: "Open live alert notifications",
                    url: "notifications.jsp"
                },
                {
                    icon: "fa-triangle-exclamation",
                    title: "Alert Center",
                    subtitle: "Open consolidated alert dashboard",
                    url: "alert_center.jsp"
                },
                {
                    icon: "fa-location-dot",
                    title: "Railway Sections & Locations",
                    subtitle: "Open section/location master",
                    url: "category_vendor_mapping.jsp"
                },
                {
                    icon: "fa-sitemap",
                    title: "Departments & Categories",
                    subtitle: "Open department/category master",
                    url: "categories.jsp"
                },
                {
                    icon: "fa-chart-pie",
                    title: "Headquarters Reports",
                    subtitle: "Open MIS and asset reports",
                    url: "reports.jsp"
                },
                {
                    icon: "fa-gear",
                    title: "System Settings",
                    subtitle: "Open organization settings",
                    url: "settings.jsp"
                }
            ];

            return items.filter(function (item) {
                return isDashboardMenuItemAllowed(role, item.url);
            });
        }

        items = [
            {
                icon: "fa-bell",
                title: "Notifications",
                subtitle: "Open live notification center",
                url: "notifications.jsp"
            },
            {
                icon: "fa-triangle-exclamation",
                title: "Alert Center",
                subtitle: "Review risk and warning signals",
                url: "alert_center.jsp"
            },
            {
                icon: "fa-file-circle-plus",
                title: "Asset Requests",
                subtitle: "Review and approve pending requests",
                url: "asset_requests.jsp"
            },
            {
                icon: "fa-calendar-check",
                title: "Overdue Actions",
                subtitle: "Returns, maintenance and warranty due",
                url: "overdue_actions.jsp"
            },
            {
                icon: "fa-database",
                title: "Database Status",
                subtitle: "Check live database connection",
                url: "db_status.jsp"
            },
            {
                icon: "fa-shield-halved",
                title: "Audit Trail",
                subtitle: "Review system activity logs",
                url: "audit_logs.jsp"
            },
            {
                icon: "fa-file-arrow-down",
                title: "Backup & Restore",
                subtitle: "Open backup and restore console",
                url: "backup_restore.jsp"
            },
            {
                icon: "fa-gear",
                title: "Administration Settings",
                subtitle: "Open control configuration",
                url: "settings.jsp"
            }
        ];

        return items.filter(function (item) {
            return isDashboardMenuItemAllowed(role, item.url);
        });
    }

    function positionMenu(trigger, menu) {
        var rect = trigger.getBoundingClientRect();
        var width = 326;
        var left = rect.left;
        var top = rect.bottom + 10;

        if (left + width > window.innerWidth - 12) {
            left = window.innerWidth - width - 12;
        }

        if (left < 12) {
            left = 12;
        }

        menu.style.left = left + "px";
        menu.style.top = top + "px";
        menu.style.width = width + "px";
    }

    function openDashboardMenu(trigger, type) {
        var menu = ensureDropdown();
        var items = menuItems(type);

        // Defensive fallback: if a role's allow-list (isDashboardMenuItemAllowed)
        // ever filters every candidate item out - as DEPARTMENT_HEAD's did until
        // this fix - show an explicit "nothing here" state instead of an empty
        // floating box with zero visible content, which reads as broken rather
        // than as "no items for your role."
        if (items.length === 0) {
            menu.innerHTML = ""
                + "<div class=\"dashboard-action-menu-empty\">"
                + "  <i class=\"fa-regular fa-circle-question\"></i>"
                + "  <span>No quick actions available for your role.</span>"
                + "</div>";
            positionMenu(trigger, menu);
            menu.classList.add("active");
            return;
        }

        menu.innerHTML = items.map(function (item) {
            return ""
                + "<button type=\"button\" class=\"dashboard-action-menu-item\" data-url=\"" + item.url + "\">"
                + "  <span class=\"dashboard-action-menu-icon\"><i class=\"fa-solid " + item.icon + "\"></i></span>"
                + "  <span class=\"dashboard-action-menu-text\">"
                + "      <strong>" + item.title + "</strong>"
                + "      <small>" + item.subtitle + "</small>"
                + "  </span>"
                + "</button>";
        }).join("");

        qsa(".dashboard-action-menu-item").forEach(function (item) {
            item.addEventListener("click", function () {
                go(item.getAttribute("data-url"));
            });
        });

        positionMenu(trigger, menu);
        menu.classList.add("active");
    }

    function initializeDropdownTriggers() {
        qsa("[data-dashboard-menu]").forEach(function (trigger) {
            trigger.addEventListener("click", function (event) {
                event.preventDefault();
                event.stopPropagation();

                var menu = ensureDropdown();
                var type = trigger.getAttribute("data-dashboard-menu");

                if (menu.classList.contains("active") && menu.getAttribute("data-current") === type) {
                    closeDropdown();
                    return;
                }

                menu.setAttribute("data-current", type);
                openDashboardMenu(trigger, type);
            });
        });

        document.addEventListener("click", function (event) {
            var menu = document.getElementById("dashboardActionMenu");

            if (!menu) {
                return;
            }

            if (!menu.contains(event.target) && !event.target.closest("[data-dashboard-menu]")) {
                closeDropdown();
            }
        });

        document.addEventListener("keydown", function (event) {
            if (event.key === "Escape") {
                closeDropdown();
            }
        });
    }

    function initializeSidebarToggle() {
        var toggle = qs(".nav-toggle");

        if (!toggle) {
            return;
        }

        if (localStorage.getItem("iramsDashboardSidebar") === "collapsed") {
            document.body.classList.add("sidebar-collapsed");
        }

        toggle.addEventListener("click", function () {
            document.body.classList.toggle("sidebar-collapsed");

            if (document.body.classList.contains("sidebar-collapsed")) {
                localStorage.setItem("iramsDashboardSidebar", "collapsed");
            } else {
                localStorage.setItem("iramsDashboardSidebar", "expanded");
            }

            if (window.IRAMSUpdateBodyWatermark) {
                window.IRAMSUpdateBodyWatermark();
                window.setTimeout(window.IRAMSUpdateBodyWatermark, 180);
                window.setTimeout(window.IRAMSUpdateBodyWatermark, 420);
            }
        });
    }

    function initializeSearchIcon() {
        var input = qs("#globalSearch");
        var icon = qs(".search-box i");

        if (!input || !icon) {
            return;
        }

        icon.style.cursor = "pointer";
        icon.setAttribute("title", "Search");

        icon.addEventListener("click", function () {
            var value = input.value.trim();

            if (value.length > 0) {
                go("global_search.jsp?q=" + encodeURIComponent(value));
            } else {
                input.focus();
            }
        });
    }

    function initializeTopbarQuickIcons() {
        qsa(".top-icon-btn").forEach(function (button) {
            var bell = button.querySelector(".fa-bell");
            var envelope = button.querySelector(".fa-envelope");
            var help = button.querySelector(".fa-circle-question");
            var href = button.getAttribute("href") || "";

            if (bell) {
                if (!href || href === "#") {
                    button.setAttribute("href", "notifications.jsp");
                }
                if (!button.getAttribute("title")) {
                    button.setAttribute("title", "Notifications");
                }
            }

            if (envelope) {
                if (!href || href === "#") {
                    button.setAttribute("href", "warranty_report.jsp");
                }
                if (!button.getAttribute("title")) {
                    button.setAttribute("title", "Warranty Report");
                }
            }

            if (help) {
                if (!href || href === "#") {
                    button.setAttribute("href", "dashboard_help.jsp");
                }
                if (!button.getAttribute("title")) {
                    button.setAttribute("title", "Help & Support");
                }
            }
        });
    }

    function initializeKeyboardAccess() {
        qsa(".dashboard-action-link").forEach(function (item) {
            if (!item.getAttribute("tabindex")) {
                item.setAttribute("tabindex", "0");
            }
        });
    }

    function initializeDashboardActions() {
        initializeAiCopilotShortcut();
        initializeSidebarToggle();
        initializeDropdownTriggers();
        initializeSearchIcon();
        initializeTopbarQuickIcons();
        initializeKeyboardAccess();
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", initializeDashboardActions);
    } else {
        initializeDashboardActions();
    }
})();
