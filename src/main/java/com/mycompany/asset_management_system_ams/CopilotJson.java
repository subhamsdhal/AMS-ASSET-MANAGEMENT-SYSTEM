package com.mycompany.asset_management_system_ams;

import java.util.Collection;
import java.util.Map;

/**
 * CopilotJson — serializes DAO results into compact JSON for the model.
 *
 * Not a general-purpose JSON library: it exists to turn the
 * Map&lt;String,Object&gt; that CopilotToolExecutor returns into something a
 * model can read, with two deliberate constraints:
 *
 *  - ROW CAP. A tool that returns 4,000 rows would blow the context window and
 *    cost a fortune for no benefit, so lists are truncated and annotated with
 *    the true total. The model is told it was truncated, so it can say
 *    "showing the first 40 of 812" rather than silently implying it saw
 *    everything.
 *  - VALUE CAP. Individual free-text fields (remarks, descriptions) are
 *    clipped so one pathological row can't dominate the payload.
 */
public final class CopilotJson {

    private static final int MAX_ROWS = 40;
    private static final int MAX_VALUE_CHARS = 400;

    private CopilotJson() {
    }

    public static String toJson(Object value) {
        StringBuilder sb = new StringBuilder();
        write(sb, value, 0);
        return sb.toString();
    }

    private static void write(StringBuilder sb, Object value, int depth) {
        if (value == null) {
            sb.append("null");
            return;
        }

        // Guard against a self-referencing structure turning into a stack overflow.
        if (depth > 6) {
            sb.append("\"...\"");
            return;
        }

        if (value instanceof Map) {
            writeMap(sb, (Map<?, ?>) value, depth);
        } else if (value instanceof Collection) {
            writeCollection(sb, (Collection<?>) value, depth);
        } else if (value instanceof Number || value instanceof Boolean) {
            sb.append(value);
        } else {
            sb.append('"').append(escape(clip(String.valueOf(value)))).append('"');
        }
    }

    private static void writeMap(StringBuilder sb, Map<?, ?> map, int depth) {
        sb.append('{');
        boolean first = true;
        for (Map.Entry<?, ?> entry : map.entrySet()) {
            if (!first) {
                sb.append(',');
            }
            first = false;
            sb.append('"').append(escape(String.valueOf(entry.getKey()))).append("\":");
            write(sb, entry.getValue(), depth + 1);
        }
        sb.append('}');
    }

    private static void writeCollection(StringBuilder sb, Collection<?> collection, int depth) {
        int total = collection.size();
        sb.append('[');

        int written = 0;
        for (Object item : collection) {
            if (written >= MAX_ROWS) {
                break;
            }
            if (written > 0) {
                sb.append(',');
            }
            write(sb, item, depth + 1);
            written++;
        }

        // The truncation note goes INSIDE the array as a final element. Writing
        // it as a sibling after the ']' only produces valid JSON when the list
        // happens to be a map value — it would corrupt the payload for a
        // root-level or nested-in-array list. Kept in-band so the model can be
        // honest with the user about the row count it actually saw.
        if (total > MAX_ROWS) {
            if (written > 0) {
                sb.append(',');
            }
            sb.append("{\"_truncated\":{\"shown\":").append(written)
              .append(",\"total\":").append(total)
              .append(",\"note\":\"Only the first ").append(written)
              .append(" rows are shown. State this when summarising.\"}}");
        }

        sb.append(']');
    }

    private static String clip(String text) {
        if (text.length() <= MAX_VALUE_CHARS) {
            return text;
        }
        return text.substring(0, MAX_VALUE_CHARS) + "...";
    }

    public static String escape(String text) {
        if (text == null) {
            return "";
        }
        StringBuilder sb = new StringBuilder(text.length() + 16);
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            switch (c) {
                case '"':  sb.append("\\\""); break;
                case '\\': sb.append("\\\\"); break;
                case '\n': sb.append("\\n");  break;
                case '\r': sb.append("\\r");  break;
                case '\t': sb.append("\\t");  break;
                default:
                    if (c < 0x20) {
                        sb.append(String.format("\\u%04x", (int) c));
                    } else {
                        sb.append(c);
                    }
            }
        }
        return sb.toString();
    }
}
