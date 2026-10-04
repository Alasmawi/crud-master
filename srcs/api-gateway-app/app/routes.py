import os
from decimal import Decimal, InvalidOperation

import requests
from flask import Blueprint, Response, jsonify, request

from app.rabbitmq import publish_billing_message

gateway_bp = Blueprint("gateway", __name__)

BILLING_FIELDS = ("user_id", "number_of_items", "total_amount")


def inventory_base_url():
    return os.environ["INVENTORY_API_URL"]


def _proxy_to_inventory(path):
    """Forward the request as-is and return Inventory's response unchanged."""
    headers = {}
    if request.content_type:
        headers["Content-Type"] = request.content_type
    try:
        resp = requests.request(
            method=request.method,
            url=f"{inventory_base_url()}{path}",
            params=request.args,
            data=request.get_data(),
            headers=headers,
            timeout=10,
        )
    except requests.RequestException:
        return jsonify({"error": "inventory service unavailable"}), 502
    return Response(resp.content, status=resp.status_code, content_type=resp.headers.get("Content-Type"))


@gateway_bp.route("/api/movies", methods=["GET", "POST", "DELETE"], strict_slashes=False)
def movies_collection():
    return _proxy_to_inventory("/api/movies")


@gateway_bp.route("/api/movies/<int:movie_id>", methods=["GET", "PUT", "DELETE"], strict_slashes=False)
def movies_item(movie_id):
    return _proxy_to_inventory(f"/api/movies/{movie_id}")


def _billing_error(payload):
    """Return an error message if the order can't be processed, else None."""
    if not isinstance(payload, dict):
        return "body must be a JSON object"
    missing = [f for f in BILLING_FIELDS if f not in payload]
    if missing:
        return f"missing fields: {', '.join(missing)}"
    try:
        if int(payload["number_of_items"]) < 0:
            return "number_of_items must be >= 0"
    except (TypeError, ValueError):
        return "number_of_items must be an integer"
    try:
        if not Decimal(str(payload["total_amount"])).is_finite():
            raise InvalidOperation
    except InvalidOperation:
        return "total_amount must be a number"
    return None


@gateway_bp.route("/api/billing", methods=["POST"], strict_slashes=False)
def billing():
    payload = request.get_json(silent=True)
    if payload is None:
        return jsonify({"error": "invalid or missing JSON body"}), 400

    error = _billing_error(payload)
    if error:
        return jsonify({"error": error}), 400

    try:
        publish_billing_message(payload)
    except Exception:
        return jsonify({"error": "message broker unavailable"}), 502

    return jsonify({"message": "Message posted"}), 200
