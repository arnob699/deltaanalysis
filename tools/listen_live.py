import subprocess
import time
import json
import urllib.request
import tempfile
import websocket

chrome_path = r'C:\Program Files\Google\Chrome\Application\chrome.exe'
tmp_profile = tempfile.mkdtemp()
cmd = [chrome_path, '--headless=new', '--remote-debugging-port=9245', '--remote-allow-origins=*', f'--user-data-dir={tmp_profile}', '--disable-gpu', 'http://localhost/']
proc = subprocess.Popen(cmd)
time.sleep(2)

try:
    tabs_res = urllib.request.urlopen('http://localhost:9245/json')
    tabs = json.loads(tabs_res.read().decode('utf-8'))
    ws_url = None
    for t in tabs:
        if 'localhost' in t.get('url', ''):
            ws_url = t.get('webSocketDebuggerUrl')
            break
    ws = websocket.create_connection(ws_url, timeout=10)

    ws.send(json.dumps({'id': 1, 'method': 'Runtime.enable'}))
    ws.send(json.dumps({'id': 2, 'method': 'Console.enable'}))

    # Switch to Live Chart
    ws.send(json.dumps({'id': 3, 'method': 'Runtime.evaluate', 'params': {'expression': "document.getElementById('nav-btn-livechart').click();"}}))

    # Listen to console and runtime events for 6 seconds to see if 1-second updates throw errors!
    start = time.time()
    events = []
    ws.settimeout(1.0)
    while time.time() - start < 6.0:
        try:
            raw = ws.recv()
            data = json.loads(raw)
            method = data.get('method', '')
            if 'console' in method.lower() or 'exception' in method.lower():
                print('EVENT:', method, data.get('params'))
        except Exception:
            pass

    ws.close()
finally:
    proc.terminate()

