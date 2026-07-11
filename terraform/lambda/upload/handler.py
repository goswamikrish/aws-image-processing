import json
import os
import uuid
import boto3

# Region + endpoint_url MUST match the bucket region.
# endpoint_url forces the presigned URL to use the regional endpoint directly,
# preventing the 307 Temporary Redirect to the global s3.amazonaws.com endpoint.
s3 = boto3.client(
    "s3",
    region_name="eu-north-1",
    endpoint_url="https://s3.eu-north-1.amazonaws.com"
)

# CORS headers returned on every response so browsers allow cross-origin calls
CORS_HEADERS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Content-Type": "application/json"
}

def lambda_handler(event, context):

    # Handle preflight OPTIONS request sent by the browser before POST
    if event.get("requestContext", {}).get("http", {}).get("method") == "OPTIONS":
        return {
            "statusCode": 200,
            "headers": CORS_HEADERS,
            "body": ""
        }

    bucket = os.environ["UPLOAD_BUCKET"]

    # Read content type and process type from request body.
    # Falls back to sensible defaults if not provided.
    content_type = "image/jpeg"
    process_type = "resize"
    if event.get("body"):
        try:
            body = json.loads(event["body"])
            content_type = body.get("contentType", "image/jpeg")
            process_type = body.get("processType", "resize")
        except Exception:
            pass

    # Keep the extension consistent with the content type
    ext = content_type.split("/")[-1] if "/" in content_type else "jpg"

    # Encode processType as a filename prefix so the process Lambda can read it
    # directly from the S3 event key — no metadata headers needed in the PUT.
    filename = f"{process_type}_{uuid.uuid4()}.{ext}"

    upload_url = s3.generate_presigned_url(
        ClientMethod="put_object",
        Params={
            "Bucket": bucket,
            "Key": filename,
            "ContentType": content_type,
        },
        ExpiresIn=300
    )

    return {
        "statusCode": 200,
        "headers": CORS_HEADERS,
        "body": json.dumps({
            "uploadUrl": upload_url,
            "fileName": filename
        })
    }