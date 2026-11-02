package com.mycompany.asset_management_system_ams;

import java.time.LocalDate;
import java.time.format.DateTimeParseException;

public final class DateValidationUtil {

    private DateValidationUtil() {
    }

    public static boolean isValidIsoDate(String dateText) {
        return parseDate(dateText) != null;
    }

    public static boolean isPastOrToday(String dateText) {
        LocalDate date = parseDate(dateText);

        if (date == null) {
            return false;
        }

        return !date.isAfter(LocalDate.now());
    }

    public static boolean isTodayOrFuture(String dateText) {
        LocalDate date = parseDate(dateText);

        if (date == null) {
            return false;
        }

        return !date.isBefore(LocalDate.now());
    }

    public static boolean isDateNotBefore(String mainDateText, String referenceDateText) {
        LocalDate mainDate = parseDate(mainDateText);
        LocalDate referenceDate = parseDate(referenceDateText);

        if (mainDate == null || referenceDate == null) {
            return false;
        }

        return !mainDate.isBefore(referenceDate);
    }

    public static boolean isDateNotAfter(String mainDateText, String referenceDateText) {
        LocalDate mainDate = parseDate(mainDateText);
        LocalDate referenceDate = parseDate(referenceDateText);

        if (mainDate == null || referenceDate == null) {
            return false;
        }

        return !mainDate.isAfter(referenceDate);
    }

    public static String today() {
        return LocalDate.now().toString();
    }

    private static LocalDate parseDate(String dateText) {
        try {
            if (dateText == null || dateText.trim().isEmpty()) {
                return null;
            }

            return LocalDate.parse(dateText.trim());

        } catch (DateTimeParseException e) {
            return null;
        }
    }
}