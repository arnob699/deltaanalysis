import subprocess
import time
import json
import urllib.request
import tempfile
import base64
import websocket

chrome_path = r'C:\Program Files\Google\Chrome\Application\chrome.exe'
tmp_profile = tempfile.mkdtemp()
cmd = [chrome_path, '--headless=new', '--remote-debugging-port=9230', '--remote-allow-origins=*', f'--user-data-dir={tmp_profile}', '--disable-gpu', '--window-size=1600,1200', 'http://localhost/']
proc = subprocess.Popen(cmd)
time.sleep(2)

try:
    tabs_res = urllib.request.urlopen('http://localhost:9230/json')
    tabs = json.loads(tabs_res.read().decode('utf-8'))
    ws_url = tabs[0].get('webSocketDebuggerUrl')
    ws = websocket.create_connection(ws_url, timeout=10)

    # 1. Click Live Chart button
    click_msg = {
        'id': 1,
        'method': 'Runtime.evaluate',
        'params': {
            'expression': "document.getElementById('nav-btn-livechart').click();"
        }
    }
    ws.send(json.dumps(click_msg))
    time.sleep(2)

    # 2. Capture screenshot
    ss_msg = {'id': 2, 'method': 'Page.captureScreenshot', 'params': {'format': 'png'}}
    ws.send(json.dumps(ss_msg))

    while True:
        raw = ws.recv()
        data = json.loads(raw)
        if data.get('id') == 2:
            img_bytes = base64.b64decode(data['result']['data'])
            with open('tools/live_chart_actual.png', 'wb') as f:
                f.write(img_bytes)
            print('Screenshot saved successfully: tools/live_chart_actual.png (bytes:', len(img_bytes), ')')
            break

    ws.close()
finally:
    proc.terminate()

