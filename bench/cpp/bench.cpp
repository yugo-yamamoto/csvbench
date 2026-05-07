#include <chrono>
#include <cstdio>
#include <cstring>
#include <limits>
#include <map>
#include <string>
#include <vector>

// ── Buffered reader (64 KB chunks via fread) ──────────────────────────────────
class BufferedReader {
    static constexpr size_t BUF = 65536;
    FILE*  fp_;
    char   buf_[BUF];
    size_t pos_ = 0, len_ = 0;

    bool refill() {
        len_ = std::fread(buf_, 1, BUF, fp_);
        pos_ = 0;
        return len_ > 0;
    }

public:
    explicit BufferedReader(const char* path) : fp_(std::fopen(path, "rb")) {}
    ~BufferedReader() { if (fp_) std::fclose(fp_); }
    bool ok() const { return fp_ != nullptr; }

    // Returns next byte, or -1 at EOF.
    int get() {
        if (pos_ >= len_ && !refill()) return -1;
        return static_cast<unsigned char>(buf_[pos_++]);
    }

    // Returns next byte without consuming it, or -1 at EOF.
    int peek() {
        if (pos_ >= len_ && !refill()) return -1;
        return static_cast<unsigned char>(buf_[pos_]);
    }
};

// ── RFC 4180 record parser ────────────────────────────────────────────────────
// Reads one CSV record; returns false at EOF.
static bool read_record(BufferedReader& r, std::vector<std::string>& fields) {
    fields.clear();
    std::string field;
    bool in_quote = false;
    int c;

    while ((c = r.get()) != -1) {
        char ch = static_cast<char>(c);
        if (in_quote) {
            if (ch == '"') {
                if (r.peek() == '"') { r.get(); field += '"'; } // escaped ""
                else                 { in_quote = false; }      // closing quote
            } else {
                field += ch; // includes embedded newlines
            }
        } else {
            switch (ch) {
                case '"':  in_quote = true; break;
                case ',':  fields.push_back(field); field.clear(); break;
                case '\n': fields.push_back(field); return true;
                case '\r': break; // skip; \n follows
                default:   field += ch;
            }
        }
    }
    // EOF
    if (!fields.empty() || !field.empty()) {
        fields.push_back(field);
        return true;
    }
    return false;
}

struct Group {
    double revenue   = 0.0;
    int    count     = 0;
    double value_sum = 0.0;
    double value_max = -std::numeric_limits<double>::infinity();
    double value_min =  std::numeric_limits<double>::infinity();
};

int main(int argc, char* argv[]) {
    const char* data_file = argc > 1 ? argv[1] : "../../data/test.csv";

    BufferedReader reader(data_file);
    if (!reader.ok()) {
        std::fprintf(stderr, "cannot open: %s\n", data_file);
        return 1;
    }

    auto t0 = std::chrono::steady_clock::now();

    std::vector<std::string> row;

    // Header
    read_record(reader, row);
    int cat_idx = -1, val_idx = -1, qty_idx = -1;
    for (int i = 0; i < (int)row.size(); ++i) {
        if      (row[i] == "category") cat_idx = i;
        else if (row[i] == "value")    val_idx = i;
        else if (row[i] == "quantity") qty_idx = i;
    }

    std::map<std::string, Group> totals;

    while (read_record(reader, row)) {
        const std::string& cat = row[cat_idx];
        double value = std::stod(row[val_idx]);
        int    qty   = std::stoi(row[qty_idx]);

        Group& g = totals[cat];
        g.revenue   += value * qty;
        g.count     += 1;
        g.value_sum += value;
        if (value > g.value_max) g.value_max = value;
        if (value < g.value_min) g.value_min = value;
    }

    std::printf("%-12s %8s %14s %12s %8s %8s\n",
                "Category", "Count", "Revenue", "Avg Value", "Max", "Min");
    for (int i = 0; i < 66; ++i) std::putchar('-');
    std::putchar('\n');
    for (const auto& [cat, g] : totals) {
        std::printf("%-12s %8d %14.2f %12.2f %8.2f %8.2f\n",
                    cat.c_str(), g.count, g.revenue,
                    g.value_sum / g.count, g.value_max, g.value_min);
    }

    double elapsed = std::chrono::duration<double>(
        std::chrono::steady_clock::now() - t0).count();
    std::printf("\nElapsed: %.4fs\n", elapsed);
    return 0;
}
