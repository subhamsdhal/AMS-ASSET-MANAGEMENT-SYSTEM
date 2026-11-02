package com.mycompany.asset_management_system_ams;

import com.mycompany.asset_management_system_ams.CopilotEngine;

public class TestWarrantyQueries {
    public static void main(String[] args) {
        String[] queries = {
            "warranty expiring in next 30 days",
            "whose warranty expiring in next 30 days",
            "which assets warranty will expire within 15 days",
            "show expired warranties",
            "warranty expired assets",
            "assets whose warranty expires soon",
            "warranty expiring this month",
            "warranty report"
        };
        
        for (String q : queries) {
            System.out.println("-------------------------------------------------");
            System.out.println("Query: " + q);
            // using userId 1, role ADMIN, no session
            CopilotEngine.CopilotResponse r = CopilotEngine.answer(q, 1, "Admin", "ADMIN", null);
            System.out.println("Response:\n" + r.answer);
        }
    }
}
