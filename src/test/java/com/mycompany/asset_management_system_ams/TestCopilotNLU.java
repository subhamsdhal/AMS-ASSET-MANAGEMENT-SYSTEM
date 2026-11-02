package com.mycompany.asset_management_system_ams;

public class TestCopilotNLU {
    public static void main(String[] args) {
        System.out.println("Starting Copilot NLU Regression Tests...\n");

        String[] testQueries = {
            "total cost of all laptop",
            "total cost of all laptops",
            "total cost of notebooks",
            "show laptops in IT department",
            "warranty expiring in next 30 days",
            "whose warranty expiring in next 30 days",
            "expired warranty assets",
            "warranty expiring this month",
            "pending maintenance",
            "maintenance history of AST010",
            "show employees in IT department",
            "available printers",
            "allocated laptops",
            "assets under maintenance",
            "export this",
            "mujhe batao saare laptops ka cost kitna hai",
            "saare laptop ka total cost batao",
            "laptops ka kharcha kitna hai",
            "mujhe IT department ke laptops dikhao",
            "agle 30 din me warranty expire hone wale assets dikhao",
            "warranty 30 din ke andar expire hone wala asset batao",
            "मुझे सारे लैपटॉप की कीमत बताओ",
            "लैपटॉप का कुल खर्च कितना है",
            "ଲାପଟପ୍ ର ମୋଟ ଖର୍ଚ୍ଚ କେତେ",
            "mote sabu laptop ra cost kete kuha",
            "agami 30 dina re warranty expire haba asset dekhao"
        };

        String[] commandQueries = {
            "add employee Rahul Kumar in IT department",
            "edit EMP006 mobile number to 9876543210",
            "disable employee EMP010",
            "delete employee EMP011",
            "add laptop Dell Latitude cost 55000 in IT department",
            "update AST005 status to Under Maintenance",
            "change AST010 department to Electrical",
            "delete asset AST020",
            "allocate AST004 to EMP006",
            "return asset AST004",
            "create maintenance request for AST010 issue screen not working",
            "mark maintenance request 5 completed",
            "approve asset request 12",
            "reject asset request 13 reason insufficient stock"
        };

        for (String query : testQueries) {
            System.out.println("==================================================");
            System.out.println("TEST QUERY: " + query);
            
            CopilotCommandPlan cmdPlan = CopilotCommandDetector.detectCommand(query);
            if (cmdPlan != null) {
                System.out.println("Detected Command Intent: " + cmdPlan.intent);
                System.out.println("Target Module: " + cmdPlan.targetModule);
                System.out.println("Extracted Fields: " + cmdPlan.extractedFields);
                System.out.println("Missing Fields: " + cmdPlan.missingRequiredFields);
                System.out.println("Requires Confirmation: " + cmdPlan.requiresConfirmation);
                System.out.println("Preview Message: " + cmdPlan.previewMessage);
                continue;
            }

            // 1. Run Detector
            CopilotQueryPlan plan = CopilotIntentDetector.detectIntent(query);
            System.out.println("Detected Intent: " + plan.intent);
            System.out.println("Normalized Category: " + plan.normalizedCategory);
            System.out.println("Department: " + plan.departmentName);
            System.out.println("Status: " + plan.status);
            if (plan.days != null) System.out.println("Days: " + plan.days);
        }

        for (String query : commandQueries) {
            System.out.println("==================================================");
            System.out.println("TEST COMMAND: " + query);
            
            CopilotCommandPlan cmdPlan = CopilotCommandDetector.detectCommand(query);
            if (cmdPlan != null) {
                System.out.println("Detected Command Intent: " + cmdPlan.intent);
                System.out.println("Target Module: " + cmdPlan.targetModule);
                System.out.println("Extracted Fields: " + cmdPlan.extractedFields);
                System.out.println("Missing Fields: " + cmdPlan.missingRequiredFields);
                System.out.println("Requires Confirmation: " + cmdPlan.requiresConfirmation);
                System.out.println("Preview Message: " + cmdPlan.previewMessage);
            } else {
                System.out.println("Failed to detect command!");
            }
        }
        
        System.out.println("\nAll Copilot NLU Regression Tests Completed.");
    }
}
