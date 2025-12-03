"""
Worker Service - Message Processor
Triggered by Pub/Sub messages, processes data, and stores in Firestore.
"""
import os
import json
import base64
import time
import re
from datetime import datetime
from flask import Flask, request, jsonify
from google.cloud import firestore

app = Flask(__name__)

# Initialize Firestore client
db = firestore.Client()


def simulate_heavy_processing(text: str) -> str:
    """
    Simulate CPU-bound processing.
    Sleeps 0.05 seconds per character (100 chars = 5 seconds).
    
    Also performs a simple "redaction" of phone numbers as an example
    of data transformation.
    """
    # Calculate sleep time based on text length
    sleep_time = len(text) * 0.05
    
    # Cap at 30 seconds to prevent timeout (Cloud Run default is 300s)
    sleep_time = min(sleep_time, 30)
    
    print(f"Processing {len(text)} characters, sleeping for {sleep_time:.2f} seconds")
    time.sleep(sleep_time)
    
    # Simple redaction: replace phone number patterns with [REDACTED]
    # Pattern matches formats like: 555-0199, (555) 123-4567, 555.123.4567
    redacted_text = re.sub(
        r'\b\d{3}[-.\s]?\d{3,4}[-.\s]?\d{4}\b',
        '[REDACTED]',
        text
    )
    
    return redacted_text


def save_to_firestore(tenant_id: str, log_id: str, original_text: str, 
                       modified_text: str, source: str, received_at: str) -> None:
    """
    Save processed data to Firestore with proper tenant isolation.
    
    Structure: tenants/{tenant_id}/processed_logs/{log_id}
    
    This ensures strict multi-tenant isolation using sub-collections.
    """
    # Reference to the document with tenant isolation
    doc_ref = db.collection("tenants").document(tenant_id) \
                .collection("processed_logs").document(log_id)
    
    # Document data matching the required schema
    doc_data = {
        "source": source,
        "original_text": original_text,
        "modified_data": modified_text,
        "processed_at": datetime.utcnow().isoformat() + "Z",
        "received_at": received_at,
        "text_length": len(original_text)
    }
    
    # Save to Firestore
    doc_ref.set(doc_data)
    print(f"Saved document: tenants/{tenant_id}/processed_logs/{log_id}")


@app.route("/", methods=["POST"])
def process_pubsub():
    """
    Handle Pub/Sub push messages.
    
    Pub/Sub delivers messages in this format:
    {
        "message": {
            "data": "<base64-encoded-message>",
            "attributes": {...},
            "messageId": "...",
            "publishTime": "..."
        },
        "subscription": "..."
    }
    """
    try:
        envelope = request.get_json()
        
        if not envelope:
            return jsonify({"error": "No Pub/Sub message received"}), 400
        
        if "message" not in envelope:
            return jsonify({"error": "Invalid Pub/Sub message format"}), 400
        
        pubsub_message = envelope["message"]
        
        # Decode the base64 message data
        if "data" in pubsub_message:
            message_data = base64.b64decode(pubsub_message["data"]).decode("utf-8")
            message = json.loads(message_data)
        else:
            return jsonify({"error": "No data in Pub/Sub message"}), 400
        
        # Extract fields from the normalized message
        tenant_id = message.get("tenant_id")
        log_id = message.get("log_id")
        text = message.get("text")
        source = message.get("source")
        received_at = message.get("received_at")
        
        if not all([tenant_id, log_id, text, source]):
            return jsonify({"error": "Missing required fields in message"}), 400
        
        print(f"Processing message for tenant: {tenant_id}, log: {log_id}")
        
        # Simulate heavy processing
        modified_text = simulate_heavy_processing(text)
        
        # Save to Firestore with tenant isolation
        save_to_firestore(
            tenant_id=tenant_id,
            log_id=log_id,
            original_text=text,
            modified_text=modified_text,
            source=source,
            received_at=received_at
        )
        
        # Return 200 to acknowledge the message
        # If we return anything other than 2xx, Pub/Sub will retry
        return jsonify({
            "status": "processed",
            "tenant_id": tenant_id,
            "log_id": log_id
        }), 200
    
    except Exception as e:
        print(f"Error processing message: {str(e)}")
        # Return 500 to trigger Pub/Sub retry
        # This handles the "crash recovery" requirement
        return jsonify({"error": str(e)}), 500


@app.route("/health", methods=["GET"])
def health():
    """Health check endpoint."""
    return jsonify({"status": "healthy"}), 200


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=False)

