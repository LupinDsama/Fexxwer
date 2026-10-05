document.addEventListener("DOMContentLoaded", () => {
  /* SPA navigation. Preserve labels and ids. */
  const links = Array.from(document.querySelectorAll("[data-nav]"));
  const sections = Array.from(document.querySelectorAll(".tab-content"));

  /* Reveal on scroll via IntersectionObserver (no scroll listener). Defined
     before first showSection call so the first call can observe. */
  let observer = null;
  if ("IntersectionObserver" in window) {
    observer = new IntersectionObserver((entries) => {
      entries.forEach((en) => {
        if (en.isIntersecting) { en.target.classList.add("in"); observer.unobserve(en.target); }
      });
    }, { threshold: 0.08 });
  }
  function observeReveals(root) {
    const els = (root || document).querySelectorAll(".reveal:not(.in)");
    if (!observer) { els.forEach((el) => el.classList.add("in")); return; }
    els.forEach((el) => observer.observe(el));
    /* Safety: never leave above fold hidden if IO misfires in some webview. */
    setTimeout(() => {
      els.forEach((el) => {
        if (!el.classList.contains("in") && el.getBoundingClientRect().top < window.innerHeight * 0.9) {
          el.classList.add("in");
        }
      });
    }, 700);
  }

  function showSection(id) {
    sections.forEach((s) => s.classList.toggle("active-section", s.id === id));
    links.forEach((a) => {
      const on = a.getAttribute("href") === "#" + id;
      a.classList.toggle("active", on);
      if (on) a.setAttribute("aria-current", "page");
      else a.removeAttribute("aria-current");
    });
    if (id === "status") initStatusCharts();
    if (id === "trading") initTradingCharts();
    const sec = document.getElementById(id);
    if (sec) observeReveals(sec);
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  links.forEach((link) => {
    link.addEventListener("click", (e) => {
      e.preventDefault();
      const id = link.getAttribute("href").slice(1);
      try { localStorage.setItem("activePage", "#" + id); } catch (_) {}
      showSection(id);
      closeMobile();
    });
  });

  const saved = (() => { try { return localStorage.getItem("activePage"); } catch (_) { return null; } })();
  if (saved && document.getElementById(saved.slice(1))) showSection(saved.slice(1));
  else showSection("home");

  /* Theme: dual mode, respect system by default. */
  const root = document.documentElement;
  const themeBtns = document.querySelectorAll("[data-theme-btn]");
  const applyTheme = (t) => {
    root.setAttribute("data-theme", t);
    themeBtns.forEach((b) => {
      const icon = b.querySelector(".material-icons-sharp");
      if (icon) icon.textContent = t === "dark" ? "light_mode" : "dark_mode";
      b.setAttribute("aria-label", t === "dark" ? "Chuyen sang giao dien sang" : "Chuyen sang giao dien toi");
    });
    try { localStorage.setItem("theme", t); } catch (_) {}
  };
  let initial = (() => { try { return localStorage.getItem("theme"); } catch (_) { return null; } })();
  if (!initial) initial = window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  applyTheme(initial);
  themeBtns.forEach((b) => b.addEventListener("click", () => {
    applyTheme(root.getAttribute("data-theme") === "dark" ? "light" : "dark");
  }));

  /* Mobile drawer = bottom bar only, plus burger scrolls to nav. */
  const burger = document.getElementById("burger");
  const mobilebar = document.getElementById("mobilebar");
  function closeMobile() { if (burger) burger.setAttribute("aria-expanded", "false"); }
  if (burger && mobilebar) {
    burger.addEventListener("click", () => {
      const open = burger.getAttribute("aria-expanded") === "true";
      burger.setAttribute("aria-expanded", String(!open));
      mobilebar.scrollIntoView({ behavior: "smooth", block: "nearest" });
    });
  }

  /* Typing effect, plain copy, no emoji. */
  const typedEl = document.getElementById("typedRole");
  if (typedEl) {
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const roles = ["Roblox Scripter", "Gameplay Programmer", "Blender Artist", "UI Builder"];
    if (reduce) { typedEl.textContent = roles[0]; }
    else {
      let ri = 0, ci = 0, del = false;
      (function loop() {
        const cur = roles[ri];
        ci += del ? -1 : 1;
        typedEl.textContent = cur.slice(0, ci);
        let wait = del ? 35 : 75;
        if (!del && ci === cur.length) { del = true; wait = 1300; }
        else if (del && ci === 0) { del = false; ri = (ri + 1) % roles.length; wait = 250; }
        setTimeout(loop, wait);
      })();
    }
  }

  /* Reveal on scroll via IntersectionObserver (no scroll listener). */
  observeReveals(document);
  document.querySelectorAll(".reveal").forEach((el) => observer && observer.observe(el));

  /* Shop buttons with pressed feedback and live label. */
  document.querySelectorAll(".buy-btn").forEach((btn) => {
    btn.addEventListener("click", () => {
      const card = btn.closest(".product-card, .shop-featured-body");
      const name = card?.querySelector("h3")?.textContent ?? "san pham";
      const old = btn.textContent;
      btn.textContent = "Da them vao gio";
      btn.disabled = true;
      setTimeout(() => { btn.textContent = old; btn.disabled = false; }, 1400);
      const note = document.getElementById("cartNote");
      if (note) note.textContent = "Gio hang: " + name;
    });
  });

  /* To top. */
  const toTop = document.getElementById("toTop");
  if (toTop) toTop.addEventListener("click", () => window.scrollTo({ top: 0, behavior: "smooth" }));

  /* Footer year. */
  const year = document.getElementById("year");
  if (year) year.textContent = String(new Date().getFullYear());

  /* STATUS charts, lazy init once. */
  let statusDone = false;
  function initStatusCharts() {
    if (statusDone || typeof Chart === "undefined") return;
    const c1 = document.getElementById("skillRadar");
    const c2 = document.getElementById("activityLine");
    const c3 = document.getElementById("timeDoughnut");
    if (!c1 || !c2 || !c3) return;
    statusDone = true;
    const accent = getComputedStyle(document.documentElement).getPropertyValue("--accent").trim() || "#e14e1b";
    Chart.defaults.font.family = "'Be Vietnam Pro', system-ui, sans-serif";
    new Chart(c1, {
      type: "radar",
      data: { labels: ["Frontend", "Gameplay", "UI", "Debug", "Deploy", "Blender"], datasets: [{ data: [82, 88, 74, 70, 62, 66], backgroundColor: "rgba(225,78,27,.18)", borderColor: accent, pointBackgroundColor: accent, borderWidth: 2 }] },
      options: { responsive: true, scales: { r: { suggestedMin: 0, suggestedMax: 100, ticks: { display: false } } }, plugins: { legend: { display: false } } }
    });
    new Chart(c2, {
      type: "line",
      data: { labels: Array.from({ length: 18 }, (_, i) => "T" + (i + 1)), datasets: [{ data: [95, 88, 76, 60, 45, 38, 30, 24, 20, 16, 14, 12, 10, 9, 8, 7, 6, 5], borderColor: accent, backgroundColor: "rgba(225,78,27,.12)", fill: true, tension: 0.35, pointRadius: 0, borderWidth: 2 }] },
      options: { responsive: true, scales: { x: { grid: { display: false } }, y: { suggestedMin: 0, suggestedMax: 100 } }, plugins: { legend: { display: false } } }
    });
    new Chart(c3, {
      type: "doughnut",
      data: { labels: ["Ngu", "Doc code cu", "The thao", "Game", "Hoc them"], datasets: [{ data: [35, 10, 20, 25, 10], backgroundColor: [accent, "#177b57", "#4d7dd1", "#8b7bd8", "#b9b3a6"], borderWidth: 0 }] },
      options: { responsive: true, plugins: { legend: { position: "bottom", labels: { boxWidth: 10 } } } }
    });
  }

  /* TRADING charts via Binance, fallback mock. */
  let tradingDone = false;
  async function fetchKlines(symbol) {
    const res = await fetch("https://api.binance.com/api/v3/klines?symbol=" + symbol + "&interval=1h&limit=48");
    if (!res.ok) throw new Error("api");
    const raw = await res.json();
    return raw.map((k) => parseFloat(k[4]));
  }
  function mock(seed) {
    let p = seed; const out = [];
    for (let i = 0; i < 48; i++) { p += (Math.random() - 0.5) * seed * 0.012; out.push(p); }
    return out;
  }
  async function renderCard(card) {
    const symbol = card.dataset.symbol;
    const canvas = card.querySelector("canvas");
    const vEl = card.querySelector(".tp-value");
    const cEl = card.querySelector(".tp-change");
    const seeds = { BTCUSDT: 67000, BNBUSDT: 590, SOLUSDT: 145 };
    let closes;
    try { closes = await fetchKlines(symbol); }
    catch (_) { closes = mock(seeds[symbol] || 100); }
    const first = closes[0], last = closes[closes.length - 1];
    const pct = ((last - first) / first) * 100;
    const up = pct >= 0;
    vEl.textContent = last >= 1000 ? Math.round(last).toLocaleString("en-US") : last.toFixed(2);
    cEl.textContent = (up ? "▲ " : "▼ ") + Math.abs(pct).toFixed(2) + "% (48h)";
    cEl.classList.add(up ? "up" : "down");
    card.querySelector(".skeleton")?.remove();
    new Chart(canvas, {
      type: "line",
      data: { labels: closes.map((_, i) => i), datasets: [{ data: closes, borderColor: up ? "#177b57" : "#d43a2f", backgroundColor: up ? "rgba(23,123,87,.12)" : "rgba(212,58,47,.12)", fill: true, tension: 0.3, pointRadius: 0, borderWidth: 2 }] },
      options: { responsive: true, scales: { x: { display: false }, y: { display: false } }, plugins: { legend: { display: false }, tooltip: { enabled: true } } }
    });
  }
  function initTradingCharts() {
    if (tradingDone || typeof Chart === "undefined") return;
    tradingDone = true;
    document.querySelectorAll(".trading-card").forEach(renderCard);
  }

  /* Game zone: chips, blackjack, holdem. No-op if section absent. */
  try { initGameZone(); } catch (_) {}
});

/* ---------- shared deck helpers ---------- */
const SUITS = ["\u2660", "\u2665", "\u2666", "\u2663"];
const RANKS = ["2","3","4","5","6","7","8","9","10","J","Q","K","A"];

function freshDeck(){
    const deck = [];
    for (const s of SUITS) {
        for (const r of RANKS) {
            deck.push({ rank: r, suit: s, red: s === "\u2665" || s === "\u2666" });
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

/* GAME ZONE bootstrap */
function initGameZone(){
    const chipEl = document.getElementById("chipBalance");
    const resetBtn = document.getElementById("resetChips");
    if (!chipEl) return;

    let chips = parseInt(localStorage.getItem("chips") || "1000", 10);

    function renderChips(){
        chipEl.textContent = chips.toLocaleString();
        localStorage.setItem("chips", chips);
    }
    renderChips();

    if (resetBtn) resetBtn.addEventListener("click", () => {
        chips = 1000;
        renderChips();
    });

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

/* BLACKJACK */
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

        if (d > 21) return endRound(`Dealer quac (${d}). Ban thang +${currentBet}`, currentBet * 2);
        if (d > p) return endRound(`Dealer thang voi ${d} vs ${p}.`, 0);
        if (d < p) return endRound(`Ban thang ${p} vs ${d}. +${currentBet}`, currentBet * 2);
        return endRound(`Hoa ${p} vs ${d}. Hoan cuoc.`, currentBet);
    }

    dealBtn.addEventListener("click", () => {
        const bet = parseInt(betInput.value, 10) || 0;
        if (bet < 10) { statusEl.textContent = "Cuoc toi thieu 10 chips."; return; }
        if (bet > getChips()) { statusEl.textContent = "Khong du chips."; return; }

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
            return endRound("Blackjack. Ban thang gap 2.5 lan cuoc.", blackjackWin);
        }
        statusEl.textContent = "Rut de lay them bai, hoac Dung de giu diem.";
    });

    hitBtn.addEventListener("click", () => {
        if (roundOver) return;
        player.push(deck.pop());
        const p = handValue(player);
        renderHands(true);
        if (p > 21) endRound(`Quac bai (${p}). Ban thua ${currentBet}.`, 0);
        else doubleBtn.disabled = true;
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
        if (p > 21) { endRound(`Quac bai (${p}). Ban thua ${currentBet}.`, 0); return; }
        setControls({ deal: false, actions: false });
        dealerPlay();
    });

    setControls({ deal: true, actions: false });
}

/* TEXAS HOLDEM (heads-up vs bot) */
const RANK_ORDER = { "2":2,"3":3,"4":4,"5":5,"6":6,"7":7,"8":8,"9":9,"10":10,"J":11,"Q":12,"K":13,"A":14 };
const HAND_NAMES = ["Mau thau","Mot doi","Hai doi","Sam co","Sanh","Thung","Cu lu","Tu quy","Thung pha sanh"];

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
    if (r[0] === r[1]) return 3 + (r[0] / 14) * 4;
    const suited = hole[0].suit === hole[1].suit ? 0.6 : 0;
    const gap = r[0] - r[1];
    const connector = gap <= 1 ? 0.6 : gap <= 3 ? 0.25 : 0;
    return (r[0] / 14) * 3 + (r[1] / 14) * 1.2 + suited + connector;
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

    let botChips = 1000;
    let deck = [], holeP = [], holeB = [], community = [];
    let pot = 0, streetP = 0, streetB = 0, stage = "idle";

    document.getElementById("resetChips")?.addEventListener("click", () => { botChips = 1000; renderBotChips(); });

    function renderBotChips(){ if (botChipsEl) botChipsEl.textContent = botChips.toLocaleString(); }
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
        else {
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
        statusEl.textContent = `${names[stage]}. Den luot ban.`;
        setActionUI(false, 0);
    }

    function showdown(){
        stage = "showdown";
        renderTable(true);
        const playerScore = evaluateBest(holeP, community);
        const botScore = evaluateBest(holeB, community);
        const cmp = compareScore(playerScore, botScore);
        if (cmp > 0) endHand("player", `Ban thang voi ${HAND_NAMES[playerScore.cat]}. +${pot} chips`);
        else if (cmp < 0) endHand("bot", `Bot thang voi ${HAND_NAMES[botScore.cat]}. Ban mat ${pot} chips.`);
        else endHand("split", `Hoa (${HAND_NAMES[playerScore.cat]}). Chia doi pot.`);
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
                statusEl.textContent = "Bot bo bai.";
                endHand("player", `Bot bo bai. Ban thang +${pot} chips`);
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
            statusEl.textContent = `Ban call ${pay}.`;
            renderTable(false);
            disableActions();
            advanceStreet();
        } else {
            statusEl.textContent = "Ban check.";
            disableActions();
            botTurn();
        }
    }

    function playerBetOrRaise(){
        const amount = Math.max(0, parseInt(amountInput.value, 10) || 0);
        if (amount <= 0) { statusEl.textContent = "Nhap so tien hop le."; return; }
        const need = streetB - streetP;
        const pay = Math.min(need + amount, getChips());
        setChips(getChips() - pay); pot += pay; streetP += pay;
        statusEl.textContent = `Ban ${need > 0 ? "raise" : "bet"} (tra ${pay}).`;
        renderTable(false);
        disableActions();
        botRespondToBet();
    }

    function playerFold(){
        statusEl.textContent = "Ban bo bai.";
        disableActions();
        endHand("bot", `Ban bo bai. Bot thang ${pot} chips.`);
    }

    startBtn.addEventListener("click", () => {
        const ante = Math.max(10, parseInt(anteInput.value, 10) || 20);
        if (ante > getChips() || ante > botChips) {
            statusEl.textContent = "Ante qua lon so voi chip hien co.";
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
        statusEl.textContent = "Preflop. Den luot ban.";
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
