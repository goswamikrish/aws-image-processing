from flask import Flask
from flask_cors import CORS

from routes.image_routes import image_bp

app = Flask(__name__)

CORS(app)

app.register_blueprint(image_bp)

if __name__ == "__main__":
    app.run(debug=True)