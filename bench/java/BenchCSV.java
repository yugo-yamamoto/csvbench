import java.io.*;
import java.nio.file.*;
import java.util.*;

public class BenchCSV {

    /**
     * Read one CSV record from a BufferedReader.
     * RFC 4180 compliant: handles quoted fields, "" escape, embedded newlines.
     * Returns null at EOF.
     */
    static List<String> readRecord(BufferedReader br) throws IOException {
        List<String> fields = new ArrayList<>();
        StringBuilder field = new StringBuilder();
        boolean inQuote = false;
        int c;

        while ((c = br.read()) != -1) {
            char ch = (char) c;
            if (inQuote) {
                if (ch == '"') {
                    br.mark(1);
                    int next = br.read();
                    if (next == '"') {
                        field.append('"'); // escaped ""
                    } else {
                        inQuote = false;
                        if (next != -1) br.reset(); // put back the char after closing quote
                    }
                } else {
                    field.append(ch); // embedded newline or any other char
                }
            } else {
                switch (ch) {
                    case '"'  -> inQuote = true;
                    case ','  -> { fields.add(field.toString()); field.setLength(0); }
                    case '\n' -> { fields.add(field.toString()); return fields; }
                    case '\r' -> {} // skip; \n follows
                    default   -> field.append(ch);
                }
            }
        }

        // EOF — return last record if non-empty
        if (!fields.isEmpty() || field.length() > 0) {
            fields.add(field.toString());
            return fields;
        }
        return null;
    }

    public static void main(String[] args) throws Exception {
        Path dataFile = Path.of(BenchCSV.class.getProtectionDomain().getCodeSource().getLocation().toURI())
                .getParent()
                .resolve("../../data/test.csv")
                .normalize();

        long startNs = System.nanoTime();

        Map<String, double[]> revenue = new TreeMap<>();
        Map<String, int[]>    count   = new TreeMap<>();
        Map<String, double[]> valSum  = new TreeMap<>();
        Map<String, double[]> valMax  = new TreeMap<>();
        Map<String, double[]> valMin  = new TreeMap<>();

        try (BufferedReader br = new BufferedReader(new FileReader(dataFile.toFile()))) {
            // header
            List<String> header = readRecord(br);
            Map<String, Integer> colIndex = new HashMap<>();
            for (int i = 0; i < header.size(); i++) colIndex.put(header.get(i), i);

            int catIdx = colIndex.get("category");
            int valIdx = colIndex.get("value");
            int qtyIdx = colIndex.get("quantity");

            List<String> row;
            while ((row = readRecord(br)) != null) {
                String cat  = row.get(catIdx);
                double value = Double.parseDouble(row.get(valIdx));
                int    qty   = Integer.parseInt(row.get(qtyIdx));

                revenue.computeIfAbsent(cat, k -> new double[]{0.0})[0] += value * qty;
                count  .computeIfAbsent(cat, k -> new int[]{0})[0]++;
                valSum .computeIfAbsent(cat, k -> new double[]{0.0})[0] += value;
                valMax .computeIfAbsent(cat, k -> new double[]{Double.NEGATIVE_INFINITY})[0] =
                        Math.max(valMax.computeIfAbsent(cat, k -> new double[]{Double.NEGATIVE_INFINITY})[0], value);
                valMin .computeIfAbsent(cat, k -> new double[]{Double.POSITIVE_INFINITY})[0] =
                        Math.min(valMin.computeIfAbsent(cat, k -> new double[]{Double.POSITIVE_INFINITY})[0], value);
            }
        }

        System.out.printf("%-12s %8s %14s %12s %8s %8s%n",
                "Category", "Count", "Revenue", "Avg Value", "Max", "Min");
        System.out.println("-".repeat(66));
        for (String cat : revenue.keySet()) {
            int cnt = count.get(cat)[0];
            double avg = valSum.get(cat)[0] / cnt;
            System.out.printf("%-12s %8d %14.2f %12.2f %8.2f %8.2f%n",
                    cat, cnt, revenue.get(cat)[0], avg, valMax.get(cat)[0], valMin.get(cat)[0]);
        }

        double elapsed = (System.nanoTime() - startNs) / 1e9;
        System.out.printf("%nElapsed: %.4fs%n", elapsed);
    }
}
