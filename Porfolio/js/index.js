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
                labels: ["Ngủ", "Xem code cũ", "Sports", "Game", "Nghĩ về deadline cũ"],
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
    initTexasHoldem(() => chips, (v) => { chips = v; renderChips(); });
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
   TEXAS HOLD'EM (heads-up vs bot)
========================================= */
const RANK_ORDER = { "2":2,"3":3,"4":4,"5":5,"6":6,"7":7,"8":8,"9":9,"10":10,"J":11,"Q":12,"K":13,"A":14 };
const HAND_NAMES = ["High Card","Một đôi","Hai đôi","Sám cô","Sảnh","Thùng","Cù lũ","Tứ quý","Thùng phá sảnh"];

function combinations(arr, k){
    const result = [];
    function helper(start, combo){
        if (combo.length === k) { result.push(combo.slice()); return; }
        for (let i = start; i < arr.length; i++) {
            combo.push(arr[i]);
            helper(i + 1, combo);
            combo.pop();
        }
    }
    helper(0, []);
    return result;
}

function evaluate5(cards){
    const ranksDesc = cards.map((c) => RANK_ORDER[c.rank]).sort((a, b) => b - a);
    const suits = cards.map((c) => c.suit);
    const isFlush = suits.every((s) => s === suits[0]);
    const uniqueDesc = [...new Set(ranksDesc)];

    let isStraight = false, straightHigh = 0;
    if (uniqueDesc.length === 5) {
        if (uniqueDesc[0] - uniqueDesc[4] === 4) { isStraight = true; straightHigh = uniqueDesc[0]; }
        else if (JSON.stringify(uniqueDesc) === JSON.stringify([14, 5, 4, 3, 2])) { isStraight = true; straightHigh = 5; }
    }

    const counts = {};
    ranksDesc.forEach((r) => (counts[r] = (counts[r] || 0) + 1));
    const groups = Object.entries(counts)
        .map(([r, c]) => ({ rank: parseInt(r, 10), count: c }))
        .sort((a, b) => b.count - a.count || b.rank - a.rank);

    if (isStraight && isFlush) return { cat: 8, tiebreak: [straightHigh] };
    if (groups[0].count === 4) return { cat: 7, tiebreak: [groups[0].rank, groups[1].rank] };
    if (groups[0].count === 3 && groups[1].count === 2) return { cat: 6, tiebreak: [groups[0].rank, groups[1].rank] };
    if (isFlush) return { cat: 5, tiebreak: ranksDesc };
    if (isStraight) return { cat: 4, tiebreak: [straightHigh] };
    if (groups[0].count === 3) {
        const kickers = groups.filter((g) => g.count === 1).map((g) => g.rank);
        return { cat: 3, tiebreak: [groups[0].rank, ...kickers] };
    }
    if (groups[0].count === 2 && groups[1].count === 2) {
        const kicker = groups[2].rank;
        return { cat: 2, tiebreak: [groups[0].rank, groups[1].rank, kicker] };
    }
    if (groups[0].count === 2) {
        const kickers = groups.filter((g) => g.count === 1).map((g) => g.rank);
        return { cat: 1, tiebreak: [groups[0].rank, ...kickers] };
    }
    return { cat: 0, tiebreak: ranksDesc };
}

function compareScore(a, b){
    if (a.cat !== b.cat) return a.cat - b.cat;
    const len = Math.max(a.tiebreak.length, b.tiebreak.length);
    for (let i = 0; i < len; i++) {
        const x = a.tiebreak[i] || 0, y = b.tiebreak[i] || 0;
        if (x !== y) return x - y;
    }
    return 0;
}

function evaluateBest(hole, community){
    const all = [...hole, ...community];
    if (all.length < 5) return { cat: 0, tiebreak: all.map((c) => RANK_ORDER[c.rank]).sort((a, b) => b - a) };
    let best = null;
    for (const combo of combinations(all, 5)) {
        const res = evaluate5(combo);
        if (!best || compareScore(res, best) > 0) best = res;
    }
    return best;
}

function preflopStrength(hole){
    const r = hole.map((c) => RANK_ORDER[c.rank]).sort((a, b) => b - a);
    if (r[0] === r[1]) return 3 + (r[0] / 14) * 4; // pocket pair, ~3..7
    const suited = hole[0].suit === hole[1].suit ? 0.6 : 0;
    const gap = r[0] - r[1];
    const connector = gap <= 1 ? 0.6 : gap <= 3 ? 0.25 : 0;
    return (r[0] / 14) * 3 + (r[1] / 14) * 1.2 + suited + connector; // ~0..4.8
}

function initTexasHoldem(getChips, setChips){
    const botCardsEl = document.getElementById("botCards");
    const communityEl = document.getElementById("communityCards");
    const playerCardsEl = document.getElementById("playerHoldemCards");
    const botChipsEl = document.getElementById("botChipsDisplay");
    const potEl = document.getElementById("potDisplay");
    const statusEl = document.getElementById("holdemStatus");
    const anteInput = document.getElementById("holdemAnte");
    const startBtn = document.getElementById("holdemStart");
    const checkCallBtn = document.getElementById("holdemCheckCall");
    const amountInput = document.getElementById("holdemAmount");
    const betRaiseBtn = document.getElementById("holdemBetRaise");
    const foldBtn = document.getElementById("holdemFold");

    if (!startBtn) return;

    let botChips = 99999999999999999;
    let deck = [], holeP = [], holeB = [], community = [];
    let pot = 0, streetP = 0, streetB = 0, stage = "idle";

    document.getElementById("resetChips")?.addEventListener("click", () => { botChips = 1000; renderBotChips(); });

    function renderBotChips(){ botChipsEl.textContent = botChips.toLocaleString(); }
    renderBotChips();

    function renderTable(revealBot){
        botCardsEl.innerHTML = "";
        holeB.forEach((c) => botCardsEl.appendChild(cardEl(c, !revealBot)));
        communityEl.innerHTML = "";
        community.forEach((c) => communityEl.appendChild(cardEl(c)));
        playerCardsEl.innerHTML = "";
        holeP.forEach((c) => playerCardsEl.appendChild(cardEl(c)));
        potEl.textContent = `Pot: ${pot}`;
    }

    function setPreActionUI(disabled){
        startBtn.disabled = !disabled;
        anteInput.disabled = !disabled;
    }

    function setActionUI(facingBet, need){
        checkCallBtn.disabled = false;
        betRaiseBtn.disabled = false;
        amountInput.disabled = false;
        foldBtn.disabled = false;
        checkCallBtn.textContent = facingBet ? `Call ${need}` : "Check";
        betRaiseBtn.textContent = facingBet ? "Raise" : "Bet";
    }

    function disableActions(){
        checkCallBtn.disabled = true;
        betRaiseBtn.disabled = true;
        amountInput.disabled = true;
        foldBtn.disabled = true;
    }

    function endHand(winner, message){
        if (winner === "player") setChips(getChips() + pot);
        else if (winner === "bot") botChips += pot;
        else { // split
            setChips(getChips() + Math.floor(pot / 2));
            botChips += Math.ceil(pot / 2);
        }
        pot = 0;
        stage = "idle";
        renderTable(true);
        statusEl.textContent = message;
        disableActions();
        setPreActionUI(true);
        renderBotChips();
    }

    function botHandStrength(){
        if (community.length === 0) return preflopStrength(holeB);
        const res = evaluateBest(holeB, community);
        return res.cat + (res.tiebreak[0] || 0) / 14;
    }

    function advanceStreet(){
        streetP = 0; streetB = 0;
        if (stage === "preflop") { community.push(deck.pop(), deck.pop(), deck.pop()); stage = "flop"; }
        else if (stage === "flop") { community.push(deck.pop()); stage = "turn"; }
        else if (stage === "turn") { community.push(deck.pop()); stage = "river"; }
        else if (stage === "river") { return showdown(); }

        renderTable(false);
        const names = { flop: "Flop", turn: "Turn", river: "River" };
        statusEl.textContent = `${names[stage]} — đến lượt bạn.`;
        setActionUI(false, 0);
    }

    function showdown(){
        stage = "showdown";
        renderTable(true);
        const playerScore = evaluateBest(holeP, community);
        const botScore = evaluateBest(holeB, community);
        const cmp = compareScore(playerScore, botScore);
        if (cmp > 0) endHand("player", `Bạn thắng với ${HAND_NAMES[playerScore.cat]}! +${pot} chips 🎉`);
        else if (cmp < 0) endHand("bot", `Bot thắng với ${HAND_NAMES[botScore.cat]}. Bạn mất ${pot} chips.`);
        else endHand("split", `Hòa (${HAND_NAMES[playerScore.cat]})! Chia đôi pot.`);
    }

    function botRespondToBet(){
        const need = streetP - streetB;
        const strength = botHandStrength();
        const callProb = Math.max(0.08, Math.min(0.95, 0.15 + strength * 0.13 + (Math.random() - 0.5) * 0.2));
        setTimeout(() => {
            if (Math.random() < callProb) {
                const pay = Math.min(need, botChips);
                botChips -= pay; pot += pay; streetB += pay;
                statusEl.textContent = `Bot call ${pay}.`;
                renderTable(false);
                advanceStreet();
            } else {
                statusEl.textContent = "Bot fold!";
                endHand("player", `Bot fold! Bạn thắng +${pot} chips 🎉`);
            }
        }, 500);
    }

    function botTurn(){
        const strength = stage === "preflop" ? preflopStrength(holeB) : botHandStrength();
        const betProb = strength > 4 ? 0.55 : strength > 2 ? 0.25 : 0.08;
        setTimeout(() => {
            if (Math.random() < betProb && botChips > 0) {
                const ante = Math.max(10, parseInt(anteInput.value, 10) || 20);
                const amount = Math.min(botChips, Math.max(ante, Math.round(pot * 0.5)));
                botChips -= amount; pot += amount; streetB += amount;
                statusEl.textContent = `Bot bet ${amount}.`;
                renderTable(false);
                setActionUI(true, streetB - streetP);
            } else {
                statusEl.textContent = "Bot check.";
                advanceStreet();
            }
        }, 500);
    }

    function playerCheckOrCall(){
        const need = streetB - streetP;
        if (need > 0) {
            const pay = Math.min(need, getChips());
            setChips(getChips() - pay); pot += pay; streetP += pay;
            statusEl.textContent = `Bạn call ${pay}.`;
            renderTable(false);
            disableActions();
            advanceStreet();
        } else {
            statusEl.textContent = "Bạn check.";
            disableActions();
            botTurn();
        }
    }

    function playerBetOrRaise(){
        const amount = Math.max(0, parseInt(amountInput.value, 10) || 0);
        if (amount <= 0) { statusEl.textContent = "Nhập số tiền hợp lệ."; return; }
        const need = streetB - streetP;
        const pay = Math.min(need + amount, getChips());
        setChips(getChips() - pay); pot += pay; streetP += pay;
        statusEl.textContent = `Bạn ${need > 0 ? "raise" : "bet"} (trả ${pay}).`;
        renderTable(false);
        disableActions();
        botRespondToBet();
    }

    function playerFold(){
        statusEl.textContent = "Bạn fold.";
        disableActions();
        endHand("bot", `Bạn fold. Bot thắng ${pot} chips.`);
    }

    startBtn.addEventListener("click", () => {
        const ante = Math.max(10, parseInt(anteInput.value, 10) || 20);
        if (ante > getChips() || ante > botChips) {
            statusEl.textContent = "Ante quá lớn so với chip hiện có (của bạn hoặc bot).";
            return;
        }
        setChips(getChips() - ante);
        botChips -= ante;
        pot = ante * 2;
        deck = freshDeck();
        holeP = [deck.pop(), deck.pop()];
        holeB = [deck.pop(), deck.pop()];
        community = [];
        streetP = 0; streetB = 0;
        stage = "preflop";

        renderTable(false);
        renderBotChips();
        statusEl.textContent = "Preflop — đến lượt bạn.";
        setPreActionUI(false);
        setActionUI(false, 0);
        amountInput.value = ante;
    });

    checkCallBtn.addEventListener("click", playerCheckOrCall);
    betRaiseBtn.addEventListener("click", playerBetOrRaise);
    foldBtn.addEventListener("click", playerFold);

    setPreActionUI(true);
    disableActions();
}
