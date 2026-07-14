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
    /* =========================================
       6. GAME ZONE — chips, Blackjack, Video Poker
    ========================================= */
    initGameZone();
});

function toggleDiv() {
    document.getElementById("myDiv").classList.toggle("hidden");
}

/* ---------- shared deck helpers ---------- */
const SUITS = ["♠", "♥", "♦", "♣"];
const RANKS = ["2","3","4","5","6","7","8","9","10","J","Q","K","A"];

function freshDeck(){
    const deck = [];
    for (const s of SUITS) {
        for (const r of RANKS) {
            deck.push({ rank: r, suit: s, red: s === "♥" || s === "♦" });
        }
    }
    for (let i = deck.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [deck[i], deck[j]] = [deck[j], deck[i]];
    }
    return deck;
}

function cardEl(card, faceDown = false, extraClass = ""){
    const el = document.createElement("div");
    el.className = `playing-card ${extraClass} ${faceDown ? "card-back" : (card.red ? "red" : "black")}`;
    if (!faceDown) {
        el.innerHTML = `<span>${card.rank}</span><span class="suit-icon">${card.suit}</span>`;
    }
    return el;
}

/* =========================================
   GAME ZONE bootstrap
========================================= */
function initGameZone(){
    const chipEl = document.getElementById("chipBalance");
    const resetBtn = document.getElementById("resetChips");
    if (!chipEl) return; // section not present on this page

    let chips = parseInt(localStorage.getItem("chips") || "1000", 10);

    function renderChips(){
        chipEl.textContent = chips.toLocaleString();
        localStorage.setItem("chips", chips);
    }
    renderChips();

    resetBtn.addEventListener("click", () => {
        chips = 1000;
        renderChips();
    });

    // tab switching
    document.querySelectorAll(".game-tab-btn").forEach((btn) => {
        btn.addEventListener("click", () => {
            document.querySelectorAll(".game-tab-btn").forEach((b) => b.classList.remove("active"));
            btn.classList.add("active");
            document.querySelectorAll(".game-panel").forEach((p) => p.classList.remove("active-panel"));
            const target = btn.dataset.game === "blackjack" ? "blackjackPanel" : "pokerPanel";
            document.getElementById(target).classList.add("active-panel");
        });
    });

    initBlackjack(() => chips, (v) => { chips = v; renderChips(); });
    initVideoPoker(() => chips, (v) => { chips = v; renderChips(); });
}

/* =========================================
   BLACKJACK
========================================= */
function initBlackjack(getChips, setChips){
    const dealerCardsEl = document.getElementById("dealerCards");
    const playerCardsEl = document.getElementById("playerCards");
    const dealerScoreEl = document.getElementById("dealerScore");
    const playerScoreEl = document.getElementById("playerScore");
    const statusEl = document.getElementById("bjStatus");
    const betInput = document.getElementById("bjBet");
    const dealBtn = document.getElementById("bjDeal");
    const hitBtn = document.getElementById("bjHit");
    const standBtn = document.getElementById("bjStand");
    const doubleBtn = document.getElementById("bjDouble");

    if (!dealBtn) return;

    let deck = [];
    let player = [];
    let dealer = [];
    let currentBet = 0;
    let roundOver = true;

    function handValue(hand){
        let total = 0, aces = 0;
        for (const c of hand) {
            if (c.rank === "A") { total += 11; aces++; }
            else if (["K","Q","J"].includes(c.rank)) total += 10;
            else total += parseInt(c.rank, 10);
        }
        while (total > 21 && aces > 0) { total -= 10; aces--; }
        return total;
    }

    function renderHands(hideDealerHole){
        dealerCardsEl.innerHTML = "";
        dealer.forEach((c, i) => dealerCardsEl.appendChild(cardEl(c, hideDealerHole && i === 1)));
        playerCardsEl.innerHTML = "";
        player.forEach((c) => playerCardsEl.appendChild(cardEl(c)));

        playerScoreEl.textContent = handValue(player);
        dealerScoreEl.textContent = hideDealerHole ? "?" : handValue(dealer);
    }

    function setControls({ deal, actions }){
        dealBtn.disabled = !deal;
        betInput.disabled = !deal;
        hitBtn.disabled = !actions;
        standBtn.disabled = !actions;
        doubleBtn.disabled = !actions || getChips() < currentBet;
    }

    function endRound(message, delta){
        roundOver = true;
        setChips(getChips() + delta);
        statusEl.textContent = message;
        renderHands(false);
        setControls({ deal: true, actions: false });
    }

    function dealerPlay(){
        while (handValue(dealer) < 17) dealer.push(deck.pop());
        const p = handValue(player);
        const d = handValue(dealer);

        if (d > 21) return endRound(`Dealer quắc (${d})! Bạn thắng +${currentBet}`, currentBet * 2);
        if (d > p) return endRound(`Dealer thắng với ${d} vs ${p}.`, 0);
        if (d < p) return endRound(`Bạn thắng ${p} vs ${d}! +${currentBet}`, currentBet * 2);
        return endRound(`Hòa (push) ${p} vs ${d}. Hoàn cược.`, currentBet);
    }

    dealBtn.addEventListener("click", () => {
        const bet = parseInt(betInput.value, 10) || 0;
        if (bet < 10) { statusEl.textContent = "Cược tối thiểu 10 chips."; return; }
        if (bet > getChips()) { statusEl.textContent = "Không đủ chips!"; return; }

        currentBet = bet;
        setChips(getChips() - bet);
        deck = freshDeck();
        player = [deck.pop(), deck.pop()];
        dealer = [deck.pop(), deck.pop()];
        roundOver = false;

        renderHands(true);
        setControls({ deal: false, actions: true });

        const p = handValue(player);
        if (p === 21) {
            const blackjackWin = Math.floor(currentBet * 2.5);
            statusEl.textContent = "Blackjack! 🎉";
            return endRound("Blackjack! Bạn thắng x2.5 cược.", blackjackWin);
        }
        statusEl.textContent = "Hit để rút thêm bài, hoặc Stand để dừng.";
    });

    hitBtn.addEventListener("click", () => {
        if (roundOver) return;
        player.push(deck.pop());
        const p = handValue(player);
        renderHands(true);
        if (p > 21) endRound(`Quắc bài (${p})! Bạn thua ${currentBet}.`, 0);
        else doubleBtn.disabled = true; // can only double on first decision
    });

    standBtn.addEventListener("click", () => {
        if (roundOver) return;
        setControls({ deal: false, actions: false });
        renderHands(false);
        dealerPlay();
    });

    doubleBtn.addEventListener("click", () => {
        if (roundOver || getChips() < currentBet) return;
        setChips(getChips() - currentBet);
        currentBet *= 2;
        player.push(deck.pop());
        const p = handValue(player);
        renderHands(true);
        if (p > 21) { endRound(`Quắc bài (${p})! Bạn thua ${currentBet}.`, 0); return; }
        setControls({ deal: false, actions: false });
        dealerPlay();
    });

    setControls({ deal: true, actions: false });
}

/* =========================================
   VIDEO POKER (Jacks or Better)
========================================= */
function initVideoPoker(getChips, setChips){
    const cardsEl = document.getElementById("pokerCards");
    const statusEl = document.getElementById("pokerStatus");
    const betInput = document.getElementById("pokerBet");
    const dealBtn = document.getElementById("pokerDeal");
    const drawBtn = document.getElementById("pokerDraw");

    if (!dealBtn) return;

    let deck = [];
    let hand = [];
    let held = [false, false, false, false, false];
    let currentBet = 0;
    let stage = "idle"; // idle -> dealt -> idle

    const RANK_ORDER = { "2":2,"3":3,"4":4,"5":5,"6":6,"7":7,"8":8,"9":9,"10":10,"J":11,"Q":12,"K":13,"A":14 };

    function renderHand(){
        cardsEl.innerHTML = "";
        hand.forEach((c, i) => {
            const el = cardEl(c, false, "poker-card");
            if (held[i]) el.classList.add("held");
            el.addEventListener("click", () => {
                if (stage !== "dealt") return;
                held[i] = !held[i];
                renderHand();
            });
            cardsEl.appendChild(el);
        });
    }

    function evaluateHand(cards){
        const ranks = cards.map((c) => RANK_ORDER[c.rank]).sort((a, b) => a - b);
        const suits = cards.map((c) => c.suit);
        const counts = {};
        ranks.forEach((r) => (counts[r] = (counts[r] || 0) + 1));
        const groups = Object.values(counts).sort((a, b) => b - a);
        const isFlush = suits.every((s) => s === suits[0]);
        const uniqueRanks = [...new Set(ranks)];
        let isStraight = uniqueRanks.length === 5 && (ranks[4] - ranks[0] === 4);
        // wheel: A-2-3-4-5
        const isWheel = JSON.stringify(uniqueRanks) === JSON.stringify([2,3,4,5,14]);
        if (isWheel) isStraight = true;

        if (isStraight && isFlush && ranks[4] === 14 && !isWheel) return { name: "Royal Flush", mult: 250 };
        if (isStraight && isFlush) return { name: "Straight Flush", mult: 50 };
        if (groups[0] === 4) return { name: "Tứ quý", mult: 25 };
        if (groups[0] === 3 && groups[1] === 2) return { name: "Cù lũ", mult: 9 };
        if (isFlush) return { name: "Thùng", mult: 6 };
        if (isStraight) return { name: "Sảnh", mult: 4 };
        if (groups[0] === 3) return { name: "Sám cô", mult: 3 };
        if (groups[0] === 2 && groups[1] === 2) return { name: "Hai đôi", mult: 2 };
        if (groups[0] === 2) {
            const pairRank = Object.keys(counts).find((k) => counts[k] === 2);
            if (parseInt(pairRank, 10) >= 11) return { name: "Đôi J trở lên", mult: 1 };
        }
        return { name: "Không trúng", mult: 0 };
    }

    function setControls({ deal, draw }){
        dealBtn.disabled = !deal;
        betInput.disabled = !deal;
        drawBtn.disabled = !draw;
    }

    dealBtn.addEventListener("click", () => {
        const bet = parseInt(betInput.value, 10) || 0;
        if (bet < 10) { statusEl.textContent = "Cược tối thiểu 10 chips."; return; }
        if (bet > getChips()) { statusEl.textContent = "Không đủ chips!"; return; }

        currentBet = bet;
        setChips(getChips() - bet);
        deck = freshDeck();
        hand = [deck.pop(), deck.pop(), deck.pop(), deck.pop(), deck.pop()];
        held = [false, false, false, false, false];
        stage = "dealt";

        renderHand();
        statusEl.textContent = "Bấm vào lá muốn giữ, rồi bấm Draw.";
        setControls({ deal: false, draw: true });
    });

    drawBtn.addEventListener("click", () => {
        hand = hand.map((c, i) => (held[i] ? c : deck.pop()));
        stage = "idle";
        renderHand();

        const result = evaluateHand(hand);
        const winnings = currentBet * result.mult;
        if (winnings > 0) {
            setChips(getChips() + winnings);
            statusEl.textContent = `${result.name}! Thắng +${winnings} chips 🎉`;
        } else {
            statusEl.textContent = `${result.name}. Thua ${currentBet} chips, chúc may mắn lần sau.`;
        }
        setControls({ deal: true, draw: false });
    });

    setControls({ deal: true, draw: false });
}