document.addEventListener("DOMContentLoaded", function () {
    const today = getTodayIsoDate();

    const pastOrTodayRules = [
        "joiningdate", "joining_date",
        "purchasedate", "purchase_date",
        "allocationdate", "allocation_date",
        "returndate", "return_date",
        "disposaldate", "disposal_date",
        "maintenancedate", "maintenance_date",
        "servicedate", "service_date",
        "performeddate", "performed_date",
        "requestdate", "request_date",
        "issuedate", "issue_date",
        "fromdate", "from_date",
        "todate", "to_date",
        "startdate", "start_date",
        "enddate", "end_date",
        "filterdate", "reportdate", "auditdate"
    ];

    const futureAllowedRules = [
        "warrantyexpiry", "warranty_expiry",
        "nextservicedate", "next_service_date",
        "nextmaintenancedate",
        "scheduleddate", "scheduled_date",
        "duedate", "due_date",
        "targetdate", "target_date"
    ];

    function initDatePickersAndRules(rootNode) {
        if (!rootNode || !rootNode.querySelectorAll) return;

        const dateInputs = rootNode.querySelectorAll('input[type="date"]');
        
        dateInputs.forEach(function (input) {
            if (input.getAttribute("data-date-picker-ready") === "true") {
                return;
            }
            input.setAttribute("data-date-picker-ready", "true");

            // Set up wrapper click for calendar icon
            const wrapper = input.closest('.form-group, .add-form-group, .date-field, .date-wrapper, .date-input-wrap, .input-icon-wrap');
            if (wrapper) {
                wrapper.classList.add('date-picker-ready');
                wrapper.addEventListener('click', function (e) {
                    if (e.target !== input) {
                        try {
                            if (typeof input.showPicker === 'function') {
                                input.showPicker();
                            } else {
                                input.focus();
                                input.click();
                            }
                        } catch (error) {
                            input.focus();
                        }
                    }
                });
            }
            
            input.addEventListener('click', function(e) {
                try {
                    if (typeof input.showPicker === 'function') {
                        input.showPicker();
                    }
                } catch (error) {}
            });

            const fieldKey = normalizeFieldKey(input.name || input.id || "");

            if (isFutureAllowed(fieldKey)) {
                // skip setting max=today
            } else if (isPastOrTodayField(fieldKey)) {
                input.max = today;
                input.addEventListener("change", function () {
                    validatePastOrTodayInput(input);
                });
            }
        });

        setupDateRelationshipRules(rootNode);
    }

    // Run initially on DOMContentLoaded
    initDatePickersAndRules(document);

    // Watch for dynamically added forms/inputs
    const observer = new MutationObserver(function(mutations) {
        mutations.forEach(function(mutation) {
            mutation.addedNodes.forEach(function(node) {
                if (node.nodeType === 1) { // ELEMENT_NODE
                    if (node.tagName === "INPUT" && node.type === "date") {
                        initDatePickersAndRules(node.parentNode);
                    } else if (node.querySelectorAll) {
                        if (node.querySelectorAll('input[type="date"]').length > 0) {
                            initDatePickersAndRules(node);
                        }
                    }
                }
            });
        });
    });

    observer.observe(document.body, { childList: true, subtree: true });

    document.querySelectorAll("form").forEach(function (form) {
        if(form.dataset.dateRulesBound) return;
        form.dataset.dateRulesBound = "true";

        form.addEventListener("submit", function (event) {
            let isValid = true;
            let errorMessage = "";

            const allDateInputs = form.querySelectorAll('input[type="date"]');
            
            allDateInputs.forEach(function (input) {
                const fieldKey = normalizeFieldKey(input.name || input.id || "");
                if (!isFutureAllowed(fieldKey) && isPastOrTodayField(fieldKey)) {
                    if (!validatePastOrTodayInput(input)) {
                        isValid = false;
                        errorMessage += "Future dates are not allowed for " + (input.name || input.id) + ".\n";
                    }
                }
            });

            const relationshipCheck = validateRelationshipRules(form);
            if (!relationshipCheck.valid) {
                isValid = false;
                errorMessage += relationshipCheck.message + "\n";
            }

            if (!isValid) {
                event.preventDefault();
                alert("Please correct the following date errors:\n\n" + errorMessage);
            }
        });
    });

    // We also need to watch for dynamically added forms
    const formObserver = new MutationObserver(function(mutations) {
        mutations.forEach(function(mutation) {
            mutation.addedNodes.forEach(function(node) {
                if (node.nodeType === 1) {
                    const forms = node.tagName === "FORM" ? [node] : node.querySelectorAll("form");
                    forms.forEach(function(form) {
                        if(form.dataset.dateRulesBound) return;
                        form.dataset.dateRulesBound = "true";
                        form.addEventListener("submit", function(event) {
                            let isValid = true;
                            let errorMessage = "";
                            const allDateInputs = form.querySelectorAll('input[type="date"]');
                            allDateInputs.forEach(function (input) {
                                const fieldKey = normalizeFieldKey(input.name || input.id || "");
                                if (!isFutureAllowed(fieldKey) && isPastOrTodayField(fieldKey)) {
                                    if (!validatePastOrTodayInput(input)) {
                                        isValid = false;
                                        errorMessage += "Future dates are not allowed for " + (input.name || input.id) + ".\n";
                                    }
                                }
                            });
                            const relationshipCheck = validateRelationshipRules(form);
                            if (!relationshipCheck.valid) {
                                isValid = false;
                                errorMessage += relationshipCheck.message + "\n";
                            }
                            if (!isValid) {
                                event.preventDefault();
                                alert("Please correct the following date errors:\n\n" + errorMessage);
                            }
                        });
                    });
                }
            });
        });
    });
    formObserver.observe(document.body, { childList: true, subtree: true });

    function getTodayIsoDate() {
        const now = new Date();
        const localDate = new Date(now.getTime() - now.getTimezoneOffset() * 60000);
        return localDate.toISOString().split("T")[0];
    }

    function normalizeFieldKey(value) {
        return String(value || "")
                .toLowerCase()
                .replace(/[\s_-]/g, "");
    }

    function isPastOrTodayField(fieldKey) {
        return pastOrTodayRules.some(function (rule) {
            return fieldKey.includes(normalizeFieldKey(rule));
        });
    }

    function isFutureAllowed(fieldKey) {
        return futureAllowedRules.some(function (rule) {
            return fieldKey.includes(normalizeFieldKey(rule));
        });
    }

    function validatePastOrTodayInput(input) {
        if (!input || !input.value) return true;
        if (input.value > today) {
            input.value = "";
            input.classList.add("date-error");
            return false;
        }
        input.classList.remove("date-error");
        return true;
    }

    function setupDateRelationshipRules(rootNode) {
        const doc = rootNode || document;
        
        const purchaseDate = findDateInput(["purchaseDate", "purchase_date", "purchasedate"], doc);
        const warrantyExpiry = findDateInput(["warrantyExpiry", "warranty_expiry", "warrantyexpiry"], doc);
        if (purchaseDate && warrantyExpiry) {
            purchaseDate.addEventListener("change", function () {
                warrantyExpiry.min = purchaseDate.value || "";
                if (warrantyExpiry.value && purchaseDate.value && warrantyExpiry.value < purchaseDate.value) {
                    warrantyExpiry.value = "";
                }
            });
        }

        const allocationDate = findDateInput(["allocationDate", "allocation_date", "allocationdate"], doc);
        const returnDate = findDateInput(["returnDate", "return_date", "returndate"], doc);
        if (allocationDate && returnDate) {
            allocationDate.addEventListener("change", function () {
                returnDate.min = allocationDate.value || "";
                if (returnDate.value && allocationDate.value && returnDate.value < allocationDate.value) {
                    returnDate.value = "";
                }
            });
        }
        
        const disposalDate = findDateInput(["disposalDate", "disposal_date", "disposaldate"], doc);
        if (purchaseDate && disposalDate) {
            purchaseDate.addEventListener("change", function () {
                disposalDate.min = purchaseDate.value || "";
                if (disposalDate.value && purchaseDate.value && disposalDate.value < purchaseDate.value) {
                    disposalDate.value = "";
                }
            });
        }
        
        const maintenanceDate = findDateInput(["maintenanceDate", "maintenance_date", "maintenancedate"], doc);
        const nextMaintenanceDate = findDateInput(["nextMaintenanceDate", "nextDueDate", "next_due_date"], doc);
        if(maintenanceDate && nextMaintenanceDate) {
            maintenanceDate.addEventListener("change", function() {
                nextMaintenanceDate.min = maintenanceDate.value || "";
                if (nextMaintenanceDate.value && maintenanceDate.value && nextMaintenanceDate.value <= maintenanceDate.value) {
                    nextMaintenanceDate.value = "";
                }
            });
        }
        
        const fromDate = findDateInput(["fromDate", "from_date", "fromdate", "startDate", "start_date", "startdate"], doc);
        const toDate = findDateInput(["toDate", "to_date", "todate", "endDate", "end_date", "enddate"], doc);
        if(fromDate && toDate) {
            fromDate.addEventListener("change", function() {
                toDate.min = fromDate.value || "";
                if(toDate.value && fromDate.value && toDate.value < fromDate.value) {
                    toDate.value = "";
                }
            });
        }
    }

    function validateRelationshipRules(form) {
        let isValid = true;
        let message = "";

        const purchaseDate = findDateInput(["purchaseDate", "purchase_date", "purchasedate"], form);
        const warrantyExpiry = findDateInput(["warrantyExpiry", "warranty_expiry", "warrantyexpiry"], form);
        if (purchaseDate && warrantyExpiry && purchaseDate.value && warrantyExpiry.value) {
            if (warrantyExpiry.value < purchaseDate.value) {
                isValid = false;
                message += "Warranty expiry cannot be before purchase date.\n";
            }
        }

        const allocationDate = findDateInput(["allocationDate", "allocation_date", "allocationdate"], form);
        const returnDate = findDateInput(["returnDate", "return_date", "returndate"], form);
        if (allocationDate && returnDate && allocationDate.value && returnDate.value) {
            if (returnDate.value < allocationDate.value) {
                isValid = false;
                message += "Return date cannot be before allocation date.\n";
            }
        }
        
        const disposalDate = findDateInput(["disposalDate", "disposal_date", "disposaldate"], form);
        if (purchaseDate && disposalDate && purchaseDate.value && disposalDate.value) {
            if (disposalDate.value < purchaseDate.value) {
                isValid = false;
                message += "Disposal date cannot be before purchase date.\n";
            }
        }
        
        const maintenanceDate = findDateInput(["maintenanceDate", "maintenance_date", "maintenancedate"], form);
        const nextMaintenanceDate = findDateInput(["nextMaintenanceDate", "nextDueDate", "next_due_date"], form);
        if (maintenanceDate && nextMaintenanceDate && maintenanceDate.value && nextMaintenanceDate.value) {
            if (nextMaintenanceDate.value <= maintenanceDate.value) {
                isValid = false;
                message += "Next maintenance date must be after maintenance date.\n";
            }
        }
        
        const fromDate = findDateInput(["fromDate", "from_date", "fromdate", "startDate", "start_date", "startdate"], form);
        const toDate = findDateInput(["toDate", "to_date", "todate", "endDate", "end_date", "enddate"], form);
        if (fromDate && toDate && fromDate.value && toDate.value) {
            if(toDate.value < fromDate.value) {
                isValid = false;
                message += "To date cannot be before From date.\n";
            }
        }

        return { valid: isValid, message: message };
    }

    function findDateInput(possibleNames, root) {
        const parent = root || document;
        for (let i = 0; i < possibleNames.length; i++) {
            const name = possibleNames[i];
            const input = parent.querySelector('input[type="date"][name="' + name + '"]')
                    || parent.querySelector('input[type="date"][id="' + name + '"]');
            if (input) return input;
        }
        return null;
    }
});