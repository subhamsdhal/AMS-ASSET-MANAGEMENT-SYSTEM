package com.mycompany.asset_management_system_ams;

import java.io.Serializable;
import java.util.HashMap;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

public class CopilotCommandPlan implements Serializable {
    private static final long serialVersionUID = 1L;

    public String rawUserMessage;
    public CopilotIntentType intent;
    public String targetModule;
    public String actionType;

    public Map<String, String> extractedFields = new HashMap<>();
    public List<String> missingRequiredFields = new ArrayList<>();

    public boolean requiresConfirmation;
    public String confirmationToken;
    public String strongConfirmationText;
    public boolean destructiveAction;

    public boolean permissionAllowed = true;
    public String permissionReason;

    public String previewMessage;
    
    public CopilotCommandPlan() {
    }

    @Override
    public String toString() {
        return "CopilotCommandPlan{" +
                "intent=" + intent +
                ", targetModule='" + targetModule + '\'' +
                ", actionType='" + actionType + '\'' +
                ", extractedFields=" + extractedFields +
                ", missingRequiredFields=" + missingRequiredFields +
                ", requiresConfirmation=" + requiresConfirmation +
                ", permissionAllowed=" + permissionAllowed +
                '}';
    }
}
