// Part III: the same payment verification, triggered directly by SNS.
// No queue and no workers: AWS starts one execution environment per
// concurrent order and bills per millisecond.
//
// Build: ../../scripts/build_lambda.sh  (produces ./bootstrap for provided.al2)
package main

import (
	"context"
	"encoding/json"
	"log"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
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

// Runs once per execution environment, i.e. only on a COLD start. Its time is
// part of the "Init Duration" in the REPORT log line.
var coldStart = true

func handler(ctx context.Context, ev events.SNSEvent) error {
	cold := coldStart
	coldStart = false
	for _, rec := range ev.Records {
		var o Order
		if err := json.Unmarshal([]byte(rec.SNS.Message), &o); err != nil {
			log.Printf(`{"level":"error","msg":"bad SNS message","err":%q}`, err.Error())
			continue // returning an error would make SNS retry a message that can never parse
		}
		time.Sleep(3 * time.Second) // payment verification
		o.Status = "completed"
		lag := time.Since(o.CreatedAt).Milliseconds()
		log.Printf(`{"msg":"order completed","order_id":%q,"customer_id":%d,"cold_start":%t,"ms_since_created":%d}`,
			o.OrderID, o.CustomerID, cold, lag)
	}
	return nil
}

func main() { lambda.Start(handler) }
