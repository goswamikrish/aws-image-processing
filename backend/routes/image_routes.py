from flask import Flask, request, jsonify, send_from_directory,Blueprint
from flask_cors import CORS
import os
from werkzeug.utils import secure_filename
from config import UPLOAD_FOLDER, PROCESSED_FOLDER
from services.image_services import process_image
from utils.files_utils import save_uploaded_file,allowed_file,generate_filename

image_bp = Blueprint("image", __name__)


@image_bp.route("/")
def home():
    return jsonify({
        "message":"Backend Running"
    })

@image_bp.route("/upload", methods=["POST"])
def upload_image():

    if "image" not in request.files:

        return jsonify({
            "error":"No image uploaded"
        }),400

    image = request.files["image"]

    if image.filename == "":

        return jsonify({
            "error":"No file selected"
        }),400
    
    if not allowed_file(image.filename):

        return jsonify({
            "error": "Only image files are allowed."
        }), 400
    
    filename, filepath = save_uploaded_file(image)

    process_type = request.form.get("processType")

    processed_filename = process_image(
        filepath,
        filename,
        process_type
    )

    return jsonify({
    "message": "Image Uploaded Successfully",
    "original": image.filename,
    "processed": processed_filename,
    "imageUrl": f"http://localhost:5000/processed/{processed_filename}"
})

@image_bp.route("/processed/<filename>")
def get_processed_image(filename):
    return send_from_directory(PROCESSED_FOLDER, filename)


@image_bp.route("/gallery", methods=["GET"])
def gallery():

    files = os.listdir(PROCESSED_FOLDER)

    images = []

    for file in files:

        images.append({

            "filename": file,

            "url": f"http://127.0.0.1:5000/processed/{file}"

        })

    return jsonify(images)