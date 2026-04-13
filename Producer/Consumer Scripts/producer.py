from confluent_kafka import Producer
import json
import socket
import time

# Configuration
# Run: kubectl port-forward kafka-0 9092:9092 -n confluent
conf = {
    'bootstrap.servers': 'localhost:9092',
    'client.id': socket.gethostname(),
    'acks': 'all'
}

def delivery_report(err, msg):
    if err is not None:
        print(f'❌ Delivery failed: {err}')
    else:
        print(f'✅ Delivered to {msg.topic()} [partition {msg.partition()}] offset {msg.offset()}')

producer = Producer(conf)
topic = "product"

print(f"Producing to topic: '{topic}' via localhost:9092")
print("Press Ctrl+C to stop\n")

try:
    count = 0
    while True:
        count += 1
        data = {
            "user": "abhijith",
            "action": "learning_kafka",
            "message_id": count,
            "timestamp": time.time()
        }
        producer.produce(
            topic,
            key=f"user-{count}",
            value=json.dumps(data),
            callback=delivery_report
        )
        producer.poll(0)  # Trigger delivery callbacks
        print(f"↑ Sent message #{count}")
        time.sleep(2)    # Produce every 2 seconds

except KeyboardInterrupt:
    print("\nFlushing remaining messages...")
    producer.flush()
    print("Producer stopped.")
except Exception as e:
    print(f"Error: {e}")
    producer.flush()