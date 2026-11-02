document.addEventListener("DOMContentLoaded", function () {
    const input = document.querySelector(".search-box input");

    if (!input) {
        return;
    }

    if (!window.location.pathname.includes("global_search.jsp")) {
        return;
    }

    const rows = document.querySelectorAll(".asset-table tbody tr");
    const countStrong = document.querySelector(".glass-panel .table-subtext strong");
    const title = document.querySelector(".glass-panel h2");

    function normalizeText(text) {
        return text
            .toLowerCase()
            .replace(/\s+/g, " ")
            .trim();
    }

    function applyLiveGlobalFilter() {
        const query = normalizeText(input.value);
        let visibleCount = 0;

        rows.forEach(function (row) {
            const rowText = normalizeText(row.innerText);

            if (query === "" || rowText.includes(query)) {
                row.style.display = "";
                visibleCount++;
            } else {
                row.style.display = "none";
            }
        });

        if (countStrong) {
            countStrong.innerText = visibleCount;
        }

        if (title) {
            if (query === "") {
                title.innerHTML = "Search Results";
            } else {
                title.innerHTML = 'Search Results for "' + input.value.trim() + '"';
            }
        }
    }

    input.focus();

    const valueLength = input.value.length;
    input.setSelectionRange(valueLength, valueLength);

    input.addEventListener("input", function () {
        applyLiveGlobalFilter();
    });
});