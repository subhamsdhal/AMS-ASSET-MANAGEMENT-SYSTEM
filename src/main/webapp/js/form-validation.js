document.addEventListener("DOMContentLoaded", function () {
    function initPhoneInputs(rootNode) {
        if (!rootNode || !rootNode.querySelectorAll) return;

        // Select potential phone inputs
        const phoneInputs = rootNode.querySelectorAll('input[type="tel"], input[name*="phone" i], input[name*="mobile" i], input[name*="contact" i], input[id*="phone" i], input[id*="mobile" i], input[id*="contact" i]');

        phoneInputs.forEach(function (input) {
            if (input.getAttribute("data-phone-ready") === "true") {
                return;
            }

            const name = (input.name || "").toLowerCase();
            const id = (input.id || "").toLowerCase();

            // Ignore fields intended for contact persons / names
            if (name.includes("person") || name.includes("name") || id.includes("person") || id.includes("name") || name.includes("email") || id.includes("email")) {
                return;
            }

            input.setAttribute("data-phone-ready", "true");
            input.setAttribute("maxlength", "10");
            input.setAttribute("inputmode", "numeric");
            input.setAttribute("pattern", "[0-9]{10}");
            input.setAttribute("placeholder", "Enter 10-digit phone number");

            // Live formatting on input
            input.addEventListener('input', function (e) {
                let val = e.target.value;

                // Strip all non-digit characters
                val = val.replace(/\D/g, '');

                // Handle Indian country code edge-case: If 12 digits and starts with 91, strip the 91
                if (val.length >= 12 && val.startsWith('91')) {
                    val = val.substring(2);
                }

                // Cap at 10 digits
                val = val.substring(0, 10);
                
                e.target.value = val;
            });
        });
    }

    // Run initially on DOMContentLoaded
    initPhoneInputs(document);

    // Watch for dynamically added forms/inputs
    const observer = new MutationObserver(function (mutations) {
        mutations.forEach(function (mutation) {
            mutation.addedNodes.forEach(function (node) {
                if (node.nodeType === 1) { // ELEMENT_NODE
                    if (node.tagName === "INPUT") {
                        initPhoneInputs(node.parentNode);
                    } else if (node.querySelectorAll) {
                        initPhoneInputs(node);
                    }
                }
            });
        });
    });

    observer.observe(document.body, { childList: true, subtree: true });

    // Validate on form submission
    function bindFormSubmitListeners(rootNode) {
        if (!rootNode || !rootNode.querySelectorAll) return;
        const forms = rootNode.tagName === "FORM" ? [rootNode] : rootNode.querySelectorAll("form");
        forms.forEach(function (form) {
            if (form.dataset.phoneRulesBound === "true") return;
            form.dataset.phoneRulesBound = "true";

            form.addEventListener("submit", function (event) {
                let isValid = true;
                const phoneInputs = form.querySelectorAll('input[data-phone-ready="true"]');
                phoneInputs.forEach(function (input) {
                    const val = input.value;
                    if (val && val.length > 0 && val.length !== 10) {
                        isValid = false;
                        input.style.borderColor = "red";
                    } else {
                        input.style.borderColor = "";
                    }
                });

                if (!isValid) {
                    event.preventDefault();
                    alert("Phone number must be exactly 10 digits.");
                }
            });
        });
    }

    bindFormSubmitListeners(document);

    // Watch for dynamically added forms to bind submit listeners
    const formObserver = new MutationObserver(function (mutations) {
        mutations.forEach(function (mutation) {
            mutation.addedNodes.forEach(function (node) {
                if (node.nodeType === 1) {
                    bindFormSubmitListeners(node);
                }
            });
        });
    });
    formObserver.observe(document.body, { childList: true, subtree: true });
});
