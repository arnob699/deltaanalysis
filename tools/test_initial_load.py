import subprocess
import time
import json
import urllib.request
import tempfile
import base64
import websocket

chrome_path = r'C:\Program Files\Google\Chrome\Application\chrome.exe'
tmp_profile = tempfile.mkdtemp()
cmd = [chrome_path, '--headless=new', '--remote-debugging-port=9250', '--remote-allow-origins=*', f'--user-data-dir={tmp_profile}', '--disable-gpu', '--window-size=1600,1200', 'about:blank']
proc = subprocess.Popen(cmd)
time.sleep(2)

try:
    tabs_res = urllib.request.urlopen('http://localhost:9250/json')
    tabs = json.loads(tabs_res.read().decode('utf-8'))
    ws_url = tabs[0].get('webSocketDebuggerUrl')
    ws = websocket.create_connection(ws_url, timeout=10)

    ws.send(json.dumps({'id': 1, 'method': 'Page.enable'}))
    ws.recv()
    ws.send(json.dumps({'id': 2, 'method': 'Runtime.enable'}))
    ws.recv()

    # Navigate to http://localhost/
    ws.send(json.dumps({'id': 3, 'method': 'Page.navigate', 'params': {'url': 'http://localhost/'}}))
    ws.recv()

    # Wait 3 seconds for initial render
    time.sleep(3)

    # Take screenshot of page
    ws.send(json.dumps({'id': 4, 'method': 'Page.captureScreenshot', 'params': {'format': 'png'}}))
    
    start_time = time.time()
    while time.time() - start_time < 10.0:
        raw = ws.recv()
        data = json.loads(raw)
        if data.get('id') == 4 and 'result' in data:
            img = base64.b64decode(data['result']['data'])
            with open('tools/screenshot_initial_load.png', 'wb') as f:
                f.write(img)
            print(f'Screenshot saved! {len(img)} bytes -> tools/screenshot_initial_load.png')
            break

    ws.close()
finally:
    proc.terminate()
