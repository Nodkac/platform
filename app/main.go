package main

import (
	"log"
	"math/rand"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// requests counts every HTTP request, labelled by path and status code.
// In Phase 2 you divide 5xx by total to get your error ratio.
var requests = promauto.NewCounterVec(prometheus.CounterOpts{
	Name: "http_requests_total",
	Help: "Total HTTP requests.",
}, []string{"path", "code"})

// latency records how long requests take, in buckets.
// Buckets are what make p95 computable later — a plain average can't give you that.
var latency = promauto.NewHistogramVec(prometheus.HistogramOpts{
	Name:    "http_request_duration_seconds",
	Help:    "Request latency in seconds.",
	Buckets: []float64{0.005, 0.01, 0.025, 0.05, 0.1, 0.2, 0.4, 0.8, 1.6},
}, []string{"path"})

// record updates both metrics after a request finishes.
func record(path string, code int, start time.Time) {
	latency.WithLabelValues(path).Observe(time.Since(start).Seconds())
	requests.WithLabelValues(path, strconv.Itoa(code)).Inc()
}

func main() {
	// The normal endpoint. This is what your load generator hits.
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		w.Write([]byte("hello from the platform\n"))
		record("/", 200, start)
	})

	// Kubernetes calls this to decide whether the pod is alive and ready.
	// Deliberately does no work — if it depended on anything else,
	// that dependency failing would restart your pods unnecessarily.
	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	// Phase 3 uses this to push p95 latency past the SLO threshold.
	http.HandleFunc("/slow", func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		time.Sleep(time.Duration(300+rand.Intn(400)) * time.Millisecond)
		w.Write([]byte("that was slow\n"))
		record("/slow", 200, start)
	})

	// Phase 3 uses this to burn error budget and fire the alert.
	http.HandleFunc("/error", func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		http.Error(w, "boom", http.StatusInternalServerError)
		record("/error", 500, start)
	})

	// Prometheus scrapes this endpoint every 15 seconds.
	http.Handle("/metrics", promhttp.Handler())

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Println("listening on :" + port)
	log.Fatal(http.ListenAndServe(":"+port, nil))

}
