"""
API Service - Unified Ingestion Gateway
Handles POST /ingest endpoint for JSON and TXT payloads
"""
import os
import json
import uuid
from datetime import datetime
from flask import Flask, request, jsonify
from google.cloud import pubsub_v1

app = Flask(__name__)

# Configuration
PROJECT_ID = os.environ.get("GCP_PROJECT_ID", "your-project-id")
TOPIC_ID = os.environ.get("PUBSUB_TOPIC_ID", "ingest-topic")

# Initialize Pub/Sub publisher
publisher = pubsub_v1.PublisherClient()
topic_path = publisher.topic_path(PROJECT_ID, TOPIC_ID)


def normalize_to_internal_format(tenant_id: str, log_id: str, text: str, source: str) -> dict:
    """
    Normalize all inputs to a single internal format.
    This creates a consistent message structure regardless of input type.
    """
    return {
        "tenant_id": tenant_id,
        "log_id": log_id,
        "text": text,
        "source": source,
        "received_at": datetime.utcnow().isoformat() + "Z"
    }


def publish_to_pubsub(message: dict) -> str:
    """
    Publish normalized message to Pub/Sub.
    Returns the message ID on success.
    """
    message_json = json.dumps(message)
    message_bytes = message_json.encode("utf-8")
    
    # Publish with tenant_id as attribute for potential filtering
    future = publisher.publish(
        topic_path,
        message_bytes,
        tenant_id=message["tenant_id"]
    )
    return future.result()


@app.route("/ingest", methods=["POST"])
def ingest():
    """
    Unified ingestion endpoint.
    
    Handles two scenarios:
    1. JSON payload with Content-Type: application/json
       Body: {"tenant_id": "acme", "log_id": "123", "text": "..."}
    
    2. Plain text with Content-Type: text/plain
       Header: X-Tenant-ID: acme
       Body: Raw text string
    """
    try:
        content_type = request.content_type or ""
        
        # Scenario 1: JSON payload
        if "application/json" in content_type:
            data = request.get_json()
            
            if not data:
                return jsonify({"error": "Invalid JSON payload"}), 400
            
            # Validate required fields
            tenant_id = data.get("tenant_id")
            text = data.get("text")
            
            if not tenant_id:
                return jsonify({"error": "Missing tenant_id"}), 400
            if not text:
                return jsonify({"error": "Missing text"}), 400
            
            # Use provided log_id or generate one
            log_id = data.get("log_id", str(uuid.uuid4()))
            source = "json_upload"
        
        # Scenario 2: Plain text payload
        elif "text/plain" in content_type:
            # Extract tenant from header
            tenant_id = request.headers.get("X-Tenant-ID")
            
            if not tenant_id:
                return jsonify({"error": "Missing X-Tenant-ID header"}), 400
            
            text = request.get_data(as_text=True)
            
            if not text:
                return jsonify({"error": "Empty text payload"}), 400
            
            # Generate log_id for text uploads
            log_id = str(uuid.uuid4())
            source = "text_upload"
        
        else:
            return jsonify({
                "error": "Unsupported Content-Type. Use application/json or text/plain"
            }), 415
        
        # Normalize the data
        normalized_message = normalize_to_internal_format(
            tenant_id=tenant_id,
            log_id=log_id,
            text=text,
            source=source
        )
        
        # Publish to Pub/Sub (async - non-blocking)
        message_id = publish_to_pubsub(normalized_message)
        
        # Return 202 Accepted immediately
        return jsonify({
            "status": "accepted",
            "message_id": message_id,
            "log_id": log_id,
            "tenant_id": tenant_id
        }), 202
    
    except Exception as e:
        # Log the error (in production, use proper logging)
        print(f"Error processing request: {str(e)}")
        return jsonify({"error": "Internal server error"}), 500


@app.route("/health", methods=["GET"])
def health():
    """Health check endpoint for Cloud Run."""
    return jsonify({"status": "healthy"}), 200


@app.route("/", methods=["GET"])
def root():
    """Root endpoint with API info."""
    return jsonify({
        "service": "Unified Ingestion Gateway",
        "version": "1.0.0",
        "endpoints": {
            "POST /ingest": "Ingest JSON or TXT data",
            "GET /health": "Health check"
        }
    }), 200


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=False)

