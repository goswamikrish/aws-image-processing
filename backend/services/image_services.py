from PIL import Image
import os
from config import PROCESSED_FOLDER


def process_image(filepath, filename, process_type):
    """
    Processes an uploaded image based on the selected process type.

    Parameters:
        filepath (str): Path to the uploaded image.
        filename (str): Original filename.
        process_type (str): resize, compress, convert, or thumbnail.

    Returns:
        str: Name of the processed file.
    """

    img = Image.open(filepath)

    processed_filename = "processed_" + filename
    processed_path = os.path.join(
        PROCESSED_FOLDER,
        processed_filename
    )

    if process_type == "resize":

        img.thumbnail((800, 800))
        img.save(processed_path)

    elif process_type == "compress":

        img.save(
            processed_path,
            optimize=True,
            quality=40
        )

    elif process_type == "convert":

        processed_filename = (
            os.path.splitext(filename)[0] + ".jpg"
        )

        processed_path = os.path.join(
            PROCESSED_FOLDER,
            processed_filename
        )

        rgb = img.convert("RGB")
        rgb.save(processed_path)

    elif process_type == "thumbnail":

        img.thumbnail((200, 200))
        img.save(processed_path)

    else:
        raise ValueError("Invalid process type")

    return processed_filename