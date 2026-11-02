package com.mycompany.asset_management_system_ams;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * LlmToolSpec — a tool the model is allowed to call, in provider-neutral form.
 *
 * This is the ONLY thing the model gets to choose from. It never writes SQL and
 * never names a table: it picks a spec by name and supplies string parameters,
 * which CopilotToolCatalog maps onto CopilotQueryPlan fields before calling the
 * existing (PreparedStatement-based, role-scoped) CopilotToolExecutor methods.
 *
 * Security note: the catalog is filtered by role BEFORE these are serialized
 * into the request, so a lower-privileged user's model never learns that a
 * restricted tool exists. The executor methods additionally re-check the
 * session role themselves — same defence-in-depth pattern as
 * RoleAccessUtil + each page's own gate.
 */
public class LlmToolSpec {

    public static class Param {
        public final String name;
        public final String description;
        /** Optional allowed values. Empty means free text. */
        public final List<String> allowedValues;

        public Param(String name, String description, List<String> allowedValues) {
            this.name = name;
            this.description = description;
            this.allowedValues = allowedValues == null ? new ArrayList<String>() : allowedValues;
        }
    }

    public final String name;
    public final String description;
    public final Map<String, Param> parameters = new LinkedHashMap<String, Param>();

    public LlmToolSpec(String name, String description) {
        this.name = name;
        this.description = description;
    }

    public LlmToolSpec param(String paramName, String paramDescription) {
        parameters.put(paramName, new Param(paramName, paramDescription, null));
        return this;
    }

    public LlmToolSpec param(String paramName, String paramDescription, String... allowed) {
        List<String> values = new ArrayList<String>();
        if (allowed != null) {
            for (String value : allowed) {
                values.add(value);
            }
        }
        parameters.put(paramName, new Param(paramName, paramDescription, values));
        return this;
    }
}
