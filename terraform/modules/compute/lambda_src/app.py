"""
CampusHub FastAPI Backend Starter Handler (Lambda compatible via Mangum)
"""
import os
import json

def lambda_handler(event, context):
    """
    AWS Lambda handler function.
    Can be replaced with `Mangum(app)` when running the full FastAPI container / zip.
    """
    path = event.get("rawPath", event.get("path", "/"))
    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")
    service_name = os.environ.get("SERVICE_NAME", "CampusHub Service")
    environment = os.environ.get("ENVIRONMENT", "dev")

    response_body = {
        "service": service_name,
        "environment": environment,
        "status": "healthy",
        "path": path,
        "method": method,
        "message": f"Welcome to CampusHub {service_name} API!"
    }

    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*"
        },
        "body": json.dumps(response_body)
    }
