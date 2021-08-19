import requests
from chalice import Chalice, Response

ROOT_PAGE = "ede524fe18db48c4b6565b37968d7203"
MY_DOMAIN = "vibe.pub"
NOTION_DOMAIN = "vibeus.notion.site"

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

app = Chalice(app_name='notion-proxy')
app.api.binary_types = [ "*/*" ] 

@app.route('/', methods=["GET", "HEAD", "OPTIONS"])
def index():
    if app.current_request.method == "OPTIONS":
        return handle_options()

    return Response(None,
            status_code=302,
                    headers={
                        "Location": f"https://{MY_DOMAIN}/{ROOT_PAGE}",
                        })


@app.route('/{proxy+}', methods=["GET", "POST", "PUT", "PATCH", "HEAD", "OPTIONS"])
def proxy():
    if app.current_request.method == "OPTIONS":
        return handle_options()

    path = app.current_request.uri_params.get("proxy")
    if path.startswith("api/") or path.startswith("image/") or path.startswith("images/"):
        return forward()

    if path.startswith("app") and path.endswith(".js"):
        def api_rewriter(content):
            s = content.decode("utf-8")
            s += LOGIN_JS
            return s.encode("utf-8")

        return forward(api_rewriter)

    def body_rewriter(content):
        s = content.decode("utf-8")
        s = s.replace('domainBaseUrl:"https://www.notion.so"', f'domainBaseUrl:"https://{MY_DOMAIN}"')
        return s.encode("utf-8")

    return forward(body_rewriter)


def handle_options():
    r = qpp.current_request

    request_headers = r.headers
    if (
        "Origin" in request_headers
        and "Access-Control-Request-Method" in request_headers
        and "Access-Control-Request-Headers" in request_headers
    ):
        return Response(
                None,
            status_code= 200,
            headers= {
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET, HEAD, POST, PUT, OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type",
            })
    else:
        return Response(
            status_code= 200,
            headers= {
                "Allow": "GET, HEAD, POST, PUT, OPTIONS",
            })


def forward(body_rewriter = None):
    r = app.current_request
    path = r.uri_params["proxy"]

    resp = requests.request(
            r.method,
            f"https://{NOTION_DOMAIN}/{path}",
            headers=clean_up_request_headers(r.headers),
            data=r.raw_body,
            params=r.query_params)

    content = resp.content
    if body_rewriter:
        content = body_rewriter(content)

    return Response(
            content,
            status_code=resp.status_code,
            headers=clean_up_response_headers(resp.headers))

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
            or k == "content-length"
            or k == "content-security-policy"
            or k == "x-content-security-policy"
        ):
            continue
        copy[k] = v
    return copy
