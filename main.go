package main

import (
	"archive/tar"
	"archive/zip"
	"bytes"
	"database/sql"
	"encoding/csv"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"

	_ "github.com/lib/pq"
)

type Response struct {
	TotalItems     int     `json:"total_items"`
	TotalCategories int    `json:"total_categories"`
	TotalPrice     float64 `json:"total_price"`
}

func main() {
	db, err := setupDatabase()
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer db.Close()

	http.HandleFunc("/api/v0/prices", func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPost {
			handlePost(db, w, r)
		} else if r.Method == http.MethodGet {
			handleGet(db, w, r)
		} else {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		}
	})

	port := os.Getenv("APP_PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("Server running on port %s", port)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}

func setupDatabase() (*sql.DB, error) {
	connStr := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		os.Getenv("POSTGRES_HOST"),
		os.Getenv("POSTGRES_PORT"),
		os.Getenv("POSTGRES_USER"),
		os.Getenv("POSTGRES_PASSWORD"),
		os.Getenv("POSTGRES_DB"),
	)
	return sql.Open("postgres", connStr)
}

func handlePost(db *sql.DB, w http.ResponseWriter, r *http.Request) {
	archiveType := r.URL.Query().Get("type")
	if archiveType == "" {
		archiveType = "zip"
	}

	file, _, err := r.FormFile("file")
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to read file: %v", err), http.StatusBadRequest)
		return
	}
	defer file.Close()

	totalItems, totalCategories, totalPrice, err := processArchive(db, file, archiveType)
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to process archive: %v", err), http.StatusInternalServerError)
		return
	}

	response := Response{
		TotalItems:     totalItems,
		TotalCategories: totalCategories,
		TotalPrice:     totalPrice,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func handleGet(db *sql.DB, w http.ResponseWriter, r *http.Request) {
	rows, err := db.Query("SELECT category, price FROM prices")
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to query database: %v", err), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var data [][]string
	data = append(data, []string{"Category", "Price"})
	for rows.Next() {
		var category string
		var price float64
		if err := rows.Scan(&category, &price); err != nil {
			http.Error(w, fmt.Sprintf("Failed to scan row: %v", err), http.StatusInternalServerError)
			return
		}
		data = append(data, []string{category, fmt.Sprintf("%.2f", price)})
	}

	buf := new(bytes.Buffer)
	zipWriter := zip.NewWriter(buf)
	fileWriter, err := zipWriter.Create("data.csv")
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to create zip file: %v", err), http.StatusInternalServerError)
		return
	}

	csvWriter := csv.NewWriter(fileWriter)
	if err := csvWriter.WriteAll(data); err != nil {
		http.Error(w, fmt.Sprintf("Failed to write CSV data: %v", err), http.StatusInternalServerError)
		return
	}

	if err := zipWriter.Close(); err != nil {
		http.Error(w, fmt.Sprintf("Failed to close zip writer: %v", err), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/zip")
	w.Header().Set("Content-Disposition", "attachment; filename=data.zip")
	w.Write(buf.Bytes())
}

func processArchive(db *sql.DB, file io.Reader, archiveType string) (int, int, float64, error) {
	var lines []string
	var err error

	switch archiveType {
	case "zip":
		lines, err = extractFromZip(file)
	case "tar":
		lines, err = extractFromTar(file)
	default:
		return 0, 0, 0, fmt.Errorf("unsupported archive type: %s", archiveType)
	}

	if err != nil {
		return 0, 0, 0, fmt.Errorf("failed to extract lines from archive: %v", err)
	}

	return processLinesAndInsert(db, lines)
}

func extractFromZip(file io.Reader) ([]string, error) {
	buf := new(bytes.Buffer)
	_, err := io.Copy(buf, file)
	if err != nil {
		return nil, fmt.Errorf("failed to read zip file: %v", err)
	}

	zipReader, err := zip.NewReader(bytes.NewReader(buf.Bytes()), int64(buf.Len()))
	if err != nil {
		return nil, fmt.Errorf("failed to open zip archive: %v", err)
	}

	var lines []string
	for _, f := range zipReader.File {
		rc, err := f.Open()
		if err != nil {
			return nil, fmt.Errorf("failed to open file in zip: %v", err)
		}
		defer rc.Close()

		content, err := io.ReadAll(rc)
		if err != nil {
			return nil, fmt.Errorf("failed to read file content: %v", err)
		}
		lines = append(lines, strings.Split(string(content), "\n")...)
	}

	return lines, nil
}

func extractFromTar(file io.Reader) ([]string, error) {
	tarReader := tar.NewReader(file)
	var lines []string

	for {
		header, err := tarReader.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("failed to read tar archive: %v", err)
		}
		if header.Typeflag == tar.TypeReg {
			content, err := io.ReadAll(tarReader)
			if err != nil {
				return nil, fmt.Errorf("failed to read file content in tar: %v", err)
			}
			lines = append(lines, strings.Split(string(content), "\n")...)
		}
	}

	return lines, nil
}

func processLinesAndInsert(db *sql.DB, lines []string) (int, int, float64, error) {
	totalItems := 0
	totalCategories := make(map[string]bool)
	totalPrice := 0.0

	for _, line := range lines {
		fields := strings.Split(line, ",")
		if len(fields) < 2 {
			continue
		}

		category := fields[0]
		price, err := strconv.ParseFloat(fields[1], 64)
		if err != nil {
			return 0, 0, 0, fmt.Errorf("failed to parse price: %v", err)
		}

		_, err = db.Exec("INSERT INTO prices (category, price) VALUES ($1, $2)", category, price)
		if err != nil {
			return 0, 0, 0, fmt.Errorf("failed to insert into database: %v", err)
		}

		totalItems++
		totalCategories[category] = true
		totalPrice += price
	}

	return totalItems, len(totalCategories), totalPrice, nil
}
