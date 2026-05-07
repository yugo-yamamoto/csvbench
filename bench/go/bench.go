package main

import (
	"encoding/csv"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"time"
)

type Group struct {
	revenue  float64
	count    int
	valueSum float64
	valueMax float64
	valueMin float64
}

func main() {
	_, thisFile, _, _ := runtime.Caller(0)
	dataFile := filepath.Join(filepath.Dir(thisFile), "..", "..", "data", "test.csv")

	f, err := os.Open(dataFile)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	defer f.Close()

	start := time.Now()

	r := csv.NewReader(f)
	header, err := r.Read()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	colIndex := map[string]int{}
	for i, col := range header {
		colIndex[col] = i
	}

	totals := map[string]*Group{}

	for {
		row, err := r.Read()
		if err != nil {
			break
		}
		cat := row[colIndex["category"]]
		value, _ := strconv.ParseFloat(row[colIndex["value"]], 64)
		qty, _ := strconv.Atoi(row[colIndex["quantity"]])

		g, ok := totals[cat]
		if !ok {
			g = &Group{valueMax: math.Inf(-1), valueMin: math.Inf(1)}
			totals[cat] = g
		}
		g.revenue += value * float64(qty)
		g.count++
		g.valueSum += value
		if value > g.valueMax {
			g.valueMax = value
		}
		if value < g.valueMin {
			g.valueMin = value
		}
	}

	cats := make([]string, 0, len(totals))
	for cat := range totals {
		cats = append(cats, cat)
	}
	sort.Strings(cats)

	fmt.Printf("%-12s %8s %14s %12s %8s %8s\n", "Category", "Count", "Revenue", "Avg Value", "Max", "Min")
	for i := 0; i < 66; i++ {
		fmt.Print("-")
	}
	fmt.Println()
	for _, cat := range cats {
		g := totals[cat]
		avg := g.valueSum / float64(g.count)
		fmt.Printf("%-12s %8d %14.2f %12.2f %8.2f %8.2f\n", cat, g.count, g.revenue, avg, g.valueMax, g.valueMin)
	}

	elapsed := time.Since(start)
	fmt.Printf("\nElapsed: %.4fs\n", elapsed.Seconds())
}
