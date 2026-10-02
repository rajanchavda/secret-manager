/* ─────────────────────────────────────────────────────────────
   Secret Manager — Interactive Client Script
   ───────────────────────────────────────────────────────────── */

document.addEventListener('DOMContentLoaded', () => {
    // 0. Theme Toggle (Default: Light Mode, switchable to Dark)
    const themeToggleBtn = document.getElementById('themeToggle');
    const updateThemeAria = (theme) => {
        if (themeToggleBtn) {
            themeToggleBtn.setAttribute('aria-label', theme === 'dark' ? 'Switch to light mode' : 'Switch to dark mode');
            themeToggleBtn.setAttribute('title', theme === 'dark' ? 'Switch to light mode' : 'Switch to dark mode');
        }
    };

    const initialTheme = document.documentElement.getAttribute('data-theme') || 'light';
    updateThemeAria(initialTheme);

    if (themeToggleBtn) {
        themeToggleBtn.addEventListener('click', () => {
            const current = document.documentElement.getAttribute('data-theme') || 'light';
            const nextTheme = current === 'dark' ? 'light' : 'dark';
            document.documentElement.setAttribute('data-theme', nextTheme);
            localStorage.setItem('sec-theme', nextTheme);
            updateThemeAria(nextTheme);
        });
    }

    // 1. Terminal / Showcase Tab Switching
    const termTabs = document.querySelectorAll('.term-tab');
    const termPanes = document.querySelectorAll('.term-pane');

    termTabs.forEach(tab => {
        tab.addEventListener('click', () => {
            const targetId = tab.getAttribute('data-target');
            
            termTabs.forEach(t => t.classList.remove('active'));
            termPanes.forEach(p => p.classList.remove('active'));

            tab.classList.add('active');
            const targetPane = document.getElementById(targetId);
            if (targetPane) {
                targetPane.classList.add('active');
            }
        });
    });

    // 2. Interactive CLI Command Explorer (Category Filter & Real-Time Search)
    const cliTabs = document.querySelectorAll('.cli-tab-btn');
    const cliCards = document.querySelectorAll('.cli-cmd-card');
    const cliSearchInput = document.getElementById('cliSearchInput');
    const cliVisibleCount = document.getElementById('cliVisibleCount');
    const cliEmptyState = document.getElementById('cliEmptyState');
    const cliResetBtn = document.getElementById('cliResetBtn');

    let currentCategory = 'all';

    function filterCommands() {
        const query = (cliSearchInput ? cliSearchInput.value : '').toLowerCase().trim();
        let visibleCount = 0;

        cliCards.forEach(card => {
            const category = card.getAttribute('data-category');
            const searchContent = (card.getAttribute('data-search') || card.textContent).toLowerCase();

            const matchesCategory = currentCategory === 'all' || category === currentCategory;
            const matchesSearch = !query || searchContent.includes(query);

            if (matchesCategory && matchesSearch) {
                card.style.display = '';
                visibleCount++;
            } else {
                card.style.display = 'none';
            }
        });

        if (cliVisibleCount) {
            cliVisibleCount.textContent = `Showing ${visibleCount} of ${cliCards.length} commands`;
        }

        if (cliEmptyState) {
            cliEmptyState.style.display = visibleCount === 0 ? 'block' : 'none';
        }
    }

    if (cliTabs.length > 0) {
        cliTabs.forEach(tab => {
            tab.addEventListener('click', () => {
                cliTabs.forEach(t => t.classList.remove('active'));
                tab.classList.add('active');
                currentCategory = tab.getAttribute('data-category') || 'all';
                filterCommands();
            });
        });
    }

    if (cliSearchInput) {
        cliSearchInput.addEventListener('input', () => {
            filterCommands();
        });
    }

    if (cliResetBtn) {
        cliResetBtn.addEventListener('click', () => {
            if (cliSearchInput) cliSearchInput.value = '';
            currentCategory = 'all';
            cliTabs.forEach(t => {
                if (t.getAttribute('data-category') === 'all') {
                    t.classList.add('active');
                } else {
                    t.classList.remove('active');
                }
            });
            filterCommands();
        });
    }


    // 3. One-Click Copy Buttons (Install pills and code snippets)
    const copyTriggers = document.querySelectorAll('[data-copy]');

    copyTriggers.forEach(trigger => {
        trigger.addEventListener('click', async (e) => {
            e.preventDefault();
            const textToCopy = trigger.getAttribute('data-copy');
            if (!textToCopy) return;

            try {
                await navigator.clipboard.writeText(textToCopy);
                
                // Visual feedback
                const btn = trigger.classList.contains('copy-btn') ? trigger : trigger.querySelector('.copy-btn');
                if (btn) {
                    const originalText = btn.innerHTML;
                    btn.classList.add('copied');
                    btn.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg> Copied!`;

                    setTimeout(() => {
                        btn.classList.remove('copied');
                        btn.innerHTML = originalText;
                    }, 2000);
                }
            } catch (err) {
                console.error('Clipboard copy failed:', err);
            }
        });
    });

    // 4. Interactive Touch ID Biometric Tap Simulation in Hero
    const touchModal = document.getElementById('touchModal');
    if (touchModal) {
        touchModal.addEventListener('click', () => {
            const icon = touchModal.querySelector('.touchid-icon-pulse');
            const title = touchModal.querySelector('.touchid-text h4');
            const desc = touchModal.querySelector('.touchid-text p');
            const pill = touchModal.querySelector('.touchid-tap-pill');
            
            if (icon && title) {
                icon.style.background = 'rgba(16, 185, 129, 0.2)';
                icon.style.borderColor = '#10b981';
                icon.style.color = '#10b981';
                title.textContent = 'Authenticated via Touch ID ✓';
                desc.textContent = 'Secrets loaded into RAM (0.003s)';
                if (pill) {
                    pill.textContent = 'Verified ✓';
                    pill.style.background = 'rgba(16, 185, 129, 0.2)';
                    pill.style.borderColor = '#10b981';
                    pill.style.color = '#34d399';
                }

                setTimeout(() => {
                    icon.style.background = '';
                    icon.style.borderColor = '';
                    icon.style.color = '';
                    title.textContent = 'Touch ID or Apple Watch';
                    desc.textContent = 'Tap sensor to inject secrets into RAM';
                    if (pill) {
                        pill.textContent = 'Tap Sensor';
                        pill.style.background = '';
                        pill.style.borderColor = '';
                        pill.style.color = '';
                    }
                }, 3000);
            }
        });
    }

    // 5. Interactive AI Agent Radar Simulator
    const btnSimulateRadar = document.getElementById('btnSimulateRadar');
    const radarFeed = document.getElementById('radarFeed');
    let simulatedAttempts = 14;

    const simulatedEvents = [
        {
            agent: 'Antigravity Agent',
            badgeClass: 'badge-cursor',
            icon: '<path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z"/>',
            action: 'Attempted tool call: <code>view_file(.env)</code>',
            shield: '✔ Served Decoy'
        },
        {
            agent: 'Claude 3.7 Sonnet',
            badgeClass: 'badge-claude',
            icon: '<circle cx="12" cy="12" r="10"/><path d="M8 14s1.5 2 4 2 4-2 4-2"/><line x1="9" y1="9" x2="9.01" y2="9"/><line x1="15" y1="9" x2="15.01" y2="9"/>',
            action: 'Invoked bash command <code>cat .env | grep STRIPE</code>',
            shield: '✔ Masked Decoy'
        },
        {
            agent: 'Cursor Composer',
            badgeClass: 'badge-cursor',
            icon: '<path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z"/>',
            action: 'Background indexer crawled workspace configuration',
            shield: '✔ 0 Secrets Read'
        },
        {
            agent: 'Local LLM (Ollama)',
            badgeClass: 'badge-copilot',
            icon: '<polyline points="16 18 22 12 16 6"/><polyline points="8 6 2 12 8 18"/>',
            action: 'Searched directory tree for <code>OPENAI_API_KEY</code>',
            shield: '✔ Blocked (Decoy)'
        }
    ];

    let eventIdx = 0;
    if (btnSimulateRadar && radarFeed) {
        btnSimulateRadar.addEventListener('click', () => {
            const ev = simulatedEvents[eventIdx % simulatedEvents.length];
            eventIdx++;
            simulatedAttempts++;

            const item = document.createElement('div');
            item.className = 'radar-feed-item';
            item.style.animation = 'termFade 0.3s ease';
            item.innerHTML = `
                <div class="radar-feed-left">
                    <span class="radar-agent-badge ${ev.badgeClass}">
                        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">${ev.icon}</svg>
                        ${ev.agent}
                    </span>
                    <span class="radar-action-text">${ev.action}</span>
                </div>
                <div class="radar-feed-right">
                    <span class="radar-shield-tag">${ev.shield}</span>
                    <span class="radar-time">just now</span>
                </div>
            `;

            radarFeed.insertBefore(item, radarFeed.firstChild);

            // Update stats summary in header
            const statsStrong = document.querySelector('.radar-stats-summary strong');
            if (statsStrong) {
                statsStrong.textContent = `${simulatedAttempts} attempts`;
            }

            // Keep max 5 items in demo
            while (radarFeed.children.length > 5) {
                radarFeed.removeChild(radarFeed.lastChild);
            }
        });
    }

    // 6. Interactive Runner Studio Simulator
    const runnerToggleBtn = document.getElementById('runnerToggleBtn');
    const runnerConsole = document.getElementById('runnerConsole');
    const runnerStatusBadge = document.getElementById('runnerStatusBadge');
    const runnerStatusText = document.getElementById('runnerStatusText');
    const runnerTelemetryDetails = document.getElementById('runnerTelemetryDetails');
    const runnerCmdInput = document.getElementById('runnerCmdInput');

    let isStudioRunning = false;
    let studioTimer = null;

    if (runnerToggleBtn && runnerConsole) {
        runnerToggleBtn.addEventListener('click', () => {
            if (!isStudioRunning) {
                // Start Server
                isStudioRunning = true;
                runnerToggleBtn.className = 'runner-btn-action stop';
                runnerToggleBtn.innerHTML = `
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><rect x="4" y="4" width="16" height="16" rx="2"/></svg>
                    <span>Stop Server</span>
                `;

                if (runnerStatusBadge && runnerStatusText) {
                    runnerStatusBadge.className = 'runner-telemetry-badge';
                    runnerStatusBadge.querySelector('.status-live-dot').style.background = '#10b981';
                    runnerStatusText.textContent = 'Running · Secrets Injected into RAM';
                }

                if (runnerTelemetryDetails) {
                    runnerTelemetryDetails.innerHTML = 'PID: <strong>51820</strong> &nbsp;|&nbsp; Memory: <strong>42.4 MB</strong> &nbsp;|&nbsp; Disk Plaintext: <strong>0 bytes</strong>';
                }

                const cmd = runnerCmdInput ? runnerCmdInput.value : 'npm run dev';
                runnerConsole.innerHTML = `
                    <div class="console-line-sec">[Secret Manager] Unlocked via Apple Secure Enclave in 0.003s</div>
                    <div class="console-line-sec">[Secret Manager] Injected 4 credentials directly into child process RAM</div>
                    <div class="console-line-sec">[Secret Manager] Stealth preload hooks active: ps -E inspection disabled</div>
                    <div class="console-line-app">> ${cmd}</div>
                    <div class="console-line-dim">[next] compiling client and server packages...</div>
                    <div class="console-line-success">✔ Ready on http://localhost:3000 (connected with RAM credentials)</div>
                `;

                studioTimer = setInterval(() => {
                    if (!isStudioRunning) return;
                    const log = document.createElement('div');
                    log.className = 'console-line-dim';
                    const now = new Date().toLocaleTimeString();
                    log.textContent = `[${now}] GET /api/v1/health 200 OK (${Math.floor(Math.random() * 15 + 8)}ms)`;
                    runnerConsole.appendChild(log);
                    runnerConsole.scrollTop = runnerConsole.scrollHeight;
                }, 4000);

            } else {
                // Stop Server
                isStudioRunning = false;
                if (studioTimer) clearInterval(studioTimer);

                runnerToggleBtn.className = 'runner-btn-action run';
                runnerToggleBtn.innerHTML = `
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21 5 3"/></svg>
                    <span>Run Server</span>
                `;

                if (runnerStatusBadge && runnerStatusText) {
                    runnerStatusBadge.className = 'runner-telemetry-badge stopped';
                    runnerStatusBadge.querySelector('.status-live-dot').style.background = '#9ca3af';
                    runnerStatusText.textContent = 'Stopped · Secrets Safely Wiped from RAM';
                }

                if (runnerTelemetryDetails) {
                    runnerTelemetryDetails.innerHTML = 'PID: — &nbsp;|&nbsp; Memory: 0.0 MB &nbsp;|&nbsp; Disk Plaintext: 0 bytes';
                }

                const logExit = document.createElement('div');
                logExit.className = 'console-line-dim';
                logExit.textContent = '[Secret Manager] Child process 51820 terminated gracefully. RAM secrets purged.';
                runnerConsole.appendChild(logExit);
                runnerConsole.scrollTop = runnerConsole.scrollHeight;
            }
        });
    }

    // 7. Interactive Deep Scanner Simulator
    const btnScanDeveloper = document.getElementById('btnScanDeveloper');
    if (btnScanDeveloper) {
        btnScanDeveloper.addEventListener('click', () => {
            const originalHTML = btnScanDeveloper.innerHTML;
            btnScanDeveloper.innerHTML = `
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="spin"><path d="M21 12a9 9 0 1 1-6.219-8.56"/></svg>
                <span>Scanning ~/Developer...</span>
            `;

            setTimeout(() => {
                btnScanDeveloper.innerHTML = originalHTML;
                alert('Scan Complete! Discovered 3 projects in ~/Developer. 2 unshielded .env files found. Click "Shield with Touch ID" to encrypt them.');
            }, 650);
        });
    }

    // 8. Scroll-Reveal Animation
    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.classList.add('in');
                observer.unobserve(entry.target);
            }
        });
    }, {
        threshold: 0.12,
        rootMargin: '0px 0px -40px 0px'
    });

    document.querySelectorAll('.reveal').forEach(el => observer.observe(el));

    // 9. Mobile Drawer Navigation Toggle
    const mobileMenuBtn = document.getElementById('mobileMenuBtn');
    const mobileDrawer = document.getElementById('mobileDrawer');

    if (mobileMenuBtn && mobileDrawer) {
        const toggleDrawer = () => {
            const isOpen = mobileDrawer.classList.contains('open');
            if (isOpen) {
                mobileDrawer.classList.remove('open');
                mobileMenuBtn.classList.remove('active');
                mobileMenuBtn.setAttribute('aria-expanded', 'false');
                mobileMenuBtn.setAttribute('aria-label', 'Open navigation menu');
            } else {
                mobileDrawer.classList.add('open');
                mobileMenuBtn.classList.add('active');
                mobileMenuBtn.setAttribute('aria-expanded', 'true');
                mobileMenuBtn.setAttribute('aria-label', 'Close navigation menu');
            }
        };

        mobileMenuBtn.addEventListener('click', toggleDrawer);

        // Close when any link inside drawer is clicked
        const drawerLinks = mobileDrawer.querySelectorAll('a');
        drawerLinks.forEach(link => {
            link.addEventListener('click', () => {
                mobileDrawer.classList.remove('open');
                mobileMenuBtn.classList.remove('active');
                mobileMenuBtn.setAttribute('aria-expanded', 'false');
                mobileMenuBtn.setAttribute('aria-label', 'Open navigation menu');
            });
        });
    }
});
