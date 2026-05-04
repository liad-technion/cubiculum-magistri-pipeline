import os

from flask import Flask, jsonify

APP_NAME = "cubiculum-magistri-app"
APP_VERSION = os.environ.get("APP_VERSION", "dev")
APP_ENV = os.environ.get("APP_ENV", "local")

app = Flask(__name__)


@app.get("/")
def index():
    return jsonify(app=APP_NAME, version=APP_VERSION, env=APP_ENV)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
