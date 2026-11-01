/**
 * Public Activity Delta — Gold (XAU/USD) Flow & Sentiment Terminal
 * Engineered for institutional traders with live spot price streaming,
 * multi-day session archives, and 12-hour Bangladesh Standard Time (BST).
 */

let deltaChart = null;
let currentMode = 'increase'; // 'increase' | 'decrease' | 'combined'
let sortDesc = true;          // Newest 20m slice first by default
let filterText = '';
let masterData = null;
let activeDayData = null;
let selectedDate = null;      // null = Today (Live), or 'YYYY.MM.DD'
let pollInterval = null;
let clockInterval = null;
let previousBidPrice = null;

document.addEventListener('DOMContentLoaded', () => {
  initLiveBstClock();
  initEventListeners();
  initChart();
  fetchDeltaData();
  startPolling();
});

/* ==========================================================================
   1. LIVE BANGLADESH TIME (BST, UTC+6) 12-HOUR CLOCK
   ========================================================================== */

function initLiveBstClock() {
  function updateClock() {
    const el = document.getElementById('banner-bst-time');
    if (!el) return;
    
    // Bangladesh Standard Time is UTC+6
    const now = new Date();
    const utcMs = now.getTime() + (now.getTimezoneOffset() * 60000);
    const bstDate = new Date(utcMs + (6 * 3600000));
    
    let hours = bstDate.getHours();
    const minutes = String(bstDate.getMinutes()).padStart(2, '0');
    const seconds = String(bstDate.getSeconds()).padStart(2, '0');
    const ampm = hours >= 12 ? 'PM' : 'AM';
    
    hours = hours % 12;
    hours = hours ? hours : 12;
    const strHours = String(hours).padStart(2, '0');
    
    el.textContent = `${strHours}:${minutes}:${seconds} ${ampm}`;
  }
  
  updateClock();
  clockInterval = setInterval(updateClock, 1000);
}

function formatCurrency(num) {
  if (num === null || num === undefined || isNaN(num)) return '$0.00';
  return '$' + Number(num).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function formatDelta(num) {
  if (num === null || num === undefined || isNaN(num)) return '0.00%';
  const prefix = num > 0 ? '+' : '';
  return `${prefix}${num.toFixed(2)}%`;
}

function getDeltaColorClass(num) {
  if (num > 0.0001) return 'val-pos';
  if (num < -0.0001) return 'val-neg';
  return 'val-neutral';
}

/* ==========================================================================
   2. EVENT LISTENERS
   ========================================================================== */

function initEventListeners() {
  // Manual refresh button
  const btnRefresh = document.getElementById('btn-manual-refresh');
  if (btnRefresh) {
    btnRefresh.addEventListener('click', triggerManualRefresh);
  }

  // Modal refresh button
  const modalRefresh = document.getElementById('modal-action-refresh');
  if (modalRefresh) {
    modalRefresh.addEventListener('click', () => {
      closeDiagnosticsModal();
      triggerManualRefresh();
    });
  }

  // Quick "Today (Live)" button
  const btnToday = document.getElementById('btn-today-quick');
  if (btnToday) {
    btnToday.addEventListener('click', () => {
      selectDay(null);
    });
  }

  // Return to Today link from archive notice bar
  const btnReturnToday = document.getElementById('btn-return-live');
  if (btnReturnToday) {
    btnReturnToday.addEventListener('click', () => {
      selectDay(null);
    });
  }

  // History Dropdown select
  const selectHistory = document.getElementById('select-history-day');
  if (selectHistory) {
    selectHistory.addEventListener('change', (e) => {
      const val = e.target.value;
      if (val === 'TODAY_LIVE') {
        selectDay(null);
      } else if (val) {
        selectDay(val);
      }
    });
  }

  // Toggle 29-Day Archive Table
  const btnToggleMatrix = document.getElementById('btn-toggle-history-table');
  const matrixSection = document.getElementById('history-matrix-section');
  const btnCloseMatrix = document.getElementById('btn-close-matrix');

  if (btnToggleMatrix && matrixSection) {
    btnToggleMatrix.addEventListener('click', () => {
      matrixSection.classList.toggle('hidden');
      if (!matrixSection.classList.contains('hidden')) {
        renderMatrixTable();
        matrixSection.scrollIntoView({ behavior: 'smooth' });
      }
    });
  }

  if (btnCloseMatrix && matrixSection) {
    btnCloseMatrix.addEventListener('click', () => {
      matrixSection.classList.add('hidden');
    });
  }

  // Diagnostics button and modal
  const btnTroubleshoot = document.getElementById('btn-troubleshoot');
  const btnOpenGuide = document.getElementById('btn-open-guide');
  const modal = document.getElementById('diagnostics-modal');
  const modalClose = document.getElementById('modal-close-btn');

  if (btnTroubleshoot) btnTroubleshoot.addEventListener('click', openDiagnosticsModal);
  if (btnOpenGuide) btnOpenGuide.addEventListener('click', (e) => {
    e.preventDefault();
    openDiagnosticsModal();
  });
  if (modalClose) modalClose.addEventListener('click', closeDiagnosticsModal);

  if (modal) {
    modal.addEventListener('click', (e) => {
      if (e.target === modal) closeDiagnosticsModal();
    });
  }

  // Chart mode selector segmented buttons
  document.querySelectorAll('.seg-btn').forEach(btn => {
    btn.addEventListener('click', (e) => {
      document.querySelectorAll('.seg-btn').forEach(b => b.classList.remove('active'));
      e.target.classList.add('active');
      currentMode = e.target.getAttribute('data-mode');
      renderChart();
    });
  });

  // Table sort order toggle
  const btnSort = document.getElementById('btn-sort-order');
  if (btnSort) {
    btnSort.addEventListener('click', () => {
      sortDesc = !sortDesc;
      document.getElementById('sort-order-label').textContent = sortDesc ? 'Newest First (Desc)' : 'Chronological (06:00 AM First)';
      renderTable();
    });
  }

  // Table search filter input
  const searchInput = document.getElementById('table-search');
  if (searchInput) {
    searchInput.addEventListener('input', (e) => {
      filterText = e.target.value.toLowerCase().trim();
      renderTable();
    });
  }
}

function openDiagnosticsModal() {
  const modal = document.getElementById('diagnostics-modal');
  if (modal) modal.classList.remove('hidden');
}

function closeDiagnosticsModal() {
  const modal = document.getElementById('diagnostics-modal');
  if (modal) modal.classList.add('hidden');
}

/* ==========================================================================
   3. DATA FETCHING & POLLING
   ========================================================================== */

function startPolling() {
  if (pollInterval) clearInterval(pollInterval);
  pollInterval = setInterval(fetchDeltaData, 1000); // 1-second live institutional refresh
}

async function fetchDeltaData() {
  try {
    const url = selectedDate ? `/api/delta?date=${encodeURIComponent(selectedDate)}` : '/api/delta';
    const res = await fetch(url, { headers: { 'ngrok-skip-browser-warning': 'true' } });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    masterData = data;
    
    resolveActiveDay();
    updateUI();
  } catch (err) {
    console.warn('[Public Activity Delta] Fetch notice:', err);
    updateBannerOffline("Server bridge disconnected. Ensure Python server is running.");
  }
}

function resolveActiveDay() {
  if (!masterData) return;
  
  const days = masterData.days || [];
  if (selectedDate && days.length > 0) {
    const found = days.find(d => d.date === selectedDate || d.date_bst === selectedDate);
    if (found) {
      activeDayData = found;
      return;
    }
  }
  
  // Default to Day 0 (Today)
  if (days.length > 0) {
    activeDayData = days[0];
  } else {
    activeDayData = {
      date: masterData.day_open_time ? masterData.day_open_time.split(' ')[0] : 'Today',
      day_name: 'Current Session',
      is_today: true,
      valid_bars: masterData.diagnostics?.valid_m20_bars_loaded || 0,
      total_bars: masterData.diagnostics?.expected_m20_bars_today || 72,
      summary: masterData.summary || {},
      intervals: masterData.intervals || []
    };
  }
}

function selectDay(dateStr) {
  selectedDate = dateStr;
  
  if (dateStr === null) {
    showToast("Live Gold Stream Active (Today)", "info");
  } else {
    showToast(`Viewing Historical Session: ${dateStr}`, "info");
  }

  resolveActiveDay();
  updateUI();
  fetchDeltaData();
}

async function triggerManualRefresh() {
  const btn = document.getElementById('btn-manual-refresh');
  const icon = btn.querySelector('.spin-icon');
  
  btn.disabled = true;
  if (icon) icon.classList.add('spinning');
  showToast("Scanning Gold market & activity delta buffers...", "info");

  try {
    const res = await fetch('/api/refresh', {
      method: 'POST',
      headers: { 'ngrok-skip-browser-warning': 'true' }
    });
    const result = await res.json();
    const payload = result.data ? result.data : result;
    masterData = payload;
    resolveActiveDay();
    updateUI();

    if (result.success !== false) {
      showToast("Activity Delta updated successfully!", "success");
    } else {
      showToast(result.message || "Refresh dispatched.", "warning");
    }
  } catch (err) {
    showToast("Error requesting refresh: " + err.message, "error");
  } finally {
    btn.disabled = false;
    if (icon) icon.classList.remove('spinning');
  }
}

/* ==========================================================================
   4. UI MASTER UPDATER
   ========================================================================== */

function updateUI() {
  if (!masterData || !activeDayData) return;

  const diag = masterData.diagnostics || {};
  const isOnline = masterData.mt5_online !== false;

  // 1. Update Live Gold Spot Ticker
  updateGoldSpotWidget(masterData.market);

  // 2. Update Status Header & Warning Bar
  updateStatusPill(masterData, diag, isOnline);

  // 3. Update Session Navigation & Chips
  updateSessionRibbon();

  // 4. Update 3 Hero Metric Cards
  updateHeroCards();

  // 5. Update Chart.js
  renderChart();

  // 6. Update Chronological Table
  renderTable();

  // 7. Update Modal
  updateDiagnosticsModal(masterData, diag, isOnline);
}

/* ==========================================================================
   5. LIVE GOLD SPOT TICKER LOGIC (FEATURED AT TOP)
   ========================================================================== */

function updateGoldSpotWidget(market) {
  if (!market) return;

  const elPrice = document.getElementById('gold-bid-display');
  const elChange = document.getElementById('gold-change-pill');
  const elSpread = document.getElementById('gold-spread-val');
  const elHigh = document.getElementById('gold-high-val');
  const elLow = document.getElementById('gold-low-val');

  const bid = market.bid || 0;
  const change = market.change || 0;
  const changePct = market.change_pct || 0;
  const spread = market.spread || 0;
  const high = market.day_high || bid;
  const low = market.day_low || bid;

  if (elPrice) {
    elPrice.textContent = formatCurrency(bid);

    // Tick flash animation
    if (previousBidPrice !== null && previousBidPrice !== bid) {
      elPrice.classList.remove('flash-up', 'flash-down');
      void elPrice.offsetWidth; // Trigger reflow
      elPrice.classList.add(bid > previousBidPrice ? 'flash-up' : 'flash-down');
    }
    previousBidPrice = bid;
  }

  if (elChange) {
    const isNeg = change < 0;
    const sign = change >= 0 ? '+' : '';
    elChange.textContent = `${sign}${change.toFixed(2)} (${sign}${changePct.toFixed(2)}%)`;
    elChange.className = `spot-change-pill mono ${isNeg ? 'val-neg' : 'val-pos'}`;
  }

  if (elSpread) elSpread.textContent = spread.toFixed(2);
  if (elHigh) elHigh.textContent = high.toLocaleString('en-US', { minimumFractionDigits: 2 });
  if (elLow) elLow.textContent = low.toLocaleString('en-US', { minimumFractionDigits: 2 });
}

/* ==========================================================================
   6. TERMINAL STATUS PILL & NOTIFICATIONS
   ========================================================================== */

function updateStatusPill(data, diag, isOnline) {
  const pill = document.getElementById('terminal-status-pill');
  const pillText = document.getElementById('terminal-status-text');
  const warningBar = document.getElementById('banner-warning-details');
  const warningText = document.getElementById('warning-text');

  if (!isOnline) {
    if (pill) {
      pill.className = 'terminal-status-pill offline';
      pillText.textContent = 'MT5 Offline';
    }
    if (warningBar && warningText) {
      warningBar.classList.remove('hidden');
      warningText.textContent = 'MetaTrader 5 connection lost. Running on cached session data.';
    }
    return;
  }

  if (!diag.dlls_allowed) {
    if (pill) {
      pill.className = 'terminal-status-pill offline';
      pillText.textContent = 'DLL Blocked';
    }
    if (warningBar && warningText) {
      warningBar.classList.remove('hidden');
      warningText.textContent = 'DLL imports are disabled in MT5 Options. Please check "Allow DLL imports".';
    }
    return;
  }

  // All Systems Operational
  if (pill) {
    pill.className = 'terminal-status-pill operational';
    pillText.textContent = 'MT5 Live (1s)';
  }
  if (warningBar) warningBar.classList.add('hidden');
}

function updateBannerOffline(msg) {
  const pill = document.getElementById('terminal-status-pill');
  const pillText = document.getElementById('terminal-status-text');
  const warningBar = document.getElementById('banner-warning-details');
  const warningText = document.getElementById('warning-text');

  if (pill) {
    pill.className = 'terminal-status-pill offline';
    pillText.textContent = 'Disconnected';
  }
  if (warningBar) warningBar.classList.remove('hidden');
  if (warningText) warningText.textContent = msg;
}

/* ==========================================================================
   7. SESSION SWITCHER & CHIPS
   ========================================================================== */

function updateSessionRibbon() {
  const chipsContainer = document.getElementById('session-pills-container');
  const selectDropdown = document.getElementById('select-history-day');
  const activeBadge = document.getElementById('active-session-indicator');
  const btnToday = document.getElementById('btn-today-quick');
  const noticeBar = document.getElementById('historical-view-notice');
  const noticeDate = document.getElementById('notice-date-text');
  const noticeBars = document.getElementById('notice-bars-text');

  const days = masterData.days || [];
  if (!days.length) return;

  const isViewingToday = (selectedDate === null || activeDayData.is_today);

  if (activeBadge) {
    activeBadge.textContent = isViewingToday 
      ? 'Today • Live Stream' 
      : `${activeDayData.day_name}, ${activeDayData.date} (Archive)`;
  }

  if (btnToday) {
    if (isViewingToday) btnToday.classList.add('active');
    else btnToday.classList.remove('active');
  }

  if (noticeBar) {
    if (isViewingToday) {
      noticeBar.classList.add('hidden');
    } else {
      noticeBar.classList.remove('hidden');
      if (noticeDate) noticeDate.textContent = `${activeDayData.day_name}, ${activeDayData.date}`;
      if (noticeBars) noticeBars.textContent = `${activeDayData.valid_bars}/${activeDayData.total_bars}`;
    }
  }

  // Populate Dropdown
  if (selectDropdown && (selectDropdown.options.length <= 1 || selectDropdown.options.length !== days.length + 1)) {
    selectDropdown.innerHTML = '<option value="" disabled>Browse 26+ Historical Days...</option>';
    
    const optToday = document.createElement('option');
    optToday.value = 'TODAY_LIVE';
    optToday.textContent = `🟢 Today (${days[0].date}) — Live Stream`;
    selectDropdown.appendChild(optToday);

    days.forEach((d, idx) => {
      if (idx === 0) return;
      const opt = document.createElement('option');
      opt.value = d.date;
      const inc = d.summary?.increase?.net_delta || 0;
      const dec = d.summary?.decrease?.net_delta || 0;
      opt.textContent = `${d.date} (${d.day_name}) • Inc: ${formatDelta(inc)} | Dec: ${formatDelta(dec)}`;
      selectDropdown.appendChild(opt);
    });
  }

  if (selectDropdown) {
    selectDropdown.value = isViewingToday ? 'TODAY_LIVE' : activeDayData.date;
  }

  // Render Horizontal Chips
  if (chipsContainer) {
    chipsContainer.innerHTML = '';
    const sliceDays = days;
    
    sliceDays.forEach(d => {
      const chip = document.createElement('div');
      const isThisActive = (isViewingToday && d.is_today) || (selectedDate === d.date);
      chip.className = `day-chip ${isThisActive ? 'active' : ''} ${d.is_today ? 'today' : ''}`;
      
      const incNet = d.summary?.increase?.net_delta || 0;
      const decNet = d.summary?.decrease?.net_delta || 0;
      
      const shortDate = d.date.substring(5);
      const dayLabel = d.is_today ? `🟢 Today` : `${d.day_name.slice(0,3)}, ${shortDate}`;

      chip.innerHTML = `
        <div class="chip-header-row">
          <span>${dayLabel}</span>
          <span class="chip-bars-badge">${d.valid_bars}b</span>
        </div>
        <div class="chip-deltas-row">
          <span class="chip-inc">${formatDelta(incNet)}</span>
          <span class="chip-dec">${formatDelta(decNet)}</span>
        </div>
      `;

      chip.addEventListener('click', () => {
        if (d.is_today) selectDay(null);
        else selectDay(d.date);
      });

      chipsContainer.appendChild(chip);
    });
  }
}

/* ==========================================================================
   8. 29-DAY PERFORMANCE ARCHIVE MATRIX TABLE
   ========================================================================== */

function renderMatrixTable() {
  const tbody = document.getElementById('matrix-table-body');
  if (!tbody || !masterData || !masterData.days) return;

  tbody.innerHTML = '';
  masterData.days.forEach(d => {
    const tr = document.createElement('tr');
    if (selectedDate === d.date || (selectedDate === null && d.is_today)) {
      tr.style.background = 'rgba(56, 189, 248, 0.08)';
    }

    const incNet = d.summary?.increase?.net_delta || 0;
    const decNet = d.summary?.decrease?.net_delta || 0;
    const bias = d.summary?.contrarian_bias || 'Neutral';

    let biasBadgeClass = 'badge-neutral';
    if (bias.toLowerCase().includes('bullish')) biasBadgeClass = 'badge-bullish';
    else if (bias.toLowerCase().includes('bearish')) biasBadgeClass = 'badge-bearish';

    tr.innerHTML = `
      <td class="mono font-semibold">${d.date}</td>
      <td>${d.day_name}</td>
      <td>
        <span class="${d.is_today ? 'badge-live' : 'badge-completed'}">
          ${d.is_today ? 'LIVE' : 'COMPLETED'}
        </span>
      </td>
      <td class="mono">${d.valid_bars} / ${d.total_bars}</td>
      <td class="mono ${getDeltaColorClass(incNet)} font-semibold">
        ${formatDelta(incNet)}
      </td>
      <td class="mono ${getDeltaColorClass(decNet)} font-semibold">
        ${formatDelta(decNet)}
      </td>
      <td>
        <span class="table-bias-badge ${biasBadgeClass}">
          ${bias}
        </span>
      </td>
      <td>
        <button class="btn-load-session" data-date="${d.date}">
          ${d.is_today ? 'View Live' : 'Load Session'}
        </button>
      </td>
    `;

    const btn = tr.querySelector('.btn-load-session');
    if (btn) {
      btn.addEventListener('click', () => {
        if (d.is_today) selectDay(null);
        else selectDay(d.date);
        document.getElementById('history-matrix-section').classList.add('hidden');
        window.scrollTo({ top: 280, behavior: 'smooth' });
      });
    }

    tbody.appendChild(tr);
  });
}

/* ==========================================================================
   9. HERO SUMMARY CARDS
   ========================================================================== */

function updateHeroCards() {
  const summary = activeDayData.summary || {};
  const inc = summary.increase || {};
  const dec = summary.decrease || {};

  const isToday = activeDayData.is_today;
  const labelInc = document.getElementById('label-inc-card');
  const labelDec = document.getElementById('label-dec-card');

  if (labelInc) labelInc.textContent = isToday ? 'Net Increase Delta (Today)' : `Net Increase Delta (${activeDayData.date})`;
  if (labelDec) labelDec.textContent = isToday ? 'Net Decrease Delta (Today)' : `Net Decrease Delta (${activeDayData.date})`;

  // 1. Increase Card
  const incNet = inc.net_delta || 0;
  const incPos = inc.sum_pos || 0;
  const incNeg = inc.sum_neg || 0;

  const elIncNet = document.getElementById('hero-inc-net');
  const elIncPos = document.getElementById('hero-inc-pos');
  const elIncNeg = document.getElementById('hero-inc-neg');
  const meterIncPos = document.getElementById('meter-inc-pos');
  const meterIncNeg = document.getElementById('meter-inc-neg');

  if (elIncNet) {
    elIncNet.textContent = formatDelta(incNet);
    elIncNet.className = 'metric-num mono ' + getDeltaColorClass(incNet);
  }
  if (elIncPos) elIncPos.textContent = `+${Math.abs(incPos).toFixed(2)}%`;
  if (elIncNeg) elIncNeg.textContent = `-${Math.abs(incNeg).toFixed(2)}%`;

  const incTotalAbs = Math.abs(incPos) + Math.abs(incNeg);
  if (meterIncPos && meterIncNeg && incTotalAbs > 0) {
    const posPct = (Math.abs(incPos) / incTotalAbs) * 100;
    meterIncPos.style.width = `${posPct}%`;
    meterIncNeg.style.width = `${100 - posPct}%`;
  }

  // 2. Decrease Card
  const decNet = dec.net_delta || 0;
  const decPos = dec.sum_pos || 0;
  const decNeg = dec.sum_neg || 0;

  const elDecNet = document.getElementById('hero-dec-net');
  const elDecPos = document.getElementById('hero-dec-pos');
  const elDecNeg = document.getElementById('hero-dec-neg');
  const meterDecPos = document.getElementById('meter-dec-pos');
  const meterDecNeg = document.getElementById('meter-dec-neg');

  if (elDecNet) {
    elDecNet.textContent = formatDelta(decNet);
    elDecNet.className = 'metric-num mono ' + getDeltaColorClass(decNet);
  }
  if (elDecPos) elDecPos.textContent = `+${Math.abs(decPos).toFixed(2)}%`;
  if (elDecNeg) elDecNeg.textContent = `-${Math.abs(decNeg).toFixed(2)}%`;

  const decTotalAbs = Math.abs(decPos) + Math.abs(decNeg);
  if (meterDecPos && meterDecNeg && decTotalAbs > 0) {
    const posPct = (Math.abs(decPos) / decTotalAbs) * 100;
    meterDecPos.style.width = `${posPct}%`;
    meterDecNeg.style.width = `${100 - posPct}%`;
  }

  // 3. Contrarian Signal Card
  const contrarianBias = summary.contrarian_bias || 'Neutral';
  const elBiasPill = document.getElementById('hero-bias-pill');
  const elBiasDesc = document.getElementById('hero-bias-desc');

  if (elBiasPill) {
    if (contrarianBias.toLowerCase().includes('bullish')) {
      elBiasPill.textContent = 'BULLISH BIAS (CROWD SHORTING)';
      elBiasPill.className = 'bias-pill bullish';
    } else if (contrarianBias.toLowerCase().includes('bearish')) {
      elBiasPill.textContent = 'BEARISH BIAS (CROWD BUYING)';
      elBiasPill.className = 'bias-pill bearish';
    } else {
      elBiasPill.textContent = 'NEUTRAL / BALANCED FLOW';
      elBiasPill.className = 'bias-pill neutral';
    }
  }

  if (elBiasDesc) {
    let narrative = '';
    if (incNet > 0.2) {
      narrative = `Retail crowd accumulated Gold LONGS (+${incNet.toFixed(2)}% opened). Contrarian bias indicates institutions look to fade public long orders.`;
    } else if (incNet < -0.2) {
      narrative = `Retail crowd accumulated Gold SHORTS (${incNet.toFixed(2)}% opened). Contrarian bias indicates institutional absorption against retail sellers.`;
    } else {
      narrative = `Buyer and seller volumes are near parity (${incNet.toFixed(2)}% net). Gold market flow is currently in structural equilibrium.`;
    }
    elBiasDesc.textContent = narrative;
  }

  // Timing strip
  const timingOpen = document.getElementById('timing-day-open');
  const timingBar = document.getElementById('timing-last-bar');
  const timingAgo = document.getElementById('timing-updated-ago');
  const bridgeTag = document.getElementById('footer-bridge-tag');

  if (timingOpen) timingOpen.textContent = '06:00 AM BST';

  if (timingBar && activeDayData.intervals && activeDayData.intervals.length > 0) {
    const lastInt = activeDayData.intervals[activeDayData.intervals.length - 1];
    timingBar.textContent = `${lastInt.time} BST`;
  }

  if (timingAgo) timingAgo.textContent = isToday ? '1s Live Sync' : 'Session Closed';
  if (bridgeTag) {
    bridgeTag.textContent = isToday ? 'Source: MT5 Live Gold Stream' : `Archive Snapshot: ${activeDayData.date}`;
  }
}

/* ==========================================================================
   10. CHART.JS RENDERING
   ========================================================================== */

function initChart() {
  const ctx = document.getElementById('deltaChart').getContext('2d');
  Chart.defaults.color = '#94a3b8';
  Chart.defaults.font.family = "'Inter', sans-serif";

  deltaChart = new Chart(ctx, {
    type: 'bar',
    data: {
      labels: [],
      datasets: []
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: {
        mode: 'index',
        intersect: false
      },
      plugins: {
        legend: { display: false },
        tooltip: {
          backgroundColor: 'rgba(15, 20, 32, 0.96)',
          titleColor: '#f8fafc',
          bodyColor: '#cbd5e1',
          borderColor: 'rgba(255, 255, 255, 0.12)',
          borderWidth: 1,
          padding: 12,
          titleFont: { size: 13, weight: '700', family: "'JetBrains Mono', monospace" },
          bodyFont: { size: 12 },
          callbacks: {
            title: (items) => {
              const idx = items[0].dataIndex;
              if (activeDayData && activeDayData.intervals && activeDayData.intervals[idx]) {
                const it = activeDayData.intervals[idx];
                return `⏰ ${it.time} BST (Broker: ${it.time_broker || '--:--'})`;
              }
              return `20-Min Bar: ${items[0].label}`;
            },
            afterBody: (items) => {
              const idx = items[0].dataIndex;
              if (activeDayData && activeDayData.intervals && activeDayData.intervals[idx]) {
                const interval = activeDayData.intervals[idx];
                return [
                  `---------------------------`,
                  `Crowd Flow: ${interval.behavior_tag || 'Neutral Flow'}`,
                  `Cumulative Increase: ${formatDelta(interval.inc_running_net || 0)}`,
                  `Cumulative Decrease: ${formatDelta(interval.dec_running_net || 0)}`
                ];
              }
              return [];
            }
          }
        }
      },
      scales: {
        x: {
          grid: {
            color: 'rgba(255, 255, 255, 0.04)',
            drawTicks: false
          },
          ticks: {
            font: { family: "'JetBrains Mono', monospace", size: 11 },
            maxRotation: 0,
            autoSkip: true,
            maxTicksLimit: 18
          }
        },
        y: {
          grid: {
            color: (context) => context.tick.value === 0 ? 'rgba(255, 255, 255, 0.3)' : 'rgba(255, 255, 255, 0.04)',
            lineWidth: (context) => context.tick.value === 0 ? 1.5 : 1
          },
          ticks: {
            font: { family: "'JetBrains Mono', monospace", size: 11 },
            callback: (val) => `${val >= 0 ? '+' : ''}${val.toFixed(2)}%`
          }
        }
      }
    }
  });
}

function renderChart() {
  if (!deltaChart || !activeDayData || !activeDayData.intervals) return;

  const intervals = activeDayData.intervals;
  const labels = intervals.map(item => item.time);

  const chartTitle = document.getElementById('chart-section-title');
  const chartSubtitle = document.getElementById('chart-section-subtitle');
  if (chartTitle) {
    chartTitle.textContent = activeDayData.is_today 
      ? "20-Minute Volume Delta & Running Cumulative Stream" 
      : `Archived Volume Stream: ${activeDayData.day_name}, ${activeDayData.date}`;
  }
  if (chartSubtitle) {
    chartSubtitle.textContent = `Individual 20m bar deltas plotted alongside 06:00 AM BST session trajectory`;
  }

  if (currentMode === 'increase') {
    const barValues = intervals.map(item => item.inc_20m);
    const lineValues = intervals.map(item => item.inc_running_net);
    const barColors = barValues.map(v => v >= 0 ? 'rgba(16, 185, 129, 0.85)' : 'rgba(244, 63, 94, 0.85)');

    deltaChart.data.labels = labels;
    deltaChart.data.datasets = [
      {
        type: 'bar',
        label: 'Increase 20m Delta',
        data: barValues,
        backgroundColor: barColors,
        borderRadius: 3,
        barPercentage: 0.75,
        order: 2
      },
      {
        type: 'line',
        label: 'Cumulative Increase',
        data: lineValues,
        borderColor: '#38bdf8',
        backgroundColor: 'rgba(56, 189, 248, 0.08)',
        borderWidth: 2.5,
        pointRadius: 0,
        pointHoverRadius: 5,
        pointHoverBackgroundColor: '#38bdf8',
        fill: true,
        tension: 0.25,
        order: 1
      }
    ];
  } else if (currentMode === 'decrease') {
    const barValues = intervals.map(item => item.dec_20m);
    const lineValues = intervals.map(item => item.dec_running_net);
    const barColors = barValues.map(v => v >= 0 ? 'rgba(16, 185, 129, 0.85)' : 'rgba(244, 63, 94, 0.85)');

    deltaChart.data.labels = labels;
    deltaChart.data.datasets = [
      {
        type: 'bar',
        label: 'Decrease 20m Delta',
        data: barValues,
        backgroundColor: barColors,
        borderRadius: 3,
        barPercentage: 0.75,
        order: 2
      },
      {
        type: 'line',
        label: 'Cumulative Decrease',
        data: lineValues,
        borderColor: '#f59e0b',
        backgroundColor: 'rgba(245, 158, 11, 0.08)',
        borderWidth: 2.5,
        pointRadius: 0,
        pointHoverRadius: 5,
        pointHoverBackgroundColor: '#f59e0b',
        fill: true,
        tension: 0.25,
        order: 1
      }
    ];
  } else if (currentMode === 'combined') {
    const incLine = intervals.map(item => item.inc_running_net);
    const decLine = intervals.map(item => item.dec_running_net);

    deltaChart.data.labels = labels;
    deltaChart.data.datasets = [
      {
        type: 'line',
        label: 'Cumulative Increase (Opened)',
        data: incLine,
        borderColor: '#38bdf8',
        backgroundColor: 'transparent',
        borderWidth: 2.5,
        pointRadius: 0,
        pointHoverRadius: 5,
        pointHoverBackgroundColor: '#38bdf8',
        tension: 0.25
      },
      {
        type: 'line',
        label: 'Cumulative Decrease (Closed)',
        data: decLine,
        borderColor: '#f59e0b',
        backgroundColor: 'transparent',
        borderWidth: 2.5,
        pointRadius: 0,
        pointHoverRadius: 5,
        pointHoverBackgroundColor: '#f59e0b',
        tension: 0.25
      }
    ];
  }

  deltaChart.update('none');
}

/* ==========================================================================
   11. CHRONOLOGICAL TABLE
   ========================================================================== */

function renderTable() {
  const tbody = document.getElementById('table-body');
  if (!tbody || !activeDayData || !activeDayData.intervals) return;

  const tableTitle = document.getElementById('table-section-title');
  if (tableTitle) {
    tableTitle.textContent = activeDayData.is_today 
      ? "Chronological 20-Minute Interval Stream (Today)"
      : `20-Minute Interval Stream: ${activeDayData.day_name}, ${activeDayData.date}`;
  }

  let items = [...activeDayData.intervals];

  if (filterText) {
    items = items.filter(it => 
      (it.time && it.time.toLowerCase().includes(filterText)) ||
      (it.time_broker && it.time_broker.toLowerCase().includes(filterText)) ||
      (it.behavior_tag && it.behavior_tag.toLowerCase().includes(filterText))
    );
  }

  if (sortDesc) {
    items.reverse();
  }

  if (items.length === 0) {
    tbody.innerHTML = `
      <tr>
        <td colspan="6" class="loading-state">
          No 20-minute delta intervals match the filter "${filterText}".
        </td>
      </tr>
    `;
    return;
  }

  tbody.innerHTML = items.map(it => {
    const inc20 = it.inc_20m || 0;
    const incCum = it.inc_running_net || 0;
    const dec20 = it.dec_20m || 0;
    const decCum = it.dec_running_net || 0;

    return `
      <tr>
        <td>
          <span class="mono time-primary">${it.time}</span>
          <span class="sub-time-broker">${it.time_broker ? `(Broker: ${it.time_broker})` : ''}</span>
        </td>
        <td>
          <span class="delta-pill ${getDeltaColorClass(inc20)}">
            ${formatDelta(inc20)}
          </span>
        </td>
        <td class="mono font-semibold ${getDeltaColorClass(incCum)}">
          ${formatDelta(incCum)}
        </td>
        <td>
          <span class="delta-pill ${getDeltaColorClass(dec20)}">
            ${formatDelta(dec20)}
          </span>
        </td>
        <td class="mono font-semibold ${getDeltaColorClass(decCum)}">
          ${formatDelta(decCum)}
        </td>
        <td>
          <span class="behavior-badge ${getBehaviorBadgeClass(it.behavior_tag)}">
            ${it.behavior_tag || 'Balanced Flow'}
          </span>
        </td>
      </tr>
    `;
  }).join('');

  // Table Foot Summaries
  const footInc = document.getElementById('foot-inc-summary');
  const footIncNet = document.getElementById('foot-inc-net-summary');
  const footDec = document.getElementById('foot-dec-summary');
  const footDecNet = document.getElementById('foot-dec-net-summary');
  const footBias = document.getElementById('foot-bias-summary');

  const sum = activeDayData.summary || {};
  if (footInc) footInc.textContent = `Gross: +${sum.increase?.sum_pos?.toFixed(2) || '0.00'}% / ${sum.increase?.sum_neg?.toFixed(2) || '0.00'}%`;
  if (footIncNet) footIncNet.textContent = `Net: ${formatDelta(sum.increase?.net_delta || 0)}`;
  if (footDec) footDec.textContent = `Gross: +${sum.decrease?.sum_pos?.toFixed(2) || '0.00'}% / ${sum.decrease?.sum_neg?.toFixed(2) || '0.00'}%`;
  if (footDecNet) footDecNet.textContent = `Net: ${formatDelta(sum.decrease?.net_delta || 0)}`;
  if (footBias) footBias.textContent = `Bias: ${sum.contrarian_bias || 'Neutral'}`;
}

/* ==========================================================================
   12. DIAGNOSTICS & TOAST
   ========================================================================== */

function updateDiagnosticsModal(data, diag, isOnline) {
  const elConn = document.getElementById('diag-terminal-conn');
  const elDll = document.getElementById('diag-dll-allowed');
  const elInd = document.getElementById('diag-indicator-found');
  const elBars = document.getElementById('diag-bars-loaded');

  if (elConn) {
    elConn.textContent = isOnline ? 'CONNECTED (1s Heartbeat Active)' : 'DISCONNECTED (Offline)';
    elConn.className = 'd-val ' + (isOnline ? 'val-pos' : 'val-neg');
  }

  if (elDll) {
    elDll.textContent = diag.dlls_allowed ? 'ALLOWED (DLL Calls Enabled)' : 'BLOCKED (Enable in MT5 Options)';
    elDll.className = 'd-val ' + (diag.dlls_allowed ? 'val-pos' : 'val-neg');
  }

  if (elInd) {
    elInd.textContent = diag.indicator_found ? 'BOUND (Active on Gold Chart)' : 'MISSING';
    elInd.className = 'd-val ' + (diag.indicator_found ? 'val-pos' : 'val-neg');
  }

  if (elBars) {
    elBars.textContent = `${data.total_history_days || 26} Historical Days (${diag.valid_m20_bars_loaded || 0} bars today)`;
    elBars.className = 'd-val val-pos';
  }
}

function getBehaviorBadgeClass(tag) {
  if (!tag) return '';
  const l = tag.toLowerCase();
  if (l.includes('aggressive') && l.includes('buying')) return 'tag-buying-agg';
  if (l.includes('aggressive') && l.includes('selling')) return 'tag-selling-agg';
  if (l.includes('buying')) return 'tag-buying';
  if (l.includes('selling')) return 'tag-selling';
  if (l.includes('profit') || l.includes('squeeze')) return 'tag-squeeze';
  return 'tag-neutral';
}

function showToast(message, type = 'info') {
  const container = document.getElementById('toast-container');
  if (!container) return;

  const toast = document.createElement('div');
  toast.className = `toast-item ${type}`;
  toast.innerHTML = `<span>${message}</span>`;

  container.appendChild(toast);
  setTimeout(() => {
    toast.style.opacity = '0';
    toast.style.transform = 'translateY(10px)';
    toast.style.transition = 'all 0.3s ease';
    setTimeout(() => toast.remove(), 300);
  }, 3500);
}
