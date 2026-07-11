import json
import os
import boto3

# Region + endpoint_url MUST match the bucket region and match the upload handler.
# Without these, boto3 defaults to the global s3.amazonaws.com endpoint and
# signs pre-signed URLs for the wrong region, causing SignatureDoesNotMatch.
s3 = boto3.client(
    "s3",
    region_name="eu-north-1",
    endpoint_url="https://s3.eu-north-1.amazonaws.com"
)

BUCKET = os.environ["PROCESSED_BUCKET"]

# CORS headers so the browser allows cross-origin fetch() calls to this endpoint
CORS_HEADERS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Content-Type": "application/json"
}


def lambda_handler(event, context):

    response = s3.list_objects_v2(
        Bucket=BUCKET
    )

    images = []

    for obj in response.get("Contents", []):

        key = obj["Key"]

        url = s3.generate_presigned_url(
            "get_object",
            Params={
                "Bucket": BUCKET,
                "Key": key
            },
            ExpiresIn=3600
        )

        images.append({
            "filename": key,
            "url": url
        })

    return {
        "statusCode": 200,
        "headers": CORS_HEADERS,
        "body": json.dumps(images)
    }