import subprocess
import time
import json
import urllib.request
import tempfile
import base64
import websocket

chrome_path = r'C:\Program Files\Google\Chrome\Application\chrome.exe'
tmp_profile = tempfile.mkdtemp()
cmd = [chrome_path, '--headless=new', '--remote-debugging-port=9247', '--remote-allow-origins=*', f'--user-data-dir={tmp_profile}', '--disable-gpu', '--window-size=1600,1200', 'http://localhost/']
proc = subprocess.Popen(cmd)
time.sleep(2)

try:
    tabs_res = urllib.request.urlopen('http://localhost:9247/json')
    tabs = json.loads(tabs_res.read().decode('utf-8'))
    ws_url = None
    for t in tabs:
        if 'localhost' in t.get('url', ''):
            ws_url = t.get('webSocketDebuggerUrl')
            break
    ws = websocket.create_connection(ws_url, timeout=10)

    # 1. Click Live Chart button
    ws.send(json.dumps({'id': 1, 'method': 'Runtime.evaluate', 'params': {'expression': "document.getElementById('nav-btn-livechart').click();"}}))
    ws.recv()

    # Wait for data to load and render
    time.sleep(3)

    # 2. Check data state and simulate crosshair hover
    check_script = """
    (function() {
        const totalCandles = candleMapByTime ? candleMapByTime.size : 0;
        
        // Pick a candle from 2 days ago to test crosshair hover pointing
        let sampleCandle = null;
        if (candleMapByTime && candleMapByTime.size > 150) {
            const arr = Array.from(candleMapByTime.values());
            sampleCandle = arr[arr.length - 150];
        }

        // Test hover pointing
        let hoverResult = 'None';
        if (sampleCandle && tvChartMain) {
            // Trigger crosshair move on main chart
            tvChartDelta.setCrosshairPosition(sampleCandle.delta || 0, sampleCandle.time, seriesDelta);
            tvChartRatio.setCrosshairPosition(sampleCandle.ratio || 50, sampleCandle.time, seriesRatio);
            renderRecordToLegend(sampleCandle);
            hoverResult = {
                hoverTime: sampleCandle.time,
                legend: document.getElementById('tv-legend-bar') ? document.getElementById('tv-legend-bar').innerText : ''
            };
        }

        return {
            activeView: activeView,
            isTvInitialized: isTvInitialized,
            totalCandles: totalCandles,
            latestBarRecord: latestBarRecord,
            visibleRange: tvChartMain ? tvChartMain.timeScale().getVisibleRange() : null,
            hoverResult: hoverResult,
            mainCanvases: document.getElementById('tv-chart-main') ? document.getElementById('tv-chart-main').querySelectorAll('canvas').length : 0,
            deltaCanvases: document.getElementById('tv-chart-delta') ? document.getElementById('tv-chart-delta').querySelectorAll('canvas').length : 0,
            ratioCanvases: document.getElementById('tv-chart-ratio') ? document.getElementById('tv-chart-ratio').querySelectorAll('canvas').length : 0,
        };
    })()
    """
    ws.send(json.dumps({'id': 2, 'method': 'Runtime.evaluate', 'params': {'expression': check_script, 'returnByValue': True}}))
    msg = ws.recv()
    state = json.loads(msg).get('result', {}).get('result', {}).get('value')
    print("CHART DATA AND CANVAS STATE:")
    print(json.dumps(state, indent=2))

    # 3. Take screenshot
    ws.send(json.dumps({'id': 3, 'method': 'Page.captureScreenshot', 'params': {'format': 'png'}}))
    screenshot_msg = ws.recv()
    b64_data = json.loads(screenshot_msg).get('result', {}).get('data')
    if b64_data:
        with open('tools/actual_live_chart_screenshot.png', 'wb') as f:
            f.write(base64.b64decode(b64_data))
        print(f"Screenshot saved! {len(b64_data)} bytes -> tools/actual_live_chart_screenshot.png")

finally:
    proc.kill()
