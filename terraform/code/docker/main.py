from http.server import BaseHTTPRequestHandler, HTTPServer
import json,random,urllib
from cgi import parse_header, parse_multipart
from urllib.parse import parse_qs

hostName = "0.0.0.0"
serverPort = 80

def get_quote(in_actor):
  actor = in_actor.decode('utf-8')
  with open('./data/quotes.json', 'r') as f:
     data = json.load(f)
  try:
     quote = data[actor][random.randint(0,len(data[actor]) -1)]
  except:
     quote = "No quote available for " + actor
  return(quote)

hello_msg = "Server running..."
class MyServer(BaseHTTPRequestHandler):
    def _set_headers(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/json')
        self.end_headers()

    def do_GET(self):
        self.respond_OK(hello_msg)

    def do_POST(self):
        print("Post")

        data = self.parse_POST()
        author = list(data.keys())[0]
        output = json.dumps(get_quote(author) )
        print(output)
        self.respond_OK(output)

    def parse_POST(self):
        ctype, pdict = parse_header(self.headers['content-type'])
        if ctype == 'multipart/form-data':
            postvars = parse_multipart(self.rfile, pdict)
        elif ctype == 'application/x-www-form-urlencoded':
            length = int(self.headers['content-length'])
            postvars = parse_qs(
                    self.rfile.read(length), 
                    keep_blank_values=1)
        else:
            postvars = {}

    
        return postvars

    def respond_OK(self, msg):
        self.send_response(200)
        self.send_header("Content-type", "text/json")
        self.end_headers()
        self.wfile.write(bytes(msg, "utf-8"))


if __name__ == "__main__":
    webServer = HTTPServer((hostName, serverPort), MyServer)
    print("Server started http://%s:%s" % (hostName, serverPort))

    try:
        webServer.serve_forever()
    except KeyboardInterrupt:
        pass

    webServer.server_close()
    print("Server stopped.")
