/* ─────────────────────────────────────────────────────────────
   sec — Interactive Client Script
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

    // 1. Terminal Tab Switching
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

    // 2. Interactive Cheatsheet Switcher
    const cheatBtns = document.querySelectorAll('.cheat-btn');
    const cheatPanels = document.querySelectorAll('.cheat-panel');

    cheatBtns.forEach(btn => {
        btn.addEventListener('click', () => {
            const targetId = btn.getAttribute('data-target');

            cheatBtns.forEach(b => b.classList.remove('active'));
            cheatPanels.forEach(p => p.classList.remove('active'));

            btn.classList.add('active');
            const targetPanel = document.getElementById(targetId);
            if (targetPanel) {
                targetPanel.classList.add('active');
            }
        });
    });

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
            
            if (icon && title) {
                icon.style.background = 'rgba(16, 185, 129, 0.2)';
                icon.style.borderColor = '#10b981';
                icon.style.color = '#10b981';
                title.textContent = 'Authenticated via Touch ID ✓';
                desc.textContent = 'Secrets loaded into RAM (0.003s)';

                setTimeout(() => {
                    icon.style.background = '';
                    icon.style.borderColor = '';
                    icon.style.color = '';
                    title.textContent = 'Touch ID or Apple Watch';
                    desc.textContent = 'Tap sensor to inject secrets into RAM';
                }, 3000);
            }
        });
    }

    // 5. Scroll-Reveal Animation
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
});
