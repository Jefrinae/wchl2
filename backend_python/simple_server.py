#!/usr/bin/env python3
"""
Simple HTTP server for testing RapidResQ alert functionality
"""
import json
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs
import threading

class SimpleAlertServer(BaseHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        self.active_alerts = {}
        super().__init__(*args, **kwargs)

    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok", "firebase": False}).encode())

        elif self.path == '/alerts/active':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            # Return mock active alerts
            alerts = [
                {
                    "id": "alert_1",
                    "reporter": "Test User",
                    "message": "Medical Emergency",
                    "lat": 12.9716,
                    "lon": 77.5946,
                    "timestamp": int(time.time() * 1000),
                    "status": "active"
                }
            ]
            self.wfile.write(json.dumps({"alerts": alerts}).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)
        data = json.loads(post_data.decode('utf-8'))

        if self.path == '/send_alert':
            # Generate mock alert ID
            alert_id = f"alert_{int(time.time())}"
            self.active_alerts[alert_id] = data

            response = {
                "status": "ok",
                "firestore_doc_id": f"fs_{alert_id}",
                "icp": {
                    "alert_id": alert_id,
                    "status": "broadcasting",
                    "message": "Alert sent successfully"
                }
            }

            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(response).encode())

        elif self.path == '/cancel_alert':
            alert_id = data.get('alert_id')
            if alert_id in self.active_alerts:
                del self.active_alerts[alert_id]
                response = {
                    "status": "cancelled",
                    "icp": {
                        "alert_id": alert_id,
                        "status": "cancelled",
                        "message": "Alert cancelled successfully"
                    }
                }
            else:
                response = {
                    "status": "error",
                    "message": "Alert not found"
                }

            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(response).encode())

        elif self.path == '/alerts/resolve':
            response = {
                "status": "ok",
                "alert_id": data.get('alert_id'),
                "message": "Alert resolved"
            }

            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(response).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        # Suppress default logging
        pass

def run_server():
    server_address = ('0.0.0.0', 8000)
    httpd = HTTPServer(server_address, SimpleAlertServer)
    print("🚀 Simple Alert Server running on http://0.0.0.0:8000")
    print("📡 Available endpoints:")
    print("  GET  /health")
    print("  GET  /alerts/active")
    print("  POST /send_alert")
    print("  POST /cancel_alert")
    print("  POST /alerts/resolve")
    print("Press Ctrl+C to stop")
    httpd.serve_forever()

if __name__ == '__main__':
    run_server()