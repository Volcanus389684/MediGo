from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse
import json

PORT = 8080


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)

        if parsed.path == "/status":
            response = {"status": "READY", "device": "laptop-simulator"}
        elif parsed.path == "/dispense":
            command = parse_qs(parsed.query).get("command", [""])[0]
            print(f"Received ESP32 command: {command}", flush=True)
            response = {"accepted": True, "command": command}
        else:
            self.send_error(404, "Unknown simulator endpoint")
            return

        body = json.dumps(response).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        return


if __name__ == "__main__":
    print(f"MediGo ESP32 simulator listening on port {PORT}.", flush=True)
    print("Keep this window open while testing the app.", flush=True)
    print("Press Ctrl+C to stop.", flush=True)
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
