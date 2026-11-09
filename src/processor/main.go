// Order Processor: polls SQS forever and verifies payments in the background.
//
// WORKERS (env, default 1) = how many orders may be in payment verification at
// once. That is the Phase 5 knob: processing rate ~= WORKERS / 3 s.
//
// Loop (per poller):
//  1. Reserve at least 1 free worker slot (blocks while all workers are busy),
//     then grab up to 9 more if they are free.
//  2. ReceiveMessage with long polling (20 s) for exactly that many messages.
//  3. Each message -> its own goroutine: sleep 3 s, DeleteMessage, free slot.
//
// Why reserve slots BEFORE receiving? A received message is hidden for the
// visibility timeout (30 s). With 1 worker, grabbing a batch of 10 means the
// 10th waits 27 s + 3 s of work = 30 s, so SQS would make it visible again and
// deliver it twice. Never take more messages than you can start right away.
//
// Env: QUEUE_URL, WORKERS, POLLERS (default WORKERS/20, 1..10), AWS_REGION.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/aws/aws-sdk-go-v2/service/sqs/types"
)

type Item struct {
	ProductID string  `json:"product_id"`
	Quantity  int     `json:"quantity"`
	Price     float64 `json:"price"`
}

type Order struct {
	OrderID    string    `json:"order_id"`
	CustomerID int       `json:"customer_id"`
	Status     string    `json:"status"`
	Items      []Item    `json:"items"`
	CreatedAt  time.Time `json:"created_at"`
}

const paymentDelay = 3 * time.Second

var (
	client   *sqs.Client
	queueURL string
	slots    chan struct{} // one token per worker

	processed, failed, inFlight atomic.Int64
	wg                          sync.WaitGroup
)

func envInt(name string, def int) int {
	if v, err := strconv.Atoi(os.Getenv(name)); err == nil && v > 0 {
		return v
	}
	return def
}

func process(m types.Message) {
	defer wg.Done()
	defer func() { <-slots; inFlight.Add(-1) }()

	var o Order
	if err := json.Unmarshal([]byte(aws.ToString(m.Body)), &o); err != nil {
		// Poison message: log it and delete it so it doesn't loop forever.
		log.Printf(`{"level":"error","msg":"bad message body","err":%q}`, err.Error())
	} else {
		time.Sleep(paymentDelay) // payment verification
		o.Status = "completed"
	}

	// Delete only AFTER processing: if the task dies first, the message becomes
	// visible again after 30 s and another worker retries it (at-least-once).
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if _, err := client.DeleteMessage(ctx, &sqs.DeleteMessageInput{
		QueueUrl: aws.String(queueURL), ReceiptHandle: m.ReceiptHandle,
	}); err != nil {
		failed.Add(1)
		log.Printf(`{"level":"error","msg":"delete failed","order_id":%q,"err":%q}`, o.OrderID, err.Error())
		return
	}
	processed.Add(1)
}

func poll(ctx context.Context, id int) {
	for ctx.Err() == nil {
		// 1. Block until at least one worker is free...
		select {
		case slots <- struct{}{}:
		case <-ctx.Done():
			return
		}
		reserved := 1
		// ...then take up to 9 more free workers without blocking.
	more:
		for reserved < 10 {
			select {
			case slots <- struct{}{}:
				reserved++
			default:
				break more
			}
		}

		// 2. Long poll for exactly `reserved` messages.
		out, err := client.ReceiveMessage(ctx, &sqs.ReceiveMessageInput{
			QueueUrl:            aws.String(queueURL),
			MaxNumberOfMessages: int32(reserved),
			WaitTimeSeconds:     20,
		})
		got := 0
		if err == nil {
			got = len(out.Messages)
		} else if !errors.Is(err, context.Canceled) {
			log.Printf(`{"level":"error","msg":"receive failed","poller":%d,"err":%q}`, id, err.Error())
			time.Sleep(time.Second)
		}

		// Give back the slots we reserved but didn't fill.
		for i := got; i < reserved; i++ {
			<-slots
		}
		// 3. One goroutine per message (each already owns a slot).
		if got > 0 {
			for _, m := range out.Messages {
				inFlight.Add(1)
				wg.Add(1)
				go process(m)
			}
		}
	}
}

func main() {
	workers := envInt("WORKERS", 1)
	defPollers := workers / 20
	if defPollers < 1 {
		defPollers = 1
	}
	if defPollers > 10 {
		defPollers = 10
	}
	pollers := envInt("POLLERS", defPollers)
	queueURL = os.Getenv("QUEUE_URL")
	slots = make(chan struct{}, workers)

	cfg, err := config.LoadDefaultConfig(context.Background())
	if err != nil {
		log.Fatalf("aws config: %v", err)
	}
	client = sqs.NewFromConfig(cfg)

	// /health for the ECS container health check (the processor has no ALB).
	go func() {
		http.HandleFunc("/health", func(w http.ResponseWriter, _ *http.Request) {
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte(`{"status":"ok"}`))
		})
		log.Fatal(http.ListenAndServe(":8080", nil))
	}()

	// Throughput line every 10 s: this is the measured "processing rate".
	go func() {
		var last int64
		for range time.Tick(10 * time.Second) {
			p := processed.Load()
			log.Printf(`{"msg":"stats","workers":%d,"in_flight":%d,"processed_total":%d,"processed_last_10s":%d,"rate_per_s":%.2f,"delete_failures":%d}`,
				workers, inFlight.Load(), p, p-last, float64(p-last)/10, failed.Load())
			last = p
		}
	}()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	log.Printf(`{"msg":"processor starting","workers":%d,"pollers":%d,"queue":%q}`, workers, pollers, queueURL)
	var pw sync.WaitGroup
	for i := 0; i < pollers; i++ {
		pw.Add(1)
		go func(id int) { defer pw.Done(); poll(ctx, id) }(i)
	}
	pw.Wait()
	// ECS sends SIGTERM on deploy/stop: finish in-flight orders (≤ 3 s) first.
	log.Printf(`{"msg":"shutting down, waiting for in-flight orders","in_flight":%d}`, inFlight.Load())
	wg.Wait()
}
