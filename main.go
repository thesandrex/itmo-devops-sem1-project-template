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

var db *sql.DB

type UploadResponse struct {
	TotalItems      int `json:"total_items"`
	TotalCategories int `json:"total_categories"`
	TotalPrice      int `json:"total_price"`
}

func initDB() {
	var err error
	connStr := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		os.Getenv("POSTGRES_HOST"),
		os.Getenv("POSTGRES_PORT"),
		os.Getenv("POSTGRES_USER"),
		os.Getenv("POSTGRES_PASSWORD"),
		os.Getenv("POSTGRES_DB"),
	)
	db, err = sql.Open("postgres", connStr)
	if err != nil {
		log.Fatalf("Failed to connect to the database: %v", err)
	}

	_, err = db.Exec(`CREATE TABLE IF NOT EXISTS prices (
		id SERIAL PRIMARY KEY,
		category TEXT,
		price INT
	)`)
	if err != nil {
		log.Fatalf("Failed to create table: %v", err)
	}
}

func uploadHandler(w http.ResponseWriter, r *http.Request) {
	archiveType := r.URL.Query().Get("type")
	if archiveType == "" {
		archiveType = "zip"
	}

	file, _, err := r.FormFile("file")
	if err != nil {
		http.Error(w, "Failed to read file: "+err.Error(), http.StatusBadRequest)
		return
	}
	defer file.Close()

	var totalItems, totalCategories, totalPrice int
	switch archiveType {
	case "zip":
		totalItems, totalCategories, totalPrice, err = processZipArchive(file)
	case "tar":
		totalItems, totalCategories, totalPrice, err = processTarArchive(file)
	default:
		http.Error(w, "Unsupported archive type: "+archiveType, http.StatusBadRequest)
		return
	}

	if err != nil {
		http.Error(w, "Failed to process archive: "+err.Error(), http.StatusInternalServerError)
		return
	}

	resp := UploadResponse{
		TotalItems:      totalItems,
		TotalCategories: totalCategories,
		TotalPrice:      totalPrice,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func processZipArchive(file io.Reader) (int, int, int, error) {
	buf := new(bytes.Buffer)
	_, err := io.Copy(buf, file)
	if err != nil {
		return 0, 0, 0, fmt.Errorf("failed to read zip file: %v", err)
	}

	zipReader, err := zip.NewReader(bytes.NewReader(buf.Bytes()), int64(buf.Len()))
	if err != nil {
		return 0, 0, 0, fmt.Errorf("failed to open zip archive: %v", err)
	}

	lines := []string{}
	for _, f := range zipReader.File {
		rc, err := f.Open()
		if err != nil {
			return 0, 0, 0, fmt.Errorf("failed to open file in zip: %v", err)
		}
		content, err := io.ReadAll(rc)
		rc.Close()
		if err != nil {
			return 0, 0, 0, fmt.Errorf("failed to read file content: %v", err)
		}
		lines = append(lines, strings.Split(string(content), "\n")...)
	}

	return processLines(lines)
}

func processTarArchive(file io.Reader) (int, int, int, error) {
	tarReader := tar.NewReader(file)
	lines := []string{}

	for {
		header, err := tarReader.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return 0, 0, 0, fmt.Errorf("failed to read tar archive: %v", err)
		}
		if header.Typeflag == tar.TypeReg {
			content, err := io.ReadAll(tarReader)
			if err != nil {
				return 0, 0, 0, fmt.Errorf("failed to read file content in tar: %v", err)
			}
			lines = append(lines, strings.Split(string(content), "\n")...)
		}
	}

	return processLines(lines)
}

func processLines(lines []string) (int, int, int, error) {
	categorySet := make(map[string]struct{})
	totalPrice := 0

	for _, line := range lines {
		fields := strings.Split(line, ",")
		if len(fields) < 2 {
			continue
		}
		category := fields[0]
		price, err := strconv.Atoi(fields[1])
		if err != nil {
			return 0, 0, 0, fmt.Errorf("invalid price format: %v", err)
		}

		_, err = db.Exec("INSERT INTO prices (category, price) VALUES ($1, $2)", category, price)
		if err != nil {
			return 0, 0, 0, fmt.Errorf("failed to insert into database: %v", err)
		}

		categorySet[category] = struct{}{}
		totalPrice += price
	}

	return len(lines), len(categorySet), totalPrice, nil
}

func downloadHandler(w http.ResponseWriter, r *http.Request) {
	archiveType := r.URL.Query().Get("type")
	if archiveType == "" {
		archiveType = "zip"
	}

	rows, err := db.Query("SELECT category, price FROM prices")
	if err != nil {
		http.Error(w, "Failed to fetch data: "+err.Error(), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	buf := new(bytes.Buffer)
	writer := csv.NewWriter(buf)

	for rows.Next() {
		var category string
		var price int
		if err := rows.Scan(&category, &price); err != nil {
			http.Error(w, "Failed to scan data: "+err.Error(), http.StatusInternalServerError)
			return
		}
		writer.Write([]string{category, strconv.Itoa(price)})
	}
	writer.Flush()

	w.Header().Set("Content-Disposition", "attachment; filename=data."+archiveType)

	switch archiveType {
	case "zip":
		w.Header().Set("Content-Type", "application/zip")
		zipWriter := zip.NewWriter(w)
		defer zipWriter.Close()

		f, err := zipWriter.Create("data.csv")
		if err != nil {
			http.Error(w, "Failed to create zip file: "+err.Error(), http.StatusInternalServerError)
			return
		}
		_, err = f.Write(buf.Bytes())
		if err != nil {
			http.Error(w, "Failed to write zip file: "+err.Error(), http.StatusInternalServerError)
			return
		}
	case "tar":
		w.Header().Set("Content-Type", "application/x-tar")
		tarWriter := tar.NewWriter(w)
		defer tarWriter.Close()

		header := &tar.Header{
			Name: "data.csv",
			Size: int64(buf.Len()),
		}
		if err := tarWriter.WriteHeader(header); err != nil {
			http.Error(w, "Failed to write tar header: "+err.Error(), http.StatusInternalServerError)
			return
		}
		_, err = tarWriter.Write(buf.Bytes())
		if err != nil {
			http.Error(w, "Failed to write tar file: "+err.Error(), http.StatusInternalServerError)
			return
		}
	default:
		http.Error(w, "Unsupported archive type: "+archiveType, http.StatusBadRequest)
		return
	}
}

func main() {
	initDB()
	http.HandleFunc("/api/v0/prices", downloadHandler)
	http.HandleFunc("/api/v0/prices?type=zip", uploadHandler)

	log.Println("Server started on :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}

