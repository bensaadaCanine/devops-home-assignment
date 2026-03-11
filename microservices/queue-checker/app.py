import json
import logging
import os
import time
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError
from prometheus_client import Counter, Gauge, Histogram, start_http_server

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s – %(message)s",
)
logger = logging.getLogger("queue-checker")

AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
SQS_QUEUE_URL = os.getenv("QUEUE_URL", "")
S3_BUCKET_NAME = os.getenv("S3_BUCKET_NAME", "")
S3_PREFIX = os.getenv("S3_PREFIX", "emails/")
POLL_INTERVAL_SEC = int(os.getenv("POLL_INTERVAL_SEC", "10"))
MAX_MESSAGES = int(os.getenv("MAX_MESSAGES", "10"))
VISIBILITY_TIMEOUT = int(os.getenv("VISIBILITY_TIMEOUT", "30"))
METRICS_PORT = int(os.getenv("METRICS_PORT", "9090"))

sqs_client = boto3.client("sqs", region_name=AWS_REGION)
s3_client = boto3.client("s3", region_name=AWS_REGION)

MESSAGES_PROCESSED = Counter(
    "queue_checker_messages_processed_total", "Messages successfully processed"
)
MESSAGES_FAILED = Counter(
    "queue_checker_messages_failed_total", "Failed messages", ["reason"]
)
S3_UPLOAD_LATENCY = Histogram(
    "queue_checker_s3_upload_duration_seconds", "S3 upload latency"
)
POLL_DURATION = Histogram(
    "queue_checker_poll_duration_seconds", "SQS poll cycle duration"
)
QUEUE_MESSAGES_RECEIVED = Counter(
    "queue_checker_sqs_messages_received_total", "Total SQS messages received"
)
LAST_POLL_TIMESTAMP = Gauge(
    "queue_checker_last_poll_timestamp_seconds", "Unix ts of last SQS poll"
)


def build_s3_key(message_id: str) -> str:
    now = datetime.now(timezone.utc)
    return (
        f"{S3_PREFIX}"
        f"year={now.year:04d}/"
        f"month={now.month:02d}/"
        f"day={now.day:02d}/"
        f"{message_id}.json"
    )


def upload_to_s3(message_id: str, body: dict) -> str:
    key = build_s3_key(message_id)
    with S3_UPLOAD_LATENCY.time():
        s3_client.put_object(
            Bucket=S3_BUCKET_NAME,
            Key=key,
            Body=json.dumps(body, ensure_ascii=False, indent=2),
            ContentType="application/json",
        )
    logger.info("Uploaded %s -> s3://%s/%s", message_id, S3_BUCKET_NAME, key)
    return key


def receive_messages() -> list:
    response = sqs_client.receive_message(
        QueueUrl=SQS_QUEUE_URL,
        MaxNumberOfMessages=MAX_MESSAGES,
        WaitTimeSeconds=5,
        VisibilityTimeout=VISIBILITY_TIMEOUT,
        AttributeNames=["All"],
        MessageAttributeNames=["All"],
    )
    return response.get("Messages", [])


def delete_message(receipt_handle: str) -> None:
    sqs_client.delete_message(QueueUrl=SQS_QUEUE_URL, ReceiptHandle=receipt_handle)


def process_message(msg: dict) -> bool:
    message_id = msg["MessageId"]
    receipt_handle = msg["ReceiptHandle"]

    try:
        body = json.loads(msg["Body"])
    except json.JSONDecodeError as exc:
        logger.error("Bad JSON in message %s: %s", message_id, exc)
        MESSAGES_FAILED.labels(reason="bad_json").inc()
        return False

    try:
        upload_to_s3(message_id, body)
    except ClientError as exc:
        logger.error("S3 upload failed for %s: %s", message_id, exc)
        MESSAGES_FAILED.labels(reason="s3_error").inc()
        return False

    try:
        delete_message(receipt_handle)
        logger.info("Deleted message %s from SQS", message_id)
    except ClientError as exc:
        logger.warning("Could not delete message %s: %s", message_id, exc)

    MESSAGES_PROCESSED.inc()
    return True


def run_poll_loop() -> None:
    logger.info(
        "Starting SQS consumer | queue=%s | bucket=%s | interval=%ds",
        SQS_QUEUE_URL,
        S3_BUCKET_NAME,
        POLL_INTERVAL_SEC,
    )
    while True:
        with POLL_DURATION.time():
            try:
                messages = receive_messages()
                LAST_POLL_TIMESTAMP.set_to_current_time()
                if not messages:
                    logger.debug("No messages. Sleeping %ds.", POLL_INTERVAL_SEC)
                else:
                    QUEUE_MESSAGES_RECEIVED.inc(len(messages))
                    logger.info("Received %d message(s)", len(messages))
                    for msg in messages:
                        process_message(msg)
            except ClientError as exc:
                logger.error("AWS error during poll: %s", exc)
            except Exception as exc:
                logger.exception("Unexpected error: %s", exc)
        time.sleep(POLL_INTERVAL_SEC)


start_http_server(METRICS_PORT)
logger.info("Prometheus metrics on :%d/metrics", METRICS_PORT)
run_poll_loop()
