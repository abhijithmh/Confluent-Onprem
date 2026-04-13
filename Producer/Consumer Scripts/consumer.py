from confluent_kafka import Consumer, KafkaError
import json
import socket

# Configuration
# Run: kubectl port-forward kafka-0 9092:9092 -n confluent
conf = {
    'bootstrap.servers': 'localhost:9092',
    'group.id': 'my-consumer-group',
    'client.id': socket.gethostname(),
    'auto.offset.reset': 'earliest'
}

consumer = Consumer(conf)
topic = "product"
consumer.subscribe([topic])

print(f"Subscribed to '{topic}' via localhost:9092")
print("Waiting for messages... (Press Ctrl+C to stop)\n")

try:
    while True:
        msg = consumer.poll(timeout=1.0)

        if msg is None:
            continue

        if msg.error():
            if msg.error().code() == KafkaError._PARTITION_EOF:
                continue
            else:
                print(f"❌ Error: {msg.error()}")
                break

        # Deserialize JSON
        try:
            value = json.loads(msg.value().decode('utf-8'))
            print(f"↓ Received | key={msg.key().decode()} | "
                  f"partition={msg.partition()} | offset={msg.offset()}")
            print(f"  payload: {json.dumps(value, indent=2)}\n")
        except json.JSONDecodeError:
            print(f"↓ Received (raw): {msg.value().decode('utf-8')}")

except KeyboardInterrupt:
    print("\nStopping consumer gracefully...")
finally:
    consumer.close()
    print("Consumer closed.")
