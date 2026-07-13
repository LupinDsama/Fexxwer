document.addEventListener("DOMContentLoaded", () => {

    /* =========================================
       1. SPA NAVIGATION
    ========================================= */
    const sidebarLinks = document.querySelectorAll(".sidebar a");
    const sections = document.querySelectorAll(".tab-content");

    function showSection(targetId){
        sections.forEach((section) => section.classList.remove("active-section"));
        const targetSection = document.getElementById(targetId);
        if (targetSection) {
            targetSection.classList.add("active-section");
        }

        // lazy-init charts the first time their section is shown
        if (targetId === "status") initStatusCharts();
        if (targetId === "trading") initTradingCharts();
    }

    function setActiveLink(link){
        sidebarLinks.forEach((btn) => btn.classList.remove("active"));
        link.classList.add("active");
    }

    sidebarLinks.forEach((link) => {
        link.addEventListener("click", (e) => {
            e.preventDefault();
            const href = link.getAttribute("href");
            const targetId = href.substring(1);

            setActiveLink(link);
            localStorage.setItem("activePage", href);
            showSection(targetId);
        });
    });

    // restore last visited page (falls back to whatever is marked active in the HTML)
    const activePage = localStorage.getItem("activePage");
    if (activePage) {
        const restoredLink = document.querySelector(`.sidebar a[href="${activePage}"]`);
        if (restoredLink) {
            setActiveLink(restoredLink);
            showSection(activePage.substring(1));
        }
    } else {
        const currentActive = document.querySelector(".sidebar a.active");
        if (currentActive) showSection(currentActive.getAttribute("href").substring(1));
    }

    /* =========================================
       2. HOME — typing effect for role text
    ========================================= */
    const typedEl = document.getElementById("typedRole");
    if (typedEl) {
        const roles = ["Roblox Scripter 🎮", "Full-end Dev 💻", "Fexxwer TheDev ✨"];
        let roleIndex = 0, charIndex = 0, deleting = false;

        function typeLoop(){
            const current = roles[roleIndex];
            if (!deleting) {
                charIndex++;
                typedEl.textContent = current.slice(0, charIndex);
                if (charIndex === current.length) {
                    deleting = true;
                    setTimeout(typeLoop, 1400);
                    return;
                }
            } else {
                charIndex--;
                typedEl.textContent = current.slice(0, charIndex);
                if (charIndex === 0) {
                    deleting = false;
                    roleIndex = (roleIndex + 1) % roles.length;
                }
            }
            setTimeout(typeLoop, deleting ? 45 : 90);
        }
        typeLoop();
    }

    /* =========================================
       3. SHOP — buy buttons
    ========================================= */
    document.querySelectorAll(".buy-btn").forEach((btn) => {
        btn.addEventListener("click", () => {
            const card = btn.closest(".product-card");
            const name = card?.querySelector("h3")?.textContent ?? "sản phẩm";
            btn.textContent = "Đã thêm ✓";
            btn.disabled = true;
            setTimeout(() => {
                btn.textContent = "Mua ngay";
                btn.disabled = false;
            }, 1500);
            console.log(`Đã thêm "${name}" vào giỏ hàng`);
        });
    });

    /* =========================================
       4. STATUS — charts (Chart.js)
    ========================================= */
    let statusChartsInitialized = false;

    function initStatusCharts(){
        if (statusChartsInitialized || typeof Chart === "undefined") return;
        statusChartsInitialized = true;

        const styles = getComputedStyle(document.documentElement);
        const primary = styles.getPropertyValue("--color-primary").trim() || "#ffce80";
        const danger = styles.getPropertyValue("--color-danger").trim() || "#54baf5";
        const success = styles.getPropertyValue("--color-success").trim() || "#1B9C85";
        const textColor = styles.getPropertyValue("--color-dark-variant").trim() || "#677483";
        const gridColor = "rgba(132, 139, 200, 0.15)";

        Chart.defaults.color = textColor;
        Chart.defaults.font.family = "Mukta, sans-serif";

        // -- Skill radar: what's rusty vs what still holds up
        new Chart(document.getElementById("skillRadar"), {
            type: "radar",
            data: {
                labels: ["Frontend", "Backend", "UI/UX", "Debug", "Deploy", "Kiên nhẫn"],
                datasets: [{
                    label: "Mức độ tự tin",
                    data: [80, 70, 65, 60, 55, 30],
                    backgroundColor: "rgba(255, 206, 128, 0.35)",
                    borderColor: primary,
                    pointBackgroundColor: primary,
                }],
            },
            options: {
                responsive: true,
                scales: {
                    r: {
                        angleLines: { color: gridColor },
                        grid: { color: gridColor },
                        pointLabels: { color: textColor },
                        ticks: { display: false },
                        suggestedMin: 0,
                        suggestedMax: 100,
                    },
                },
                plugins: { legend: { display: false } },
            },
        });

        // -- Activity line: a slow fade over 18 months of "nghỉ"
        const months = Array.from({ length: 18 }, (_, i) => `T-${18 - i}`);
        const activity = [95, 88, 76, 60, 45, 38, 30, 24, 20, 16, 14, 12, 10, 9, 8, 7, 6, 5];

        new Chart(document.getElementById("activityLine"), {
            type: "line",
            data: {
                labels: months,
                datasets: [{
                    label: "Hoạt động code (%)",
                    data: activity,
                    borderColor: danger,
                    backgroundColor: "rgba(84, 186, 245, 0.15)",
                    fill: true,
                    tension: 0.35,
                    pointRadius: 2,
                }],
            },
            options: {
                responsive: true,
                scales: {
                    x: { grid: { display: false } },
                    y: { grid: { color: gridColor }, suggestedMin: 0, suggestedMax: 100 },
                },
                plugins: { legend: { display: false } },
            },
        });

        // -- Time doughnut: what a rest day actually looks like
        new Chart(document.getElementById("timeDoughnut"), {
            type: "doughnut",
            data: {
                labels: ["Ngủ", "Xem code cũ", "Trading chart", "Game", "Nghĩ về deadline cũ"],
                datasets: [{
                    data: [35, 10, 20, 25, 10],
                    backgroundColor: [primary, success, danger, "#8b7bd8", "#a3bdcc"],
                    borderColor: "transparent",
                }],
            },
            options: {
                responsive: true,
                plugins: { legend: { position: "bottom", labels: { boxWidth: 10 } } },
            },
        });
    }

    /* =========================================
       5. TRADING — live charts via Binance public API
    ========================================= */
    let tradingChartsInitialized = false;

    async function fetchKlines(symbol){
        const url = `https://api.binance.com/api/v3/klines?symbol=${symbol}&interval=1h&limit=48`;
        const res = await fetch(url);
        if (!res.ok) throw new Error(`Binance API error for ${symbol}`);
        const raw = await res.json();
        // kline format: [openTime, open, high, low, close, volume, ...]
        return raw.map((k) => ({ time: k[0], close: parseFloat(k[4]) }));
    }

    function mockKlines(seedPrice){
        // fallback data so the section still looks alive if the API/network is blocked
        const points = [];
        let price = seedPrice;
        for (let i = 0; i < 48; i++) {
            price += (Math.random() - 0.5) * seedPrice * 0.01;
            points.push({ time: i, close: price });
        }
        return points;
    }

    async function renderTradingCard(card){
        const symbol = card.dataset.symbol;
        const canvas = card.querySelector(".trading-chart");
        const valueEl = card.querySelector(".tp-value");
        const changeEl = card.querySelector(".tp-change");
        const seedPrices = { BTCUSDT: 65000, BNBUSDT: 600, SOLUSDT: 150 };

        let points;
        try {
            points = await fetchKlines(symbol);
        } catch (err) {
            points = mockKlines(seedPrices[symbol] ?? 100);
        }

        const closes = points.map((p) => p.close);
        const first = closes[0];
        const last = closes[closes.length - 1];
        const pctChange = ((last - first) / first) * 100;
        const isUp = pctChange >= 0;

        valueEl.textContent = last >= 1000
            ? last.toLocaleString(undefined, { maximumFractionDigits: 0 })
            : last.toFixed(2);
        changeEl.textContent = `${isUp ? "▲" : "▼"} ${pctChange.toFixed(2)}%`;
        changeEl.classList.add(isUp ? "up" : "down");

        const lineColor = isUp ? "#1B9C85" : "#ef4444";

        new Chart(canvas, {
            type: "line",
            data: {
                labels: closes.map((_, i) => i),
                datasets: [{
                    data: closes,
                    borderColor: lineColor,
                    backgroundColor: isUp ? "rgba(27, 156, 133, 0.12)" : "rgba(239, 68, 68, 0.12)",
                    fill: true,
                    tension: 0.3,
                    pointRadius: 0,
                    borderWidth: 2,
                }],
            },
            options: {
                responsive: true,
                interaction: { intersect: false },
                scales: {
                    x: { display: false },
                    y: { display: false },
                },
                plugins: { legend: { display: false } },
            },
        });
    }

    function initTradingCharts(){
        if (tradingChartsInitialized || typeof Chart === "undefined") return;
        tradingChartsInitialized = true;
        document.querySelectorAll(".trading-card").forEach(renderTradingCard);
    }
});

function toggleDiv() {
    document.getElementById("myDiv").classList.toggle("hidden");
}