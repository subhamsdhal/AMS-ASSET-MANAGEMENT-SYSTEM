package com.mycompany.asset_management_system_ams;

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;

/**
 * Straight-line depreciation, the single calculation used everywhere the
 * app needs an asset's current worth: view_asset.jsp, depreciation_report.jsp,
 * and the write-off figure AssetDAO.reviewDisposal() records when a disposal
 * is approved.
 *
 * Before this class existed, the exact same formula was written inline, once,
 * directly into view_asset.jsp's SQL - the only place in the entire codebase
 * that computed a book value at all. Nowhere else (the asset list, any
 * report, disposal) had access to it, so there was no way to see an asset's
 * current worth except by opening that one page, and no way to record what
 * an asset was actually worth at the moment it was disposed of.
 *
 * Formula (unchanged from the original inline version, just centralized):
 *   accumulated depreciation = purchaseCost * (annualRatePercent / 100) * (monthsOwned / 12)
 *   book value = purchaseCost - accumulated depreciation
 * Both are floored/capped so depreciation can never exceed the original cost
 * and book value can never go negative - a fully depreciated asset is worth
 * exactly zero, not a negative number.
 */
public final class DepreciationUtil {

    private DepreciationUtil() {
    }

    /**
     * @param purchaseCost       original cost; a non-positive value means
     *                           "nothing to depreciate" (returns 0.0), not an error
     * @param annualRatePercent  e.g. 10.0 for 10% per year
     * @param purchaseDateIso    ISO date string (yyyy-MM-dd), as returned by
     *                           JDBC's getString() on a raw (non-DATE_FORMAT'd)
     *                           DATE column
     * @param asOf               the date to compute as of; null means today
     */
    public static double computeAccumulatedDepreciation(double purchaseCost, double annualRatePercent,
            String purchaseDateIso, LocalDate asOf) {
        if (purchaseCost <= 0 || annualRatePercent <= 0 || purchaseDateIso == null || purchaseDateIso.trim().isEmpty()) {
            return 0.0;
        }

        LocalDate purchaseDate = parseIso(purchaseDateIso);
        if (purchaseDate == null) {
            return 0.0;
        }

        LocalDate effectiveAsOf = asOf != null ? asOf : LocalDate.now();
        long monthsOwned = ChronoUnit.MONTHS.between(purchaseDate, effectiveAsOf);
        if (monthsOwned < 0) {
            monthsOwned = 0;
        }

        double raw = purchaseCost * (annualRatePercent / 100.0) * (monthsOwned / 12.0);
        double capped = Math.min(purchaseCost, raw);
        return round2(capped);
    }

    /** Current book value = purchase cost minus accumulated depreciation, floored at zero. */
    public static double computeBookValue(double purchaseCost, double annualRatePercent,
            String purchaseDateIso, LocalDate asOf) {
        double depreciation = computeAccumulatedDepreciation(purchaseCost, annualRatePercent, purchaseDateIso, asOf);
        double value = purchaseCost - depreciation;
        return round2(Math.max(value, 0.0));
    }

    private static LocalDate parseIso(String value) {
        try {
            return LocalDate.parse(value.trim(), DateTimeFormatter.ISO_LOCAL_DATE);
        } catch (Exception e) {
            return null;
        }
    }

    private static double round2(double value) {
        return Math.round(value * 100.0) / 100.0;
    }
}
