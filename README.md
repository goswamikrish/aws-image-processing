# Image Processing Platform

A small image-processing web app with a static frontend and a Flask backend. Users can upload an image, choose a processing operation, and view the processed result in the browser.

The current code runs locally. The UI title says "Serverless Image Processing Platform", but this repository does not currently include AWS infrastructure, Lambda handlers, S3 integration, or deployment templates.

## Features

- Upload an image from the browser.
- Choose one of four processing modes:
  - Resize: scales the image down to fit within 800 x 800 pixels.
  - Compress: saves the image with optimization enabled and JPEG-style quality set to 40.
  - Convert to JPEG: converts the uploaded image to RGB and saves it with a `.jpg` extension.
  - Thumbnail: scales the image down to fit within 200 x 200 pixels.
- Store uploaded source files in `backend/uploads`.
- Store processed images in `backend/processed`.
- Serve processed images through the backend so the frontend can preview them.

## Tech Stack

### Frontend

- HTML
- CSS
- JavaScript
- Browser `fetch` API
- `FormData` for multipart uploads

### Backend

- Python
- Flask
- Flask-CORS
- Pillow
- Werkzeug filename sanitization

## Project Structure

```text
.
|-- README.md
|-- backend
|   |-- app.py
|   |-- config.py
|   |-- requirements.txt
|   |-- processed
|   |-- services
|   |   `-- image_services.py
|   |-- uploads
|   `-- utils
|       `-- files_utils.py
`-- frontend
    |-- index.html
    |-- script.js
    `-- style.css
```

### Important Files

`backend/app.py`

Main Flask application. It defines:

- `GET /` health-style route that returns a JSON message.
- `POST /upload` route that receives an uploaded image and processing type.
- `GET /processed/<filename>` route that serves processed image files.

`backend/config.py`

Stores folder names for uploads and processed output:

- `UPLOAD_FOLDER = "uploads"`
- `PROCESSED_FOLDER = "processed"`

It also creates those folders if they do not exist.

`backend/services/image_services.py`

Contains the image processing logic using Pillow. The main function is:

```python
process_image(filepath, filename, process_type)
```

It opens the uploaded image, applies the selected operation, writes the processed image to the processed folder, and returns the processed filename.

`backend/utils/files_utils.py`

Currently empty. This is a natural place to add reusable file helpers later, such as extension validation, filename generation, cleanup utilities, or upload-size checks.

`frontend/index.html`

Defines the user interface:

- File input
- Processing dropdown
- Upload button
- Status area
- Processed image preview

`frontend/script.js`

Handles the upload workflow in the browser:

1. Reads the selected image file.
2. Reads the selected processing type.
3. Sends both values to `http://127.0.0.1:5000/upload`.
4. Displays the backend response.
5. Updates the preview image using the returned `imageUrl`.

`frontend/style.css`

Contains basic page styling for the frontend.

## Backend API

### `GET /`

Checks whether the backend is running.

Example response:

```json
{
  "message": "Backend Running"
}
```

### `POST /upload`

Uploads and processes an image.

Request type:

```text
multipart/form-data
```

Form fields:

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `image` | File | Yes | The image to upload and process. |
| `processType` | String | Yes | One of `resize`, `compress`, `convert`, or `thumbnail`. |

Successful response:

```json
{
  "message": "Image Uploaded Successfully",
  "original": "example.png",
  "processed": "processed_example.png",
  "imageUrl": "http://localhost:5000/processed/processed_example.png"
}
```

Possible error responses:

```json
{
  "error": "No image uploaded"
}
```

```json
{
  "error": "No file selected"
}
```

Note: if an invalid `processType` is submitted, `process_image` raises `ValueError("Invalid process type")`. The current route does not catch that exception, so Flask will return a server error in that case.

### `GET /processed/<filename>`

Serves a processed image file from the processed output directory.

Example:

```text
http://localhost:5000/processed/processed_example.png
```

## Processing Modes

### Resize

```python
img.thumbnail((800, 800))
```

Creates an image that fits within an 800 x 800 bounding box while preserving aspect ratio. Pillow's `thumbnail` method modifies the image object in place.

### Compress

```python
img.save(processed_path, optimize=True, quality=40)
```

Saves an optimized version of the image. The current implementation keeps the generated filename as `processed_<original filename>`.

### Convert

```python
rgb = img.convert("RGB")
rgb.save(processed_path)
```

Converts the image to RGB and saves it with a `.jpg` extension. Unlike the other modes, this output filename is based on the original filename without the `processed_` prefix:

```text
original.png -> original.jpg
```

### Thumbnail

```python
img.thumbnail((200, 200))
```

Creates a smaller preview image that fits within a 200 x 200 bounding box while preserving aspect ratio.

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

If PowerShell blocks script execution, you can use Command Prompt activation instead:

```bat
venv\Scripts\activate.bat
```

### 2. Install Backend Dependencies

```powershell
pip install -r requirements.txt
```

### 3. Run the Backend

Run this from the `backend` directory:

```powershell
python app.py
```

By default, Flask starts at:

```text
http://127.0.0.1:5000
```

You can confirm the backend is running by opening:

```text
http://127.0.0.1:5000/
```

### 4. Open the Frontend

Open `frontend/index.html` in a browser.

The frontend sends upload requests to:

```text
http://127.0.0.1:5000/upload
```

Because the backend enables CORS, the static frontend can call the Flask API even when opened directly from the filesystem.

## Usage

1. Start the Flask backend.
2. Open `frontend/index.html`.
3. Choose an image file.
4. Select a processing mode from the dropdown.
5. Click `Upload Image`.
6. View the response details and processed image preview.

## Example cURL Request

From the project root, replace `path\to\image.png` with a real image path:

```powershell
curl.exe -X POST http://127.0.0.1:5000/upload `
  -F "image=@path\to\image.png" `
  -F "processType=resize"
```

## Runtime Folders

The backend uses two runtime folders:

- `backend/uploads`: stores the original uploaded files.
- `backend/processed`: stores generated processed files.

These folders may contain user-uploaded or generated images. They are application data, not source code.

## Current Limitations

- No AWS integration is implemented yet.
- No file size limit is configured.
- No explicit file extension or MIME-type validation is implemented.
- Invalid processing types are not handled gracefully by the upload route.
- Uploaded files with the same sanitized filename can overwrite earlier uploads.
- Processed files with the same generated filename can overwrite earlier outputs.
- `frontend/script.js` uses `127.0.0.1:5000` for uploads, while the backend response uses `localhost:5000` in `imageUrl`.
- There is no automated test suite yet.
- `backend/utils/files_utils.py` is currently empty.
- The checked-in `backend/venv` directory is a local environment and is usually excluded from source control in production projects.

## Suggested Improvements

- Add a `.gitignore` for `venv`, `__pycache__`, uploads, and processed outputs.
- Add validation for allowed image extensions and content types.
- Add a maximum upload size with Flask's `MAX_CONTENT_LENGTH`.
- Generate unique filenames to avoid overwriting files.
- Catch processing errors and return clean JSON error responses.
- Move API base URL into a frontend configuration constant.
- Add tests for the upload route and each image processing mode.
- Add AWS deployment support if the target is truly serverless, such as:
  - S3 buckets for uploads and processed images.
  - Lambda image processing function.
  - API Gateway endpoint.
  - Infrastructure as Code using AWS SAM, Serverless Framework, Terraform, or CloudFormation.

## Development Notes

- The backend imports `UPLOAD_FOLDER` and `PROCESSED_FOLDER` from `config.py`.
- `config.py` creates the upload and processed folders relative to the process working directory. Run the backend from `backend` so the files are stored inside `backend/uploads` and `backend/processed`.
- `secure_filename` is used before saving uploads, which helps reduce unsafe filename characters.
- Pillow operations preserve aspect ratio for resize and thumbnail modes.
- CORS is enabled globally with `CORS(app)`.

## License

No license file is currently included in this repository.
