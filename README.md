# Image Processing AWS Platform

A browser-based image processing app with two backend paths:

- A serverless AWS flow built with Terraform, API Gateway, Lambda, S3, and Pillow.
- A local Flask backend that can process images on the developer machine.

The frontend lets users choose an image, select an operation, upload it, and browse processed images in a gallery. In the current frontend code, uploads and gallery reads are wired to the deployed API Gateway endpoint in `frontend/script.js`.

## Features

- Upload images from the browser.
- Choose one of four processing modes:
  - Resize: fit within an 800 x 800 pixel box.
  - Compress: save with Pillow optimization and quality set to 40.
  - Convert: convert to JPEG/RGB output.
  - Thumbnail: fit within a 200 x 200 pixel box.
- Generate pre-signed S3 upload URLs through Lambda.
- Upload original images directly from the browser to the uploads S3 bucket.
- Process images asynchronously when new uploads land in S3.
- Store processed images in a separate processed S3 bucket.
- Return gallery entries with pre-signed read URLs.
- Provide a local Flask API for development/testing without AWS.

## Tech Stack

### Frontend

- HTML
- CSS
- JavaScript
- Browser `fetch` API
- `FormData` and direct S3 `PUT` uploads through pre-signed URLs

### Local Backend

- Python
- Flask
- Flask-CORS
- Pillow
- Werkzeug filename sanitization

### AWS / Infrastructure

- Terraform
- AWS S3
- AWS Lambda with Python 3.12
- Amazon API Gateway HTTP API
- AWS IAM roles and policies
- Terraform `archive` provider for Lambda zip artifacts

## Project Components Structure

```text
.
|-- README.md
|-- .gitignore
|-- backend
|   |-- app.py
|   |-- config.py
|   |-- requirements.txt
|   |-- routes
|   |   `-- image_routes.py
|   |-- services
|   |   `-- image_services.py
|   |-- utils
|   |   `-- files_utils.py
|   |-- uploads
|   `-- processed
|-- frontend
|   |-- index.html
|   |-- script.js
|   `-- style.css
`-- terraform
    |-- provider.tf
    |-- variables.tf
    |-- main.tf
    |-- outputs.tf
    |-- build
    |   |-- upload.zip
    |   |-- process.zip
    |   `-- gallery.zip
    `-- lambda
        |-- upload
        |   |-- handler.py
        |   `-- requirements.txt
        |-- process
        |   |-- handler.py
        |   |-- requirements.txt
        |   |-- PIL
        |   |-- pillow.libs
        |   `-- pillow-12.2.0.dist-info
        `-- gallery
            |-- handler.py
            `-- requirements.txt
```

### Structure Notes

- `backend/uploads` and `backend/processed` are runtime data folders for the local Flask backend.
- `backend/__pycache__` and nested `__pycache__` folders are generated Python cache files.
- `terraform/build` contains generated Lambda zip packages.
- `terraform/lambda/process/PIL`, `terraform/lambda/process/pillow.libs`, and `terraform/lambda/process/pillow-12.2.0.dist-info` are vendored Pillow dependency files for the image processing Lambda package.
- `terraform/.terraform`, Terraform state files, local variables files, build zips, runtime images, and Python caches are generated or environment-specific files and are usually not committed to source control.

## Component Responsibilities

| Component | Path | Responsibility |
| --- | --- | --- |
| Frontend page | `frontend/index.html` | Defines the upload form, image preview, processing selector, status area, and gallery container. |
| Frontend behavior | `frontend/script.js` | Handles file selection, preview rendering, API calls, pre-signed upload flow, gallery polling, image downloads, and toast messages. |
| Frontend styling | `frontend/style.css` | Provides layout, form controls, buttons, preview states, gallery cards, toast notifications, and responsive styling. |
| Flask app entrypoint | `backend/app.py` | Creates the Flask app, enables CORS, registers the image routes blueprint, and starts the local dev server. |
| Flask config | `backend/config.py` | Defines local upload and processed output directories and creates them when the backend starts. |
| Flask routes | `backend/routes/image_routes.py` | Provides local routes for health checks, image uploads, processed image serving, and gallery listing. |
| Local image service | `backend/services/image_services.py` | Uses Pillow to resize, compress, convert, or thumbnail local image files. |
| Local file utilities | `backend/utils/files_utils.py` | Validates file extensions, sanitizes names, generates UUID filenames, and saves uploaded files. |
| Terraform provider setup | `terraform/provider.tf` | Sets Terraform version/provider requirements and configures the AWS region. |
| Terraform variables | `terraform/variables.tf` | Declares `aws_region`, `project_name`, and `environment`. |
| AWS infrastructure | `terraform/main.tf` | Creates S3 buckets, bucket policies, CORS settings, IAM permissions, Lambda functions, API Gateway routes, and S3 event notifications. |
| Terraform outputs | `terraform/outputs.tf` | Prints bucket names, API endpoint, frontend website URL, project name, and region after apply. |
| Upload Lambda | `terraform/lambda/upload/handler.py` | Handles `POST /upload`, creates a pre-signed S3 `PUT` URL, and encodes the processing type into the object key. |
| Process Lambda | `terraform/lambda/process/handler.py` | Runs from S3 upload events, downloads the uploaded image, processes it with Pillow, and stores the result in the processed bucket. |
| Gallery Lambda | `terraform/lambda/gallery/handler.py` | Handles `GET /gallery`, lists processed S3 objects, and returns pre-signed read URLs. |

## Serverless Request Flow

1. The user selects an image and processing type in the frontend.
2. `frontend/script.js` sends `POST /upload` to API Gateway with the file content type and selected `processType`.
3. API Gateway invokes `terraform/lambda/upload/handler.py`.
4. The upload Lambda returns a pre-signed S3 `PUT` URL and generated object key.
5. The browser uploads the original image directly to the uploads S3 bucket.
6. The uploads bucket emits an `ObjectCreated` event.
7. S3 invokes `terraform/lambda/process/handler.py`.
8. The process Lambda reads the process type from the uploaded object key, downloads the file to `/tmp`, processes it with Pillow, and uploads `processed_<key>` to the processed bucket.
9. The frontend polls `GET /gallery`.
10. API Gateway invokes `terraform/lambda/gallery/handler.py`.
11. The gallery Lambda lists processed objects and returns filenames plus pre-signed read URLs.
12. The frontend renders the processed images and provides view/download actions.

## AWS API

### `POST /upload`

Creates a pre-signed S3 upload URL.

Request body:

```json
{
  "contentType": "image/jpeg",
  "processType": "resize"
}
```

Successful response:

```json
{
  "uploadUrl": "https://...",
  "fileName": "resize_uuid.jpeg"
}
```

The frontend then uploads the file with:

```http
PUT <uploadUrl>
Content-Type: image/jpeg
```

### `GET /gallery`

Lists processed images.

Example response:

```json
[
  {
    "filename": "processed_resize_uuid.jpeg",
    "url": "https://..."
  }
]
```

## Local Flask API

The Flask backend is useful for local development and direct backend testing. It stores uploads in `backend/uploads` and processed outputs in `backend/processed`.

### `GET /`

Health check.

Example response:

```json
{
  "message": "Backend Running"
}
```

### `POST /upload`

Uploads and processes an image locally.

Request type:

```text
multipart/form-data
```

Form fields:

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `image` | File | Yes | Supported extensions: `png`, `jpg`, `jpeg`, `gif`, `webp`. |
| `processType` | String | Yes | One of `resize`, `compress`, `convert`, or `thumbnail`. |

Successful response:

```json
{
  "message": "Image Uploaded Successfully",
  "original": "example.png",
  "processed": "processed_uuid_example.png",
  "imageUrl": "http://localhost:5000/processed/processed_uuid_example.png"
}
```

### `GET /processed/<filename>`

Serves a locally processed image from `backend/processed`.

### `GET /gallery`

Lists local processed images.

Example response:

```json
[
  {
    "filename": "processed_example.png",
    "url": "http://127.0.0.1:5000/processed/processed_example.png"
  }
]
```

## Processing Modes

| Mode | Behavior |
| --- | --- |
| `resize` | Uses Pillow `thumbnail((800, 800))` to preserve aspect ratio inside an 800 x 800 box. |
| `compress` | Saves with `optimize=True` and `quality=40`. |
| `convert` | Converts the image to RGB and writes JPEG output. |
| `thumbnail` | Uses Pillow `thumbnail((200, 200))` to preserve aspect ratio inside a 200 x 200 box. |

## Local Setup

### Prerequisites

- Python 3
- `pip`
- A modern web browser

### 1. Create and Activate a Virtual Environment

From the project root:

```powershell
cd backend
python -m venv venv
.\venv\Scripts\Activate.ps1
```

If PowerShell blocks script execution, use Command Prompt activation:

```bat
venv\Scripts\activate.bat
```

### 2. Install Backend Dependencies

```powershell
pip install -r requirements.txt
```

### 3. Run the Local Backend

Run this from the `backend` directory:

```powershell
python app.py
```

By default, Flask starts at:

```text
http://127.0.0.1:5000
```

### 4. Open the Frontend

Open `frontend/index.html` in a browser.

Important: the current frontend is configured to call this deployed API Gateway URL:

```text
https://txqyd7x425.execute-api.eu-north-1.amazonaws.com
```

To use the local Flask backend instead, update the `API_URL` constants in `frontend/script.js` to:

```text
http://127.0.0.1:5000
```

The local Flask API uses multipart upload, while the current AWS frontend flow uses a JSON pre-signed URL request followed by a direct S3 `PUT`. If you switch back to Flask, the upload logic in `frontend/script.js` must match the Flask route's `multipart/form-data` contract.

## Terraform Deployment

### Prerequisites

- Terraform 1.5 or newer
- AWS credentials configured locally
- Permission to create S3 buckets, Lambda functions, IAM roles/policies, API Gateway HTTP APIs, and S3 bucket notifications

### Variables

`terraform/variables.tf` expects:

| Variable | Description |
| --- | --- |
| `aws_region` | AWS region for the deployment. |
| `project_name` | Prefix used in resource names. |
| `environment` | Environment name used in resource names and tags. |

Example `terraform.tfvars`:

```hcl
aws_region   = "eu-north-1"
project_name = "image-processing"
environment  = "dev"
```

### Commands

Run from the `terraform` directory:

```powershell
terraform init
terraform plan
terraform apply
```

Terraform outputs include:

- `api_endpoint`
- `frontend_url`
- `s3_bucket_uploads`
- `s3_bucket_processed`
- `s3_bucket_frontend`

## Deploying the Frontend to S3

Terraform creates a public S3 website bucket for the frontend. After `terraform apply`, upload the static frontend files to the frontend bucket:

```powershell
aws s3 sync ..\frontend s3://<frontend-bucket-name>
```

Then open the `frontend_url` output.

If Terraform creates a new API endpoint, update the `API_URL` constants in `frontend/script.js` before syncing the frontend files.

## Runtime and Generated Files

The repo currently contains runtime/generated files such as:

- Local uploads in `backend/uploads`
- Local processed files in `backend/processed`
- Python caches in `__pycache__`
- Terraform provider files in `terraform/.terraform`
- Terraform state files
- Terraform build zips in `terraform/build`
- Vendored Pillow files in `terraform/lambda/process`

These files are useful locally, but many teams prefer to ignore generated files and keep only source, configuration, and reproducible packaging instructions in version control.

## Current Limitations

- `frontend/script.js` has the API Gateway URL hardcoded in multiple places.
- The upload and gallery Lambda handlers hardcode the S3 client region/endpoint to `eu-north-1`.
- API Gateway and S3 CORS allow all origins for development.
- The local Flask route does not catch invalid `processType` errors gracefully.
- File validation is extension/content-type based depending on flow; deeper image validation is limited.
- There is no automated test suite yet.
- Terraform state and generated artifacts appear in the working tree and should be handled carefully.

## Suggested Improvements

- Move frontend `API_URL` into a single configuration value.
- Pass the AWS region into Lambda through environment variables instead of hardcoding it.
- Restrict CORS origins to the deployed frontend domain for production.
- Add image size limits and content validation.
- Catch image processing errors and return clean JSON responses.
- Add tests for local processing and Lambda handlers.
- Expand `.gitignore` for runtime images, caches, Terraform state, provider folders, and build artifacts.

## License

No license file is currently included in this repository.
