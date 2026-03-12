import json
import logging
import os
from datetime import datetime

import boto3
from botocore.exceptions import ClientError
from flask import Flask, jsonify, request
from prometheus_client import Counter, Histogram
from prometheus_flask_exporter import PrometheusMetrics

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s – %(message)s",
)
logger = logging.getLogger("email-checker")

app = Flask(__name__)

metrics = PrometheusMetrics(app)
metrics.info("email_checker_info", "Email Checker – REST API", version="1.0.0")

REQUEST_COUNT = Counter(
    "email_checker_requests_total", "Total /send requests", ["status"]
)
SQS_PUBLISH_LATENCY = Histogram(
    "email_checker_sqs_publish_duration_seconds", "Time to publish to SQS"
)
TOKEN_VALIDATION_FAILURES = Counter(
    "email_checker_token_validation_failures_total", "Token validation failures"
)

AWS_REGION = os.getenv("AWS_REGION", "eu-west-1")
SQS_QUEUE_URL = os.getenv("QUEUE_URL", "")

sqs_client = boto3.client("sqs", region_name=AWS_REGION)
ssm_client = boto3.client("ssm", region_name=AWS_REGION)


def get_expected_token() -> str:
    """Fetch the expected API token from SSM Parameter Store (SecureString)."""
    try:
        response = ssm_client.get_parameter(
            Name="/email-checker/validation-token", WithDecryption=True
        )
        TOKEN = response["Parameter"]["Value"]
        return TOKEN
    except ClientError as exc:
        logger.error("Failed to retrieve token from SSM: %s", exc)
        raise


REQUIRED_DATA_FIELDS = {
    "email_subject",
    "email_sender",
    "email_timestream",
    "email_content",
}


def validate_payload(payload: dict) -> tuple[bool, str]:
    """
    Returns (is_valid, error_message).
    Checks:
      1. 'token' field presence and correctness.
      2. 'data' field presence and all four required text sub-fields.
    """
    if "token" not in payload:
        return False, "Missing 'token' field"

    try:
        expected = get_expected_token()
    except Exception:
        return False, "Token validation service unavailable"

    if payload["token"] != expected:
        TOKEN_VALIDATION_FAILURES.inc()
        return False, "Invalid token"

    if "data" not in payload:
        return False, "Missing 'data' field"

    data = payload["data"]
    if not isinstance(data, dict):
        return False, "'data' must be a JSON object"

    missing = REQUIRED_DATA_FIELDS - data.keys()
    if missing:
        return False, f"Missing data fields: {', '.join(sorted(missing))}"

    for field in REQUIRED_DATA_FIELDS:
        if not isinstance(data[field], str) or not data[field].strip():
            return False, f"Field '{field}' must be a non-empty string"

    return True, ""


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "healthy", "service": "email-checker"}), 200


@app.route("/ready", methods=["GET"])
def ready():
    """
    Readiness probe – confirms the service can actually do its job:
      1. SSM is reachable and the token parameter exists.
      2. SQS queue is reachable.
    Returns 200 only when both checks pass; 503 otherwise so Kubernetes
    stops routing traffic until dependencies recover.
    """
    checks = {}

    try:
        get_expected_token()
        checks["ssm"] = "ok"
    except ClientError as exc:
        checks["ssm"] = f"error: {exc.response['Error']['Code']}"
    except Exception as exc:
        checks["ssm"] = f"error: {exc}"

    try:
        sqs_client.get_queue_attributes(
            QueueUrl=SQS_QUEUE_URL,
            AttributeNames=["ApproximateNumberOfMessages"],
        )
        checks["sqs"] = "ok"
    except ClientError as exc:
        checks["sqs"] = f"error: {exc.response['Error']['Code']}"
    except Exception as exc:
        checks["sqs"] = f"error: {exc}"

    all_ok = all(v == "ok" for v in checks.values())
    return jsonify({"ready": all_ok, "checks": checks}), 200 if all_ok else 503


@app.route("/send", methods=["POST"])
def send_message():
    """
    Accepts the email payload, validates it, then publishes to SQS.

    Expected JSON body:
    {
        "data": {
            "email_subject": "...",
            "email_sender": "...",
            "email_timestream": "...",
            "email_content": "..."
        },
        "token": "..."
    }
    """
    payload = request.get_json(silent=True)
    if payload is None:
        REQUEST_COUNT.labels(status="client_error").inc()
        logger.warning("Received non-JSON request body")
        return jsonify({"error": "Request body must be valid JSON"}), 400

    is_valid, error_msg = validate_payload(payload)
    if not is_valid:
        REQUEST_COUNT.labels(status="validation_error").inc()
        logger.warning("Validation failed: %s", error_msg)
        return jsonify({"error": error_msg}), 422

    message_body = {
        "data": payload["data"],
        "received_at": datetime.utcnow().isoformat() + "Z",
    }

    try:
        with SQS_PUBLISH_LATENCY.time():
            response = sqs_client.send_message(
                QueueUrl=SQS_QUEUE_URL,
                MessageBody=json.dumps(message_body),
            )
        message_id = response["MessageId"]
        REQUEST_COUNT.labels(status="success").inc()
        logger.info("Message published to SQS. MessageId=%s", message_id)
        return jsonify({"status": "published", "message_id": message_id}), 200
    except ClientError as exc:
        REQUEST_COUNT.labels(status="server_error").inc()
        logger.error("Failed to send message to SQS: %s", exc)
        return jsonify({"error": "Failed to publish message"}), 500
