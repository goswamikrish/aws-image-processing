import os
import boto3
from PIL import Image

s3 = boto3.client("s3")

UPLOAD_BUCKET = os.environ["UPLOAD_BUCKET"]
PROCESSED_BUCKET = os.environ["PROCESSED_BUCKET"]


def lambda_handler(event, context):

    # Get S3 event information
    record = event["Records"][0]

    key = record["s3"]["object"]["key"]

    # Extract processType from the filename prefix set by the upload Lambda.
    # Key format: "{processType}_{uuid}.{ext}" — e.g. "resize_abc123.jpg"
    # Falls back to "resize" if the key doesn't follow the expected format.
    process_type = key.split("_")[0] if "_" in key else "resize"

    # Temporary files
    input_path = f"/tmp/{key}"
    output_path = f"/tmp/processed_{key}"

    print(f"Downloading {key}")

    s3.download_file(
        UPLOAD_BUCKET,
        key,
        input_path
    )

    # Process image
    process_image(
        input_path,
        output_path,
        process_type
    )

    print("Uploading processed image")

    s3.upload_file(
        output_path,
        PROCESSED_BUCKET,
        f"processed_{key}"
    )

    print("Image processed successfully")

    return {
        "statusCode": 200
    }


def process_image(input_path, output_path, process_type):

    img = Image.open(input_path)

    if process_type == "resize":

        img.thumbnail((800, 800))

        img.save(output_path)

    elif process_type == "compress":

        img.save(
            output_path,
            optimize=True,
            quality=40
        )

    elif process_type == "convert":

        rgb = img.convert("RGB")

        rgb.save(output_path, "JPEG")

    elif process_type == "thumbnail":

        img.thumbnail((200, 200))

        img.save(output_path)

    else:

        raise ValueError(f"Unsupported process type: {process_type}")