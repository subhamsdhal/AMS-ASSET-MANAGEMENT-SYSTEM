package com.mycompany.asset_management_system_ams;

import org.junit.jupiter.api.Test;
import java.io.File;
import java.nio.file.Files;
import java.sql.Connection;
import java.sql.Statement;

public class DBSeederTest {

    @Test
    public void runSeed() throws Exception {
        File file = new File("seed_user_passwords.sql");
        if (!file.exists()) {
            System.out.println("seed_user_passwords.sql not present; skipping local seeder execution.");
            return;
        }

        String sql = new String(Files.readAllBytes(file.toPath()));
        String[] queries = sql.split(";");

        try (Connection con = DBConnection.getConnection()) {
            if (con == null) {
                System.out.println("Database connection not configured or unreachable; skipping seed execution.");
                return;
            }

            try (Statement stmt = con.createStatement()) {
                for (String q : queries) {
                    if (!q.trim().isEmpty()) {
                        stmt.execute(q);
                    }
                }
            }
        }
    }
}
