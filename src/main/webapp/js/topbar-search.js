(function () {
    "use strict";

    var GLOBAL_SEARCH_PAGE = "global_search.jsp";

    var modules = [
        {
            title: "Dashboard",
            subtitle: "Overall IR-AMS command dashboard",
            url: "dashboard.jsp",
            icon: "fa-house",
            keywords: "dashboard home command control summary overview railway asset management"
        },
        {
            title: "Assets",
            subtitle: "Railway asset register and asset details",
            url: "assets.jsp",
            icon: "fa-cubes",
            keywords: "asset assets register asset list railway asset item serial qr code location stock"
        },
        {
            title: "Add Asset",
            subtitle: "Register a new railway asset",
            url: "add_asset.jsp",
            icon: "fa-plus",
            keywords: "add asset new asset create asset register item purchase vendor category"
        },
        {
            title: "Allocation & Return",
            subtitle: "Issue and return assets to holders",
            url: "allocation.jsp",
            icon: "fa-arrow-right-arrow-left",
            keywords: "allocation allocate issue assigned employee asset holder return department section"
        },
        {
            title: "Holders",
            subtitle: "Employee and asset holder master",
            url: "employees.jsp",
            icon: "fa-id-card",
            keywords: "employee employees holder holders staff officer department section designation employee code"
        },
        {
            title: "Departments / Categories",
            subtitle: "Department and category master records",
            url: "categories.jsp",
            icon: "fa-sitemap",
            keywords: "department departments category categories asset category master laptop printer furniture network"
        },
        {
            title: "Sections / Locations",
            subtitle: "Railway locations, offices, sections and rooms",
            url: "category_vendor_mapping.jsp",
            icon: "fa-location-dot",
            keywords: "section sections location locations room office building rail sadan headquarters department division"
        },
        {
            title: "Maintenance & Warranty",
            subtitle: "Maintenance logs, repair records and warranty alerts",
            url: "maintenance.jsp",
            icon: "fa-screwdriver-wrench",
            keywords: "maintenance repair service log preventive corrective under maintenance warranty issue work done"
        },
        {
            title: "Physical Verification",
            subtitle: "Physical verification and stock checking register",
            url: "physical_verification.jsp",
            icon: "fa-shield-halved",
            keywords: "physical verification verify duty order officer schedule mismatch holder location not found damaged review"
        },
        {
            title: "Reports & Analytics",
            subtitle: "Reports, registers and Excel export",
            url: "reports.jsp",
            icon: "fa-chart-simple",
            keywords: "reports report excel export register analytics asset report allocation maintenance verification"
        },
        {
            title: "Warranty Report",
            subtitle: "Warranty expiry and maintenance alert report",
            url: "warranty_report.jsp",
            icon: "fa-chart-line",
            keywords: "warranty report expiry expired expiring maintenance service alert"
        },
        {
            title: "Planning & Requests",
            subtitle: "Asset demand, request and approval workflow",
            url: "asset_requests.jsp",
            icon: "fa-square-plus",
            keywords: "asset request requests demand requisition approve reject pending employee department planning"
        },
        {
            title: "Audit",
            subtitle: "System activity and audit logs",
            url: "audit_logs.jsp",
            icon: "fa-clipboard-check",
            keywords: "audit logs activity trail login delete update export history inspection"
        },
        {
            title: "QR Scan",
            subtitle: "Scan QR and verify railway asset details",
            url: "qr_scanner.jsp",
            icon: "fa-qrcode",
            keywords: "qr scanner scan barcode asset verification mobile camera qr code"
        },
        {
            title: "Vendors",
            subtitle: "Vendor and supplier master records",
            url: "vendors.jsp",
            icon: "fa-truck-field",
            keywords: "vendor vendors supplier suppliers dealer purchase contact gst"
        },
        {
            title: "System Administration",
            subtitle: "System settings and administration",
            url: "settings.jsp",
            icon: "fa-gear",
            keywords: "settings system administration admin configuration backup restore user role"
        },
        {
            title: "Help & Support",
            subtitle: "Open IR-AMS help and support page",
            url: "dashboard_help.jsp",
            icon: "fa-headset",
            keywords: "help support assistance guide manual dashboard help"
        }
    ];

    function normalize(text) {
        if (!text) {
            return "";
        }

        return text.toString().toLowerCase().replace(/\s+/g, " ").trim();
    }

    function escapeHtml(text) {
        if (text === null || text === undefined) {
            return "";
        }

        return String(text)
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;")
            .replace(/'/g, "&#39;");
    }

    function getSearchInput() {
        return document.getElementById("globalSearch")
                || document.querySelector(".search-box input")
                || document.querySelector(".top-search input")
                || document.querySelector("input[name='q']");
    }

    function getSearchBox(input) {
        if (!input) {
            return null;
        }

        return input.closest(".search-box")
                || input.closest("form")
                || input.parentElement;
    }

    function buildGlobalSearchUrl(query) {
        var q = normalize(query);

        if (!q) {
            return GLOBAL_SEARCH_PAGE;
        }

        return GLOBAL_SEARCH_PAGE + "?q=" + encodeURIComponent(q);
    }

    function openGlobalSearch(query) {
        window.location.href = buildGlobalSearchUrl(query);
    }

    function injectSearchStyles() {
        if (document.getElementById("iramsSearchStyle")) {
            return;
        }

        var style = document.createElement("style");
        style.id = "iramsSearchStyle";

        style.innerHTML = `
            .irams-search-panel {
                position: fixed;
                z-index: 99999;
                width: 460px;
                max-height: 460px;
                overflow-y: auto;
                background: rgba(255, 255, 255, 0.985);
                border: 1px solid #dbe6f3;
                border-radius: 16px;
                box-shadow: 0 20px 48px rgba(15, 42, 95, 0.20);
                padding: 10px;
                display: none;
                backdrop-filter: blur(16px);
            }

            .irams-search-panel.active {
                display: block;
            }

            .irams-search-title {
                font-size: 11px;
                text-transform: uppercase;
                color: #526b91;
                font-weight: 950;
                letter-spacing: 0.4px;
                padding: 8px 10px 9px;
                border-bottom: 1px solid #e5edf7;
                margin-bottom: 6px;
            }

            .irams-search-item {
                display: grid;
                grid-template-columns: 42px minmax(0, 1fr) auto;
                gap: 11px;
                align-items: center;
                padding: 10px;
                border-radius: 12px;
                cursor: pointer;
                transition: 0.16s ease;
                border: 1px solid transparent;
                text-decoration: none;
                color: #082b70;
            }

            .irams-search-item:hover,
            .irams-search-item.active {
                background: #eef5ff;
                border-color: #d6e7ff;
            }

            .irams-search-icon {
                width: 40px;
                height: 40px;
                border-radius: 13px;
                background: linear-gradient(135deg, #0b55bd, #073985);
                color: #ffffff;
                display: flex;
                align-items: center;
                justify-content: center;
                font-size: 15px;
                box-shadow: 0 8px 16px rgba(11, 85, 189, 0.18);
            }

            .irams-search-icon.green {
                background: linear-gradient(135deg, #078c48, #045d31);
            }

            .irams-search-content {
                min-width: 0;
            }

            .irams-search-item strong {
                display: block;
                color: #082b70;
                font-size: 13px;
                font-weight: 950;
                margin-bottom: 3px;
                white-space: nowrap;
                overflow: hidden;
                text-overflow: ellipsis;
            }

            .irams-search-item span {
                display: block;
                color: #526b91;
                font-size: 11.5px;
                font-weight: 750;
                line-height: 1.35;
                white-space: nowrap;
                overflow: hidden;
                text-overflow: ellipsis;
            }

            .irams-search-action {
                color: #08348f;
                font-size: 10.5px;
                font-weight: 950;
                white-space: nowrap;
                text-transform: uppercase;
            }

            .irams-search-empty {
                padding: 18px 12px;
                color: #526b91;
                font-size: 13px;
                font-weight: 800;
                text-align: center;
            }

            .irams-search-hint {
                margin-top: 8px;
                padding: 9px 10px;
                border-top: 1px solid #e5edf7;
                color: #607692;
                font-size: 11px;
                font-weight: 750;
                line-height: 1.45;
            }

            .irams-search-key {
                display: inline-flex;
                align-items: center;
                justify-content: center;
                min-width: 22px;
                height: 20px;
                padding: 0 6px;
                margin: 0 2px;
                border-radius: 6px;
                background: #eef5ff;
                border: 1px solid #d8e7fb;
                color: #08348f;
                font-size: 10px;
                font-weight: 950;
            }

            @media (max-width: 700px) {
                .irams-search-panel {
                    left: 12px !important;
                    right: 12px !important;
                    width: auto !important;
                    max-height: 70vh;
                }
            }
        `;

        document.head.appendChild(style);
    }

    function createPanel() {
        var existing = document.getElementById("iramsSearchPanel");

        if (existing) {
            return existing;
        }

        var panel = document.createElement("div");
        panel.id = "iramsSearchPanel";
        panel.className = "irams-search-panel";

        document.body.appendChild(panel);

        return panel;
    }

    function positionPanel(input, panel) {
        var rect = input.getBoundingClientRect();
        var windowWidth = window.innerWidth || document.documentElement.clientWidth;
        var desiredWidth = Math.max(rect.width, 460);
        var left = rect.left;

        if (left + desiredWidth > windowWidth - 16) {
            left = Math.max(12, windowWidth - desiredWidth - 16);
        }

        panel.style.left = left + "px";
        panel.style.top = (rect.bottom + 8) + "px";
        panel.style.width = desiredWidth + "px";
    }

    function findModuleMatches(query) {
        var q = normalize(query);

        if (!q) {
            return modules.slice(0, 8);
        }

        var results = [];

        modules.forEach(function (module) {
            var title = normalize(module.title);
            var subtitle = normalize(module.subtitle);
            var keywords = normalize(module.keywords);

            var score = 0;

            if (title === q) {
                score += 120;
            }

            if (title.indexOf(q) !== -1) {
                score += 70;
            }

            if (keywords.indexOf(q) !== -1) {
                score += 50;
            }

            if (subtitle.indexOf(q) !== -1) {
                score += 25;
            }

            var queryWords = q.split(" ");

            queryWords.forEach(function (word) {
                if (word.length > 1 && title.indexOf(word) !== -1) {
                    score += 14;
                }

                if (word.length > 1 && keywords.indexOf(word) !== -1) {
                    score += 10;
                }

                if (word.length > 1 && subtitle.indexOf(word) !== -1) {
                    score += 6;
                }
            });

            if (score > 0) {
                results.push({
                    module: module,
                    score: score
                });
            }
        });

        results.sort(function (a, b) {
            return b.score - a.score;
        });

        return results.slice(0, 7).map(function (item) {
            return item.module;
        });
    }

    function renderPanel(panel, input, query) {
        positionPanel(input, panel);

        var q = normalize(query);
        var matches = findModuleMatches(q);
        var html = "";

        html += `<div class="irams-search-title">IR-AMS Smart Search</div>`;

        html += `
            <div class="irams-search-item active"
                 data-url="${escapeHtml(buildGlobalSearchUrl(q))}">
                <div class="irams-search-icon green">
                    <i class="fa-solid fa-magnifying-glass"></i>
                </div>
                <div class="irams-search-content">
                    <strong>${q ? "Search database for \"" + escapeHtml(q) + "\"" : "Open Global Search"}</strong>
                    <span>Search assets, holders, departments, locations, vendors, allocation, maintenance, requests, verification and audit.</span>
                </div>
                <div class="irams-search-action">Search</div>
            </div>
        `;

        if (matches && matches.length > 0) {
            html += `<div class="irams-search-title">Quick Module Shortcuts</div>`;

            matches.forEach(function (module) {
                html += `
                    <div class="irams-search-item"
                         data-url="${escapeHtml(module.url)}">
                        <div class="irams-search-icon">
                            <i class="fa-solid ${escapeHtml(module.icon)}"></i>
                        </div>
                        <div class="irams-search-content">
                            <strong>${escapeHtml(module.title)}</strong>
                            <span>${escapeHtml(module.subtitle)}</span>
                        </div>
                        <div class="irams-search-action">Open</div>
                    </div>
                `;
            });
        }

        if (!matches || matches.length === 0) {
            html += `
                <div class="irams-search-empty">
                    No matching shortcut found.<br>
                    Press Enter to search the database.
                </div>
            `;
        }

        html += `
            <div class="irams-search-hint">
                Press <span class="irams-search-key">Enter</span> to search records.
                Use <span class="irams-search-key">↑</span> <span class="irams-search-key">↓</span> for shortcuts.
                Press <span class="irams-search-key">Ctrl</span> + <span class="irams-search-key">K</span> to focus search.
            </div>
        `;

        panel.innerHTML = html;
        panel.classList.add("active");

        bindPanelItems(panel);
    }

    function bindPanelItems(panel) {
        var items = panel.querySelectorAll(".irams-search-item");

        items.forEach(function (item) {
            item.addEventListener("click", function () {
                var url = item.getAttribute("data-url");

                if (url) {
                    window.location.href = url;
                }
            });
        });
    }

    function hidePanel(panel) {
        if (panel) {
            panel.classList.remove("active");
        }
    }

    function openActiveResult(panel) {
        if (!panel) {
            return false;
        }

        var active = panel.querySelector(".irams-search-item.active")
                || panel.querySelector(".irams-search-item");

        if (!active) {
            return false;
        }

        var url = active.getAttribute("data-url");

        if (!url) {
            return false;
        }

        window.location.href = url;
        return true;
    }

    function moveActive(panel, direction) {
        if (!panel) {
            return;
        }

        var items = Array.prototype.slice.call(panel.querySelectorAll(".irams-search-item"));

        if (items.length === 0) {
            return;
        }

        var currentIndex = items.findIndex(function (item) {
            return item.classList.contains("active");
        });

        if (currentIndex === -1) {
            currentIndex = 0;
        } else {
            items[currentIndex].classList.remove("active");
            currentIndex += direction;
        }

        if (currentIndex < 0) {
            currentIndex = items.length - 1;
        }

        if (currentIndex >= items.length) {
            currentIndex = 0;
        }

        items[currentIndex].classList.add("active");

        if (typeof items[currentIndex].scrollIntoView === "function") {
            items[currentIndex].scrollIntoView({
                block: "nearest"
            });
        }
    }

    function makeSearchIconClickable(input, panel) {
        var box = getSearchBox(input);

        if (!box) {
            return;
        }

        var icon = box.querySelector(".fa-magnifying-glass");

        if (!icon) {
            return;
        }

        icon.style.cursor = "pointer";

        icon.addEventListener("click", function (event) {
            event.preventDefault();
            event.stopPropagation();

            openGlobalSearch(input.value);
        });
    }

    function bindFormSubmit(input) {
        var form = input.closest("form");

        if (!form) {
            return;
        }

        form.addEventListener("submit", function (event) {
            event.preventDefault();
            openGlobalSearch(input.value);
        });
    }

    function initializeSearch() {
        var input = getSearchInput();

        if (!input) {
            return;
        }

        injectSearchStyles();

        var panel = createPanel();

        input.setAttribute("autocomplete", "off");

        input.addEventListener("focus", function () {
            renderPanel(panel, input, input.value);
        });

        input.addEventListener("input", function () {
            renderPanel(panel, input, input.value);
        });

        input.addEventListener("keydown", function (event) {
            if (event.key === "Enter") {
                event.preventDefault();

                if (!panel.classList.contains("active")) {
                    openGlobalSearch(input.value);
                    return;
                }

                openActiveResult(panel);
                return;
            }

            if (event.key === "ArrowDown") {
                event.preventDefault();
                moveActive(panel, 1);
                return;
            }

            if (event.key === "ArrowUp") {
                event.preventDefault();
                moveActive(panel, -1);
                return;
            }

            if (event.key === "Escape") {
                hidePanel(panel);
                input.blur();
            }
        });

        makeSearchIconClickable(input, panel);
        bindFormSubmit(input);

        window.addEventListener("resize", function () {
            if (panel.classList.contains("active")) {
                positionPanel(input, panel);
            }
        });

        window.addEventListener("scroll", function () {
            if (panel.classList.contains("active")) {
                positionPanel(input, panel);
            }
        }, true);

        document.addEventListener("click", function (event) {
            var clickedInsideInput = input.contains(event.target);
            var clickedInsidePanel = panel.contains(event.target);
            var searchBox = getSearchBox(input);
            var clickedInsideSearchBox = searchBox && searchBox.contains(event.target);

            if (!clickedInsideInput && !clickedInsidePanel && !clickedInsideSearchBox) {
                hidePanel(panel);
            }
        });

        document.addEventListener("keydown", function (event) {
            var key = event.key ? event.key.toLowerCase() : "";

            if ((event.ctrlKey || event.metaKey) && key === "k") {
                event.preventDefault();
                input.focus();
                input.select();
                renderPanel(panel, input, input.value);
            }
        });
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", initializeSearch);
    } else {
        initializeSearch();
    }

})();