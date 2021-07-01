import base64
import sys

sys.path.append("vendors")
import requests

ROOT_PAGE = "ede524fe18db48c4b6565b37968d7203"

NOTION_ROOT = "https://www.notion.so"
LOGIN_JS = """
(function() {
  var body = document.querySelector("body");
  var observer = new MutationObserver(function(mutations) {
    var login = document.querySelector("#notion-app main div.notion-login");
    if (login) {
      console.log("Login detected.");
      var url = new URL(location.href);
      url.host = "www.notion.so";
      location.replace(url.href);
    }
  });
  observer.observe(body, { childList: true, subtree: true });
})();
"""


def lambda_handler(event, context):
    if event["httpMethod"] == "OPTIONS":
        return handle_options(event)

    path = event["path"]
    if path == "/":
        return {
            "statusCode": 301,
            "headers": {
                "Location": f"https://vibe.pub/{ROOT_PAGE}",
            },
        }
    elif path.startswith("/app") and path.endswith(".js"):
        return handle_app_js(path, event)
    elif path.startswith("/api"):
        return handle_api(path, event)
    else:
        return forward_path(path, event)


def handle_options(event):
    request_headers = event.get("headers", {})
    if (
        "Origin" in request_headers
        and "Access-Control-Request-Method" in request_headers
        and "Access-Control-Request-Headers" in request_headers
    ):
        return {
            "statusCode": 200,
            "headers": {
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET, HEAD, POST, PUT, OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type",
            },
            "body": None,
            "isBase64Encoded": False,
        }
    else:
        return {
            "statusCode": 200,
            "headers": {
                "Allow": "GET, HEAD, POST, PUT, OPTIONS",
            },
            "body": None,
            "isBase64Encoded": False,
        }


def handle_app_js(path, event):
    resp = requests.request(event["httpMethod"], NOTION_ROOT + path)
    body = resp.text.replace("/www.notion.so", "/vibe.pub")
    body += LOGIN_JS
    headers = clean_up_response_headers(resp.headers)
    return {
        "statusCode": resp.status_code,
        "headers": headers,
        "body": body,
        "isBase64Encoded": False,
    }


def handle_api(path, event):
    return forward_path(path, event)


def forward_path(path, event):
    body = event.get("body")
    query = event.get("queryStringParameters")

    if body and event.get("isBase64Encoded", False):
        body = base64.b64decode(body)

    resp = requests.request(
        event["httpMethod"],
        NOTION_ROOT + path,
        headers=clean_up_request_headers(event["headers"]),
        data=body,
        params=query,
    )
    return {
        "statusCode": resp.status_code,
        "headers": clean_up_response_headers(resp.headers),
        "body": base64.b64encode(resp.content),
        "isBase64Encoded": True,
    }


def clean_up_request_headers(headers):
    copy = {}
    for k, v in headers.items():
        k = k.lower()
        if k.startswith("cloudfront") or k.startswith("x-"):
            continue
        if k == "host" or k == "via" or k == "referer" or k == "accept-encoding":
            continue
        copy[k] = v
    return copy


def clean_up_response_headers(headers):
    copy = {}
    for k, v in headers.items():
        k = k.lower()
        if (
            k == "content-encoding"
            or k == "content-security-policy"
            or k == "x-content-security-policy"
        ):
            continue
        copy[k] = v
    return copy
