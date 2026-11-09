"""
CS6650 HW7 - flash sale load tests.

  ENDPOINT=sync|async   which endpoint to hit (default sync)
  TEST=normal           5 users, spawn 1/s, 30 s      (expected: 100% success)
  TEST=flash            20 users, spawn 10/s, 60 s    (the flash sale)
  TIMEOUT=<seconds>     how long a customer waits before giving up (default 60,
                        same as the ALB idle timeout)

Each user waits a random 100-500 ms between orders, as the assignment specifies.
The shape stops the test by itself; just set Host and click Start.
"""
import os
import random

from locust import FastHttpUser, LoadTestShape, between, task

ENDPOINT = os.getenv("ENDPOINT", "sync").strip().lower()
TEST = os.getenv("TEST", "normal").strip().lower()
TIMEOUT = float(os.getenv("TIMEOUT") or 60)

PATH = {"sync": "/orders/sync", "async": "/orders/async"}[ENDPOINT]
SHAPES = {
    #           users, spawn rate, seconds
    "normal": (5, 1, 30),
    "flash": (20, 10, 60),
}

PRODUCTS = [f"SKU-{i:04d}" for i in range(1, 101)]


def random_order():
    return {
        "customer_id": random.randint(1, 100_000),
        "items": [
            {
                "product_id": random.choice(PRODUCTS),
                "quantity": random.randint(1, 3),
                "price": round(random.uniform(5, 200), 2),
            }
            for _ in range(random.randint(1, 3))
        ],
    }


class Shopper(FastHttpUser):
    wait_time = between(0.1, 0.5)
    network_timeout = TIMEOUT
    connection_timeout = TIMEOUT

    @task
    def place_order(self):
        expected = 200 if ENDPOINT == "sync" else 202
        with self.client.post(PATH, json=random_order(), name=PATH, catch_response=True) as r:
            if r.status_code == expected:
                r.success()
            else:
                r.failure(f"HTTP {r.status_code}")


class FlashSaleShape(LoadTestShape):
    users, spawn_rate, duration = SHAPES[TEST]

    def tick(self):
        if self.get_run_time() >= self.duration:
            return None  # ends the test
        return self.users, self.spawn_rate
