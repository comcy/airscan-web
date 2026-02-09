<script>
    console.log('🚀 Scanner App gestartet');
    
    // PWA Install Prompt
    let deferredPrompt;
    const installBanner = document.getElementById('installBanner');
    const installBtn = document.getElementById('installBtn');
    const dismissBtn = document.getElementById('dismissBtn');
    
    window.addEventListener('beforeinstallprompt', (e) => {
        console.log('📱 beforeinstallprompt Event gefeuert');
        e.preventDefault();
        deferredPrompt = e;
        
        if (!localStorage.getItem('installDismissed')) {
            installBanner.classList.add('show');
        }
    });
    
    installBtn.addEventListener('click', async () => {
        if (deferredPrompt) {
            deferredPrompt.prompt();
            const { outcome } = await deferredPrompt.userChoice;
            console.log('PWA Install outcome:', outcome);
            deferredPrompt = null;
            installBanner.classList.remove('show');
        }
    });
    
    dismissBtn.addEventListener('click', () => {
        installBanner.classList.remove('show');
        localStorage.setItem('installDismissed', 'true');
    });
    
    window.addEventListener('appinstalled', () => {
        console.log('✅ PWA installiert');
        installBanner.classList.remove('show');
    });
    
    // Service Worker Registration
    if ('serviceWorker' in navigator) {
        navigator.serviceWorker.register('/service-worker.js')
            .then((registration) => {
                console.log('✅ Service Worker registriert:', registration.scope);
                
                registration.addEventListener('updatefound', () => {
                    const newWorker = registration.installing;
                    newWorker.addEventListener('statechange', () => {
                        if (newWorker.state === 'installed' && navigator.serviceWorker.controller) {
                            document.getElementById('updateToast').classList.add('show');
                        }
                    });
                });
            })
            .catch((error) => {
                console.error('❌ Service Worker Fehler:', error);
            });
    }
    
    function updateApp() {
        if ('serviceWorker' in navigator) {
            navigator.serviceWorker.getRegistration().then((registration) => {
                if (registration && registration.waiting) {
                    registration.waiting.postMessage({ type: 'SKIP_WAITING' });
                }
            });
            window.location.reload();
        }
    }
    
    // Online/Offline Status
    const statusDot = document.getElementById('statusDot');
    const statusText = document.getElementById('statusText');
    
    function updateOnlineStatus() {
        if (navigator.onLine) {
            statusDot.classList.remove('offline');
            statusText.textContent = 'Online';
            console.log('🌐 Online');
        } else {
            statusDot.classList.add('offline');
            statusText.textContent = 'Offline';
            console.log('📡 Offline');
        }
    }
    
    window.addEventListener('online', updateOnlineStatus);
    window.addEventListener('offline', updateOnlineStatus);
    updateOnlineStatus();
    
    // Option cards toggle
    document.querySelectorAll('.option-card').forEach(card => {
        card.addEventListener('click', (e) => {
            if (e.target.tagName !== 'INPUT') {
                const checkbox = card.querySelector('input[type="checkbox"]');
                checkbox.checked = !checkbox.checked;
            }
            card.classList.toggle('active', card.querySelector('input').checked);
        });
    });
    
    const form = document.getElementById('scanForm');
    const output = document.getElementById('output');
    const scanBtn = document.getElementById('scanBtn');
    const scansList = document.getElementById('scansList');
    
    // Initial load
    console.log('📋 Lade initiale Scan-Liste...');
    loadScans();
    
    // Pull to refresh
    let startY = 0;
    let pullDistance = 0;
    
    document.addEventListener('touchstart', (e) => {
        if (window.scrollY === 0) {
            startY = e.touches[0].pageY;
        }
    });
    
    document.addEventListener('touchmove', (e) => {
        if (startY > 0) {
            pullDistance = e.touches[0].pageY - startY;
            if (pullDistance > 80) {
                console.log('🔄 Pull-to-refresh ausgelöst');
                loadScans();
                startY = 0;
            }
        }
    });
    
    form.addEventListener('submit', async (e) => {
        e.preventDefault();
        console.log('📤 Scan-Formular abgeschickt');
        
        const formData = {
            name: document.getElementById('name').value || 'scan',
            resolution: parseInt(document.getElementById('resolution').value),
            mode: document.getElementById('mode').value,
            source: document.getElementById('source').value,
            compress: document.getElementById('compress').checked,
            ocr: document.getElementById('ocr').checked
        };
        
        console.log('📋 Scan-Parameter:', formData);
        
        scanBtn.disabled = true;
        scanBtn.innerHTML = '<span class="spinner"></span> Scanne...';
        output.classList.remove('show');
        
        try {
            const response = await fetch('/api/scan', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(formData)
            });
            
            const result = await response.json();
            console.log('📥 Scan-Ergebnis:', result);
            
            output.classList.add('show');
            
            if (result.success) {
                output.className = 'output show success';
                output.textContent = result.output + '\n\n✅ PDF: ' + result.filename;
                loadScans();
                
                if (navigator.vibrate) {
                    navigator.vibrate(200);
                }
                
                setTimeout(() => {
                    if (confirm('Jetzt herunterladen?')) {
                        window.location.href = result.downloadUrl;
                    }
                }, 500);
            } else {
                output.className = 'output show error';
                output.textContent = '❌ ' + (result.error || result.output);
                if (navigator.vibrate) {
                    navigator.vibrate([100, 50, 100]);
                }
            }
        } catch (error) {
            console.error('❌ Scan-Fehler:', error);
            output.classList.add('show');
            output.className = 'output show error';
            output.textContent = '❌ ' + error.message;
        } finally {
            scanBtn.disabled = false;
            scanBtn.innerHTML = '🚀 Scan starten';
        }
    });
    
    async function loadScans() {
        console.log('🔄 loadScans() gestartet');
        
        try {
            console.log('📡 Fetching /api/scans...');
            const response = await fetch('/api/scans');
            console.log('📡 Response Status:', response.status, response.statusText);
            
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }
            
            const scans = await response.json();
            console.log('📄 Scans geladen:', scans.length, 'Dateien');
            console.log('📄 Daten:', scans);
            
            if (scans.length === 0) {
                console.log('📭 Keine Scans vorhanden');
                scansList.innerHTML = `
                    <div class="empty-state">
                        <div class="empty-state-icon">📭</div>
                        <div>Keine Scans vorhanden</div>
                    </div>
                `;
                return;
            }
            
            console.log('🎨 Rendere Scan-Liste...');
            scansList.innerHTML = scans.map(scan => {
                return `
                    <div class="scan-item">
                        <div class="scan-info">
                            <div class="scan-name">${escapeHtml(scan.filename)}</div>
                            <div class="scan-meta">${formatBytes(scan.size)} • ${escapeHtml(scan.created)}</div>
                        </div>
                        <div class="scan-actions">
                            <button class="btn-icon download" onclick="downloadFile('${escapeHtml(scan.filename)}')">
                                ⬇️
                            </button>
                            <button class="btn-icon delete" onclick="deleteScan('${escapeHtml(scan.filename)}')">
                                🗑️
                            </button>
                        </div>
                    </div>
                `;
            }).join('');
            
            console.log('✅ Scan-Liste gerendert');
            
        } catch (error) {
            console.error('❌ Fehler beim Laden der Scans:', error);
            scansList.innerHTML = `
                <div class="empty-state">
                    <div class="empty-state-icon">❌</div>
                    <div>Fehler beim Laden</div>
                    <div style="font-size: 12px; margin-top: 8px; color: var(--error);">${error.message}</div>
                </div>
            `;
        }
    }
    
    function downloadFile(filename) {
        console.log('📥 Download:', filename);
        window.location.href = `/api/download/${encodeURIComponent(filename)}`;
    }
    
    async function deleteScan(filename) {
        if (!confirm(`"${filename}" löschen?`)) return;
        
        console.log('🗑️ Lösche:', filename);
        
        try {
            const response = await fetch(`/api/delete/${encodeURIComponent(filename)}`, {
                method: 'DELETE'
            });
            
            if (response.ok) {
                console.log('✅ Gelöscht:', filename);
                loadScans();
                if (navigator.vibrate) navigator.vibrate(100);
            } else {
                console.error('❌ Löschen fehlgeschlagen');
                alert('Fehler beim Löschen');
            }
        } catch (error) {
            console.error('❌ Fehler beim Löschen:', error);
            alert('Fehler: ' + error.message);
        }
    }
    
    function escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }
    
    function formatBytes(bytes) {
        if (bytes === 0) return '0 B';
        const k = 1024;
        const sizes = ['B', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i];
    }
    
    console.log('✅ Scanner App initialisiert');
</script>