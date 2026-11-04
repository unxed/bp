// SPDX-License-Identifier: MIT
// The server of examples/httpd/httpd.pas in Go, for the benchmark (run.sh): net/http, the same three routes and
// bodies. usage: httpd-go [PORT]   (default 8080)
package main

import (
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync/atomic"
)

var requests, bytesSent atomic.Int64

func send(w http.ResponseWriter, code int, ctype, body string) {
	w.Header().Set("Content-Type", ctype)
	w.WriteHeader(code)
	requests.Add(1)
	bytesSent.Add(int64(len(body)))
	io.WriteString(w, body)
}

func squares(n int) string {
	var b strings.Builder
	b.WriteString(`{"n":` + strconv.Itoa(n) + `,"squares":[`)
	for i := 1; i <= n; i++ {
		if i > 1 {
			b.WriteByte(',')
		}
		b.WriteString(strconv.Itoa(i * i))
	}
	b.WriteString("]}\n")
	return b.String()
}

func main() {
	port := "8080"
	if len(os.Args) > 1 {
		port = os.Args[1]
	}
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			send(w, http.StatusNotFound, "text/plain", "Not Found\n")
			return
		}
		send(w, http.StatusOK, "text/plain", "Hello from Better Pascal\n")
	})
	http.HandleFunc("/json", func(w http.ResponseWriter, r *http.Request) {
		s := "10"
		if v, ok := r.URL.Query()["n"]; ok {
			s = v[0]
		}
		n, err := strconv.Atoi(s)
		if err != nil || n < 0 || n > 1000 {
			send(w, http.StatusBadRequest, "text/plain", "n must be 0..1000\n")
			return
		}
		send(w, http.StatusOK, "application/json", squares(n))
	})
	http.HandleFunc("/stats", func(w http.ResponseWriter, r *http.Request) {
		send(w, http.StatusOK, "application/json",
			`{"requests":`+strconv.FormatInt(requests.Load(), 10)+`,"bytes":`+strconv.FormatInt(bytesSent.Load(), 10)+"}\n")
	})
	log.Fatal(http.ListenAndServe(":"+port, nil))
}
