import com.univocity.parsers.csv.*;
import java.io.*;
import java.nio.file.*;
import java.util.*;

public class BenchUnivocity {

    static int indexOf(String[] arr, String target) {
        for (int i = 0; i < arr.length; i++)
            if (arr[i].equals(target)) return i;
        throw new RuntimeException("column not found: " + target);
    }

    public static void main(String[] args) throws Exception {
        Path dataFile = Path.of(args.length > 0 ? args[0] : "../../data/test.csv")
                .toAbsolutePath().normalize();

        long startNs = System.nanoTime();

        CsvParserSettings settings = new CsvParserSettings();
        settings.setHeaderExtractionEnabled(true);

        Map<String, double[]> revenue = new TreeMap<>();
        Map<String, int[]>    count   = new TreeMap<>();
        Map<String, double[]> valSum  = new TreeMap<>();
        Map<String, double[]> valMax  = new TreeMap<>();
        Map<String, double[]> valMin  = new TreeMap<>();

        CsvParser parser = new CsvParser(settings);
        parser.beginParsing(dataFile.toFile());

        String[] headers = parser.getContext().headers();
        int catIdx = indexOf(headers, "category");
        int valIdx = indexOf(headers, "value");
        int qtyIdx = indexOf(headers, "quantity");

        String[] row;
        while ((row = parser.parseNext()) != null) {
            String cat  = row[catIdx];
            double value = Double.parseDouble(row[valIdx]);
            int    qty   = Integer.parseInt(row[qtyIdx]);

            revenue.computeIfAbsent(cat, k -> new double[]{0.0})[0] += value * qty;
            count  .computeIfAbsent(cat, k -> new int[]{0})[0]++;
            valSum .computeIfAbsent(cat, k -> new double[]{0.0})[0] += value;
            valMax .computeIfAbsent(cat, k -> new double[]{Double.NEGATIVE_INFINITY})[0] =
                    Math.max(valMax.computeIfAbsent(cat, k -> new double[]{Double.NEGATIVE_INFINITY})[0], value);
            valMin .computeIfAbsent(cat, k -> new double[]{Double.POSITIVE_INFINITY})[0] =
                    Math.min(valMin.computeIfAbsent(cat, k -> new double[]{Double.POSITIVE_INFINITY})[0], value);
        }
        parser.stopParsing();

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
