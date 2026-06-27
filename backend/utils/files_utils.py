import os
import uuid
from werkzeug.utils import secure_filename

from config import UPLOAD_FOLDER
ALLOWED_EXTENSIONS = {
    "png",
    "jpg",
    "jpeg",
    "gif",
    "webp"
}
def allowed_file(filename):

    return (
        "." in filename
        and
        filename.rsplit(".",1)[1].lower()
        in ALLOWED_EXTENSIONS
    )
def generate_filename(filename):

    filename = secure_filename(filename)

    unique_id = uuid.uuid4()

    return f"{unique_id}_{filename}"
def save_uploaded_file(image):

    filename = generate_filename(image.filename)

    filepath = os.path.join(
        UPLOAD_FOLDER,
        filename
    )

    image.save(filepath)

    return filename, filepath
