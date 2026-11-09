// Order Receiver: the public API behind the ALB.
//
//	GET  /health        -> 200 (ALB + ECS health checks)
//	POST /orders/sync   -> verify payment inline (3 s, limited slots) -> 200 OK
//	POST /orders/async  -> publish to SNS -> 202 Accepted (< 100 ms)
//
// Env: SNS_TOPIC_ARN, PAYMENT_SLOTS (default 1), PORT (default 8080), AWS_REGION.
package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"strconv"
	"sync/atomic"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sns"
)

type Item struct {
	ProductID string  `json:"product_id"`
	Quantity  int     `json:"quantity"`
	Price     float64 `json:"price"`
}

type Order struct {
	OrderID    string    `json:"order_id"`
	CustomerID int       `json:"customer_id"`
	Status     string    `json:"status"` // pending, processing, completed
	Items      []Item    `json:"items"`
	CreatedAt  time.Time `json:"created_at"`
}

const paymentDelay = 3 * time.Second

var (
	// paymentSlots simulates the payment processor's capacity. time.Sleep alone
	// would NOT create a bottleneck: a sleeping goroutine frees its OS thread, so
	// thousands of requests could "verify" in parallel. A buffered channel used
	// as a semaphore caps how many verifications run at once.
	// Capacity 1 = "1 order per 3 seconds" (0.33 orders/s total).
	paymentSlots chan struct{}

	snsClient *sns.Client
	topicARN  string

	syncDone, asyncAccepted, asyncFailed atomic.Int64
	syncWaiting                          atomic.Int64
)

func newOrderID() string {
	b := make([]byte, 8)
	_, _ = rand.Read(b)
	return "ord-" + hex.EncodeToString(b)
}

// decodeOrder reads the request body and fills in the server-side fields.
func decodeOrder(r *http.Request) (Order, error) {
	var o Order
	if err := json.NewDecoder(r.Body).Decode(&o); err != nil {
		return o, err
	}
	o.OrderID = newOrderID()
	o.CreatedAt = time.Now().UTC()
	o.Status = "pending"
	return o, nil
}

func verifyPayment(ctx context.Context) error {
	syncWaiting.Add(1)
	defer syncWaiting.Add(-1)
	select {
	case paymentSlots <- struct{}{}: // wait for a free slot
	case <-ctx.Done(): // client (or ALB) gave up while queued
		return ctx.Err()
	}
	defer func() { <-paymentSlots }()
	time.Sleep(paymentDelay)
	return nil
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func handleSync(w http.ResponseWriter, r *http.Request) {
	o, err := decodeOrder(r)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
		return
	}
	o.Status = "processing"
	if err := verifyPayment(r.Context()); err != nil {
		return // client is gone; nothing to write
	}
	o.Status = "completed"
	syncDone.Add(1)
	writeJSON(w, http.StatusOK, o)
}

func handleAsync(w http.ResponseWriter, r *http.Request) {
	o, err := decodeOrder(r)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
		return
	}
	body, _ := json.Marshal(o)
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	_, err = snsClient.Publish(ctx, &sns.PublishInput{
		TopicArn: aws.String(topicARN),
		Message:  aws.String(string(body)),
	})
	if err != nil {
		asyncFailed.Add(1)
		log.Printf(`{"level":"error","msg":"sns publish failed","err":%q}`, err.Error())
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "could not queue order"})
		return
	}
	asyncAccepted.Add(1)
	writeJSON(w, http.StatusAccepted, o)
}

func main() {
	slots := 1
	if v, err := strconv.Atoi(os.Getenv("PAYMENT_SLOTS")); err == nil && v > 0 {
		slots = v
	}
	paymentSlots = make(chan struct{}, slots)

	topicARN = os.Getenv("SNS_TOPIC_ARN")
	cfg, err := config.LoadDefaultConfig(context.Background())
	if err != nil {
		log.Fatalf("aws config: %v", err)
	}
	snsClient = sns.NewFromConfig(cfg)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	mux := http.NewServeMux() // Go 1.22+ method-aware patterns
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})
	mux.HandleFunc("POST /orders/sync", handleSync)
	mux.HandleFunc("POST /orders/async", handleAsync)

	// One stats line every 10 s in CloudWatch Logs, handy for the report.
	go func() {
		for range time.Tick(10 * time.Second) {
			log.Printf(`{"msg":"stats","sync_completed":%d,"sync_waiting":%d,"async_accepted":%d,"async_failed":%d,"payment_slots":%d}`,
				syncDone.Load(), syncWaiting.Load(), asyncAccepted.Load(), asyncFailed.Load(), slots)
		}
	}()

	log.Printf(`{"msg":"receiver starting","port":%q,"payment_slots":%d,"topic":%q}`, port, slots, topicARN)
	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
		// No WriteTimeout: a sync request may legitimately wait in line for a
		// payment slot. The ALB's 60 s idle timeout is the real cut-off.
	}
	log.Fatal(srv.ListenAndServe())
}
