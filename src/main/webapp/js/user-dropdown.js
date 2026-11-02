(function () {
    "use strict";

    function getProfileBox() {
        return document.querySelector(".top-profile")
                || document.querySelector(".user-card")
                || document.querySelector(".profile-box")
                || document.querySelector(".user-profile");
    }

    function getUserName() {
        var el = document.querySelector(".top-profile strong")
                || document.querySelector(".user-card strong")
                || document.querySelector(".rail-user-main strong")
                || document.querySelector(".profile-box strong")
                || document.querySelector(".user-profile strong");

        if (!el) {
            return "User";
        }

        return el.textContent.trim() || "User";
    }

    function getUserRole() {
        var dataRoleEl = document.querySelector(".railway-sidebar[data-user-role]")
                || document.querySelector(".sidebar[data-user-role]")
                || document.body;
        var dataRole = dataRoleEl ? (dataRoleEl.getAttribute("data-user-role") || "") : "";

        if (dataRole) {
            return dataRole.replace(/_/g, " ").toLowerCase().replace(/\b\w/g, function (c) {
                return c.toUpperCase();
            });
        }

        var el = document.querySelector(".top-profile span")
                || document.querySelector(".user-card span")
                || document.querySelector(".rail-user-main span")
                || document.querySelector(".profile-box span")
                || document.querySelector(".user-profile span");

        if (!el) {
            return "IR-AMS User";
        }

        return el.textContent.trim() || "IR-AMS User";
    }

    function normalizeRole(role) {
        return (role || "").toString().trim().toUpperCase().replace(/\s+/g, "_");
    }

    function escapeHtml(value) {
        return (value || "")
                .toString()
                .replace(/&/g, "&amp;")
                .replace(/</g, "&lt;")
                .replace(/>/g, "&gt;")
                .replace(/"/g, "&quot;")
                .replace(/'/g, "&#39;");
    }

    function injectStyle() {
        if (document.getElementById("iramsUserDropdownStyle")) {
            return;
        }

        var style = document.createElement("style");
        style.id = "iramsUserDropdownStyle";

        style.innerHTML = `
            .irams-user-dropdown {
                position: fixed;
                width: 285px;
                background: rgba(255, 255, 255, 0.98);
                border: 1px solid #dbe6f3;
                border-radius: 16px;
                box-shadow: 0 20px 48px rgba(15, 42, 95, 0.18);
                z-index: 9998;
                padding: 12px;
                display: none;
            }

            .irams-user-dropdown.active {
                display: block;
            }

            .irams-user-head {
                padding: 12px;
                border-radius: 13px;
                background: linear-gradient(135deg, #eef5ff, #ffffff);
                border: 1px solid #dce7f4;
                display: grid;
                grid-template-columns: 46px 1fr;
                gap: 12px;
                align-items: center;
                margin-bottom: 10px;
            }

            .irams-user-avatar {
                width: 46px;
                height: 46px;
                border-radius: 50%;
                background: linear-gradient(135deg, #06357d, #0b55bd);
                color: #ffffff;
                display: flex;
                align-items: center;
                justify-content: center;
                font-weight: 950;
                font-size: 18px;
                box-shadow: 0 10px 20px rgba(11, 85, 189, 0.22);
            }

            .irams-user-head strong {
                display: block;
                color: #082b70;
                font-size: 14px;
                font-weight: 950;
                margin-bottom: 3px;
            }

            .irams-user-head span {
                display: block;
                color: #526b91;
                font-size: 12px;
                font-weight: 800;
            }

            .irams-dropdown-item {
                display: flex;
                align-items: center;
                gap: 11px;
                min-height: 42px;
                padding: 10px 11px;
                border-radius: 11px;
                color: #0b347c;
                font-size: 13px;
                font-weight: 850;
                cursor: pointer;
                transition: 0.16s ease;
                border: 1px solid transparent;
            }

            .irams-dropdown-item:hover {
                background: #eef5ff;
                border-color: #d6e7ff;
            }

            .irams-dropdown-item i {
                width: 18px;
                color: #0b55bd;
                text-align: center;
            }

            .irams-dropdown-divider {
                height: 1px;
                background: #e5edf7;
                margin: 8px 0;
            }

            .irams-dropdown-item.logout {
                color: #b91c1c;
            }

            .irams-dropdown-item.logout i {
                color: #dc2626;
            }

            .irams-unit-note {
                margin-top: 9px;
                padding: 10px 11px;
                border-radius: 11px;
                background: #f8fbff;
                border: 1px solid #e1ebf6;
                color: #526b91;
                font-size: 11px;
                line-height: 1.45;
                font-weight: 750;
            }

            .irams-unit-note strong {
                color: #082b70;
                font-weight: 950;
            }
        `;

        document.head.appendChild(style);
    }

    function createDropdown() {
        var existing = document.getElementById("iramsUserDropdown");

        if (existing) {
            return existing;
        }

        var username = getUserName();
        var role = getUserRole();
        var roleKey = normalizeRole(role);
        var initial = username.substring(0, 1).toUpperCase();
        var canOpenSettings = roleKey === "SUPER_ADMIN" || roleKey === "ADMIN";
        var canOpenAudit = roleKey === "SUPER_ADMIN" || roleKey === "ADMIN" || roleKey === "ASSET_MANAGER" || roleKey === "AUDITOR";
        var canOpenReports = roleKey === "SUPER_ADMIN" || roleKey === "ADMIN" || roleKey === "ASSET_MANAGER" || roleKey === "AUDITOR";

        var dropdown = document.createElement("div");
        dropdown.id = "iramsUserDropdown";
        dropdown.className = "irams-user-dropdown";

        dropdown.innerHTML = `
            <div class="irams-user-head">
                <div class="irams-user-avatar">${escapeHtml(initial)}</div>
                <div>
                    <strong>${escapeHtml(username)}</strong>
                    <span>${escapeHtml(role)}</span>
                </div>
            </div>

            <div class="irams-dropdown-item" data-url="dashboard.jsp">
                <i class="fa-solid fa-gauge-high"></i>
                Dashboard
            </div>

            ${canOpenSettings ? `<div class="irams-dropdown-item" data-url="settings.jsp">
                <i class="fa-solid fa-gear"></i>
                System Administration
            </div>` : ``}

            ${canOpenAudit ? `<div class="irams-dropdown-item" data-url="audit_logs.jsp">
                <i class="fa-solid fa-shield-halved"></i>
                Audit Trail
            </div>` : ``}

            ${canOpenReports ? `<div class="irams-dropdown-item" data-url="reports.jsp">
                <i class="fa-solid fa-chart-pie"></i>
                Reports
            </div>` : ``}

            <div class="irams-dropdown-divider"></div>

            <div class="irams-dropdown-item logout" data-url="logout.jsp">
                <i class="fa-solid fa-right-from-bracket"></i>
                Logout
            </div>

            <div class="irams-unit-note">
                <strong>IR-AMS Session</strong><br>
                Railway Asset Management System access is controlled by assigned role permissions.
            </div>
        `;

        document.body.appendChild(dropdown);

        var items = dropdown.querySelectorAll(".irams-dropdown-item");

        items.forEach(function (item) {
            item.addEventListener("click", function () {
                var url = item.getAttribute("data-url");

                if (url) {
                    window.location.href = url;
                }
            });
        });

        return dropdown;
    }

    function positionDropdown(profileBox, dropdown) {
        var rect = profileBox.getBoundingClientRect();
        var dropdownWidth = 285;

        var left = rect.right - dropdownWidth;
        var top = rect.bottom + 10;

        if (left < 12) {
            left = 12;
        }

        if (left + dropdownWidth > window.innerWidth - 12) {
            left = window.innerWidth - dropdownWidth - 12;
        }

        dropdown.style.left = left + "px";
        dropdown.style.top = top + "px";
    }

    function closeDropdown(dropdown) {
        dropdown.classList.remove("active");
    }

    function toggleDropdown(profileBox, dropdown) {
        positionDropdown(profileBox, dropdown);
        dropdown.classList.toggle("active");
    }

    function initializeDropdown() {
        var profileBox = getProfileBox();

        if (!profileBox) {
            return;
        }

        injectStyle();

        var dropdown = createDropdown();

        profileBox.style.cursor = "pointer";

        profileBox.addEventListener("click", function (event) {
            event.stopPropagation();
            toggleDropdown(profileBox, dropdown);
        });

        document.addEventListener("click", function (event) {
            if (!dropdown.contains(event.target) && !profileBox.contains(event.target)) {
                closeDropdown(dropdown);
            }
        });

        window.addEventListener("resize", function () {
            if (dropdown.classList.contains("active")) {
                positionDropdown(profileBox, dropdown);
            }
        });

        window.addEventListener("scroll", function () {
            if (dropdown.classList.contains("active")) {
                positionDropdown(profileBox, dropdown);
            }
        }, true);

        document.addEventListener("keydown", function (event) {
            if (event.key === "Escape") {
                closeDropdown(dropdown);
            }
        });
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", initializeDropdown);
    } else {
        initializeDropdown();
    }

})();
