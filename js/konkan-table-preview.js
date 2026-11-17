/* KURD HALO — Hawler table preview */
(function () {
  'use strict';
  const engine = window.KurdHaloKonkanEngine;
  const page = document.getElementById('konkanPage');
  if (!engine || !page || document.getElementById('konkanTablePreview')) return;

  const style = document.createElement('style');
  style.textContent = `
    #konkanTablePreview{border:1px solid #b58a3e;background:linear-gradient(145deg,#1c251d,#101711);border-radius:18px;padding:14px;margin:14px 0;color:#f5e8c9}
    #konkanTablePreview h3{color:#f4ca70;margin:0 0 10px}
    .kh-board{display:grid;grid-template-columns:1fr 1fr 1fr;grid-template-rows:auto auto auto;gap:8px;align-items:center;text-align:center}
    .kh-seat{border:1px solid #92713a;background:#282318;border-radius:12px;padding:10px 4px;font-size:12px;min-height:48px}
    .kh-seat strong{display:block;color:#f4d58c}
    .kh-seat small{color:#c9bda8}
    .kh-seat.top{grid-column:2;grid-row:1}
    .kh-seat.left{grid-column:1;grid-row:2}
    .kh-middle{grid-column:2;grid-row:2;border:1px solid #d2aa57;border-radius:14px;background:#332515;padding:12px 3px;font-size:12px}
    .kh-seat.right{grid-column:3;grid-row:2}
    .kh-seat.bottom{grid-column:2;grid-row:3;border-color:#d2aa57}
    .kh-pieces{display:flex;flex-wrap:wrap;gap:5px;justify-content:center;margin-top:10px}
    .kh-tile{min-width:31px;padding:8px 4px;border-radius:7px;background:linear-gradient(160deg,#fff7df,#d8c49b);color:#222;border:1px solid #a88d5c;font-weight:900;font-size:13px;box-shadow:0 2px 4px #0006}
    .kh-tile.red{color:#c32626}.kh-tile.black{color:#202020}.kh-tile.blue{color:#1767b3}.kh-tile.yellow{color:#987000}
    .kh-tile.joker{background:linear-gradient(140deg,#e9c76a,#9b6421);color:#2c1905}
    .kh-tile.antique{background:linear-gradient(140deg,#d6b46d,#70502a);color:#fff}
    #khDealButton{width:100%;margin-top:12px}
    .kh-disclaimer{font-size:12px;line-height:1.7;color:#d5c7a9;margin:8px 0}
  `;
  document.head.appendChild(style);

  const panel = document.createElement('section');
  panel.id = 'konkanTablePreview';
  panel.innerHTML = `
    <h3>🀄 مێزی کۆنکانی هەولێر</h3>
    <p class="kh-disclaimer">پێشانگای دابەشکردنی کاشییەکان — ئەم قۆناغە تەنها بۆ تاقیکردنەوەی یاسا و ڕووکارە؛ هێشتا یاریی ئۆنلاین و نۆرەی یاریزانان چالاک نییە.</p>
    <div class="kh-board">
      <div class="kh-seat top"><strong>🔵 یاریزانی ٢</strong><small>تیمی B</small><div id="khCount2">١٤ کاشی</div></div>
      <div class="kh-seat left"><strong>🟡 یاریزانی ٤</strong><small>تیمی A • هاوتیمی تۆ</small><div id="khCount4">١٤ کاشی</div></div>
      <div class="kh-middle">🏛️ مێزی هەولێر<br><strong id="khCapTile">کاپ</strong><br><small id="khDeckCount">کۆمەڵەی کاشی</small></div>
      <div class="kh-seat right"><strong>🔵 یاریزانی ٣</strong><small>تیمی B</small><div id="khCount3">١٤ کاشی</div></div>
      <div class="kh-seat bottom"><strong>🟡 تۆ • یاریزانی ١</strong><small>تیمی A</small><div id="khCount1">١٤ کاشی</div></div>
    </div>
    <div style="margin-top:12px;color:#f4ca70;font-weight:800">کاشییەکانی تۆ</div>
    <div id="khMyHand" class="kh-pieces"><span class="kh-disclaimer">بۆ دەستپێکردن، دوگمەی خوارەوە دابگرە.</span></div>
    <p id="khDealStatus" class="kh-disclaimer" aria-live="polite">ئامادەی دابەشکردنی ١٥ و ١٤ کاشی.</p>
    <button type="button" id="khDealButton">🎲 دابەشکردنی کاشییەکان</button>
  `;
  const spin = document.getElementById('konkanDailySpinPanel');
  if (spin) page.insertBefore(panel, spin);
  else page.appendChild(panel);

  const digits = n => String(n).replace(/\d/g, d => '٠١٢٣٤٥٦٧٨٩'[Number(d)]);
  const names = {red:'سوور',black:'ڕەش',blue:'شین',yellow:'زەرد'};
  const label = tile => {
    if (tile.kind === 'joker') return 'جوکەر';
    if (tile.kind === 'antique') return 'ئەنتیک';
    return tile.number === 1 ? 'A' : String(tile.number);
  };
  const hand = document.getElementById('khMyHand');
  const status = document.getElementById('khDealStatus');
  const cap = document.getElementById('khCapTile');
  const button = document.getElementById('khDealButton');

  button.addEventListener('click', () => {
    try {
      const round = engine.prepareRound();
      const myTiles = round.hands[0];
      hand.innerHTML = '';
      myTiles.forEach(tile => {
        const el = document.createElement('span');
        el.className = 'kh-tile ' + (tile.kind === 'number' ? tile.color : tile.kind);
        el.textContent = label(tile);
        el.title = tile.kind === 'number' ? names[tile.color] + ' ' + tile.number : label(tile);
        hand.appendChild(el);
      });
      cap.textContent = label(round.cap) + (round.cap.color ? ' • ' + names[round.cap.color] : '');
      document.getElementById('khDeckCount').textContent = digits(round.drawPile.length) + ' کاشی ماوەتەوە';
      [1,2,3,4].forEach(n => {
        const count = round.hands[n-1].length;
        document.getElementById('khCount'+n).textContent = digits(count) + ' کاشی';
      });
      status.textContent = 'کاپ دیاری کرا؛ کاپ لە یاری دەرکرا. جوکەر: ' + names[round.jokerIdentity.color] + ' ' + round.jokerIdentity.number + '. سەرکردە: یاریزانی ' + (round.captain+1) + '.';
      button.textContent = '🔄 دابەشکردنەوەی کاشییەکان';
    } catch (error) {
      status.textContent = 'هەڵە لە دابەشکردنی کاشی: ' + (error.message || error);
    }
  });
})();
